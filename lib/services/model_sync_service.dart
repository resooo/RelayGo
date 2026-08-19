import 'package:hive_flutter/hive_flutter.dart';
import 'package:relaygo/database/model_repository.dart';
import 'package:relaygo/models/api_key.dart';
import 'package:relaygo/models/model_info.dart';
import 'package:relaygo/models/model_sync_exception.dart';
import 'package:relaygo/models/provider_config.dart';
import 'package:relaygo/services/key_manager.dart';
import 'package:relaygo/services/model_normalizer.dart';
import 'package:relaygo/services/providers/base_provider.dart';
import 'package:relaygo/services/providers/provider_factory.dart';

/// 同步状态
enum SyncStatus { syncing, completed, failed }

/// 单个服务商的同步进度
class SyncProgress {
  final String provider;
  final SyncStatus status;
  final String message;
  SyncProgress(this.provider, this.status, this.message);
}

/// 单个服务商同步结果
class ProviderSyncResult {
  final String provider;
  final bool success;
  final List<ModelInfo> models;
  final int newModels;
  final int updatedModels;
  final int removedModels;
  final String? error;

  ProviderSyncResult({
    required this.provider,
    required this.success,
    this.models = const [],
    this.newModels = 0,
    this.updatedModels = 0,
    this.removedModels = 0,
    this.error,
  });
}

/// 整体同步结果（含各服务商明细与总量）
class SyncResult {
  final int timestamp;
  final Map<String, ProviderSyncResult> providerResults;
  final int totalModels;

  SyncResult({
    required this.timestamp,
    required this.providerResults,
    required this.totalModels,
  });

  int get successCount =>
      providerResults.values.where((r) => r.success).length;
  int get failedCount => providerResults.length - successCount;
  int get newCount =>
      providerResults.values.fold(0, (s, r) => s + r.newModels);
  int get updatedCount =>
      providerResults.values.fold(0, (s, r) => s + r.updatedModels);
  int get removedCount =>
      providerResults.values.fold(0, (s, r) => s + r.removedModels);
}

/// 待同步的 (provider 类型, providerId) 对
///
/// [type] 为 ProviderType.name（openai/anthropic/.../custom）；
/// [id] 为同步/展示用的标识：custom 提供商用 providerId（如 sensetime），
/// 非 custom 提供商用 provider 名本身。
class SyncTarget {
  final String type;
  final String id;
  const SyncTarget(this.type, this.id);
}

/// 模型列表同步服务
///
/// 遍历「拥有 active key 的」服务商，并行拉取各服务商模型列表，
/// 统一格式后合并进 [ModelRepository]，并标记新增/更新/已下线模型。
///
/// 支持进度回调与可取消（[isCancelled] 返回 true 时尽快中止）。
class ModelSyncService {
  final KeyManager keyManager;
  final ModelRepository repository;
  final BaseProvider Function(ProviderType) providerResolver;
  final Duration timeout;
  final Box? historyBox;

  ModelSyncService(
    this.keyManager,
    this.repository, {
    this.providerResolver = providerFor,
    this.timeout = const Duration(seconds: 25),
    this.historyBox,
  });

  /// 拥有 active key 的 [SyncTarget] 列表（去重）
  ///
  /// 非 custom 提供商统一按 provider 名同步；
  /// custom 提供商按各自 providerId 单独同步，确保各自定义服务的模型归入正确名称。
  List<SyncTarget> get activeProviderIds {
    final map = <String, Set<String>>{};
    for (final k in keyManager.getAll()) {
      if (k.status != KeyStatus.active) continue;
      if (k.provider == 'custom' && k.providerId.isNotEmpty) {
        map.putIfAbsent('custom', () => <String>{}).add(k.providerId);
      } else {
        map.putIfAbsent(k.provider, () => <String>{}).add(k.provider);
      }
    }
    final result = <SyncTarget>[];
    for (final e in map.entries) {
      for (final id in e.value) {
        result.add(SyncTarget(e.key, id));
      }
    }
    return result;
  }

  /// 同步所有服务商（并发）
  ///
  /// 自定义提供商（provider='custom'）按 providerId 分别同步，
  /// 确保商汤、DeepSeek 等各自独立拉取模型列表并存为各自名称。
  Future<SyncResult> syncAll({
    void Function(SyncProgress)? onProgress,
    bool Function()? isCancelled,
    bool autoDisableRemoved = true,
  }) async {
    final pairs = activeProviderIds;
    final results = <String, ProviderSyncResult>{};
    if (pairs.isEmpty) {
      final empty = SyncResult(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        providerResults: const {},
        totalModels: 0,
      );
      await _saveHistory(empty);
      return empty;
    }

    final futures = pairs.map((pair) async {
      final display = pair.id; // 显示名：providerId（如 sensetime）或 provider 名（如 openai）
      if (isCancelled?.call() == true) {
        return MapEntry(
            display,
            ProviderSyncResult(
                provider: display, success: false, error: '已取消'));
      }
      onProgress?.call(SyncProgress(display, SyncStatus.syncing, '正在同步 $display 的模型列表...'));
      ProviderSyncResult r;
      try {
        r = await syncProvider(pair.type, providerId: pair.id,
            isCancelled: isCancelled, autoDisableRemoved: autoDisableRemoved);
      } catch (e) {
        r = ProviderSyncResult(
            provider: display, success: false, error: ModelSyncException.friendly(e));
      }
      onProgress?.call(SyncProgress(
        display,
        r.success ? SyncStatus.completed : SyncStatus.failed,
        r.success
            ? '$display 同步完成，共 ${r.models.length} 个模型'
            : '$display 同步失败：${r.error ?? ''}',
      ));
      return MapEntry(display, r);
    });

    final entries = await Future.wait(futures);
    for (final e in entries) {
      results[e.key] = e.value;
    }

    final result = SyncResult(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      providerResults: results,
      totalModels: results.values.fold(0, (s, r) => s + r.models.length),
    );
    await _saveHistory(result);
    return result;
  }

  /// 同步单个服务商
  ///
  /// [provider] 为 ProviderType.name（openai/anthropic/.../custom），
  /// 或自定义提供商 ID（如 sensetime，此时按 custom + providerId 处理）。
  /// [providerId] 可选：当 [provider] 为 custom 时，用于定位具体自定义提供商
  /// （如 sensetime），并确保模型归入该 providerId 名称。
  Future<ProviderSyncResult> syncProvider(
    String provider, {
    String? providerId,
    bool Function()? isCancelled,
    bool autoDisableRemoved = true,
  }) async {
    if (isCancelled?.call() == true) {
      throw ModelSyncException(provider: provider, message: '已取消');
    }
    // 判断是否为自定义提供商：
    // - provider 名不在标准 ProviderType 集合中（如直接传 sensetime）→ 自定义
    // - provider 为 'custom' → 自定义
    // 内置提供商（openai/anthropic/...）即使 providerId 非空（等于 provider 名）也不视为自定义
    const standard = {'openai', 'anthropic', 'google', 'azure', 'custom'};
    final isCustomId = provider == 'custom' || !standard.contains(provider);
    final effectiveProvider = isCustomId ? 'custom' : provider;
    final effectiveId = isCustomId
        ? (providerId != null && providerId.isNotEmpty ? providerId : provider)
        : null;
    final keys = effectiveId != null && effectiveId.isNotEmpty
        ? keyManager
            .getActiveByProvider(effectiveProvider)
            .where((k) => effectiveId == 'custom'
                ? (k.providerId.isEmpty || k.providerId == 'custom')
                : k.providerId == effectiveId)
            .toList()
        : keyManager.getActiveByProvider(effectiveProvider);
    if (keys.isEmpty) {
      throw ModelSyncException(
          provider: provider, message: '未配置可用的 API Key');
    }
    final key = keys.first;
    final fetched = await providerResolver(ProviderTypeX.fromString(effectiveProvider))
        .fetchModels(key)
        .timeout(timeout,
            onTimeout: () => throw ModelSyncException(
                provider: provider, message: '连接超时'));

    // 模型归属名称：custom 提供商使用 providerId（如 sensetime），否则用 provider 名
    final modelProvider = effectiveProvider == 'custom' && effectiveId != null
        ? effectiveId
        : effectiveProvider;

    // 归一化：确保所有模型归入 modelProvider（防止 provider 实现返回了不同的 provider 名）
    // P0：同时做能力分层归一化，给模型赋 virtualId / contextWindow。
    // 关联来源 key：记录「是哪个 key 拉取了该模型」，用于删除 key 时清理其模型 / 按 key 批量启停。
    final models = fetched.map((m) {
      var normalized = m;
      if (m.provider != modelProvider) {
        normalized = m.copyWith(
          provider: modelProvider,
          id: ModelInfo.unifiedId(modelProvider, m.name),
        );
      }
      return ModelNormalizer.normalize(normalized.copyWith(sourceKeyId: key.id));
    }).toList();

    // 计算新增 / 更新
    final oldMap = {
      for (final m in repository.getByProvider(modelProvider)) m.id: m
    };
    final keepIds = <String>{};
    var newCount = 0;
    var updatedCount = 0;
    final toSave = <ModelInfo>[];
    for (final m in models) {
      keepIds.add(m.id);
      final prev = oldMap[m.id];
      if (prev == null) {
        newCount++;
        toSave.add(m);
      } else {
        if (prev.name != m.name ||
            prev.displayName != m.displayName ||
            prev.ownedBy != m.ownedBy ||
            !_listEq(prev.capabilities, m.capabilities)) {
          updatedCount++;
        }
        // 保留用户此前对该模型的启用/停用偏好
        toSave.add(m.copyWith(isEnabled: prev.isEnabled));
      }
    }

    await repository.upsertAll(toSave);
    // 标记该模型归属下、本次未出现过的模型为已下线（可按设置关闭）
    final removedCount = autoDisableRemoved
        ? await repository.markRemoved(keepIds, modelProvider)
        : 0;

    return ProviderSyncResult(
      provider: modelProvider,
      success: true,
      models: models,
      newModels: newCount,
      updatedModels: updatedCount,
      removedModels: removedCount,
    );
  }

  static bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 写入同步历史（保留最近 20 条）
  ///
  /// 注意：Hive 整数键上限为 0xFFFFFFFF，毫秒时间戳会超界，
  /// 因此使用自增键（add），时间戳仅作为记录字段参与排序。
  Future<void> _saveHistory(SyncResult result) async {
    if (historyBox == null) return;
    await historyBox!.add({
      'timestamp': result.timestamp,
      'total_models': result.totalModels,
      'providers': result.providerResults.entries
          .map((e) => {
                'provider': e.key,
                'success': e.value.success,
                'count': e.value.models.length,
                'new': e.value.newModels,
                'updated': e.value.updatedModels,
                'removed': e.value.removedModels,
                'error': e.value.error,
              })
          .toList(),
    });
    final keys = historyBox!.keys.whereType<int>().toList()..sort();
    while (keys.length > 20) {
      await historyBox!.delete(keys.removeAt(0));
    }
  }

  /// 读取同步历史（最新在前）
  List<Map<String, dynamic>> getHistory({int limit = 10}) {
    if (historyBox == null) return const [];
    final entries = historyBox!.values
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    entries.sort((a, b) =>
        (b['timestamp'] as int).compareTo(a['timestamp'] as int));
    return entries.take(limit).toList();
  }
}
