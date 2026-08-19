import 'package:hive_flutter/hive_flutter.dart';
import 'package:relaygo/models/model_info.dart';
import 'package:relaygo/services/model_normalizer.dart';

/// 模型库仓储：基于 Hive Box（直接存 Map，免 codegen，跨平台一致）
///
/// 负责统一模型的增删改查、按服务商/能力/状态过滤、启用开关、
/// 以及「同步后标记已下线模型」。
class ModelRepository {
  final Box _box;

  ModelRepository(this._box);

  List<ModelInfo> getAll() {
    final list = _box.values
        .whereType<Map>()
        .map((m) => ModelInfo.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    list.sort((a, b) {
      final c = a.provider.compareTo(b.provider);
      return c != 0 ? c : a.name.compareTo(b.name);
    });
    return list;
  }

  ModelInfo? getById(String id) {
    final v = _box.get(id);
    if (v == null) return null;
    return ModelInfo.fromJson(Map<String, dynamic>.from(v as Map));
  }

  List<ModelInfo> getByProvider(String provider) =>
      getAll().where((m) => m.provider == provider).toList();

  /// 启用中且状态正常的模型（供代理层对外暴露）
  List<ModelInfo> getEnabled() =>
      getAll().where((m) => m.isEnabled && m.status == 'active').toList();

  // ————————————————— P0 能力分层：虚拟模型聚集与惰性回填 —————————————————

  /// 惰性回填：对「已启用、但 virtualId 为 null」的模型做一次归一化归类并落库。
  ///
  /// 幂等：已归类的直接跳过；未知模型保持 null。用于老数据在首次读取时补全，
  /// 避免一次性全表迁移的风险。返回本次实际写回的条数。
  Future<int> backfillVirtualIds() async {
    final updates = <String, dynamic>{};
    for (final m in getAll()) {
      if (!m.isEnabled || m.virtualId != null) continue;
      final normalized = ModelNormalizer.normalize(m);
      if (normalized.virtualId == null) continue;
      updates[m.id] =
          normalized.copyWith(virtualId: normalized.virtualId).toJson();
    }
    if (updates.isNotEmpty) await _box.putAll(updates);
    return updates.length;
  }

  /// 按 virtualId 分组聚合「已启用且已归类」的真实模型。
  /// 返回 { virtualId: [ModelInfo...] }，供 /v1/models 收敛成少量能力模型。
  Map<String, List<ModelInfo>> groupByVirtual() {
    final map = <String, List<ModelInfo>>{};
    for (final m in getEnabled()) {
      if (m.virtualId == null) continue;
      map.putIfAbsent(m.virtualId!, () => []).add(m);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.provider.compareTo(b.provider));
    }
    return map;
  }

  /// 多维过滤
  List<ModelInfo> getFiltered({
    String? provider,
    String? capability,
    String? status,
    bool enabledOnly = false,
  }) {
    var list = getAll();
    if (provider != null && provider.isNotEmpty) {
      list = list.where((m) => m.provider == provider).toList();
    }
    if (capability != null && capability.isNotEmpty) {
      list = list.where((m) => m.capabilities.contains(capability)).toList();
    }
    if (status != null && status.isNotEmpty) {
      list = list.where((m) => m.status == status).toList();
    }
    if (enabledOnly) {
      list = list.where((m) => m.isEnabled).toList();
    }
    return list;
  }

  /// 批量写入（按统一 id 覆盖，自动合并新旧字段）
  Future<void> upsertAll(List<ModelInfo> models) async {
    final map = <String, dynamic>{};
    for (final m in models) {
      map[m.id] = m.toJson();
    }
    if (map.isNotEmpty) await _box.putAll(map);
  }

  /// 切换单个模型的启用状态
  Future<void> setEnabled(String id, bool enabled) async {
    final m = getById(id);
    if (m != null) {
      await _box.put(id, m.copyWith(isEnabled: enabled).toJson());
    }
  }

  /// 删除指定来源 key 拉取的全部模型（用于删除 key 时清理，随后重同步）
  ///
  /// 返回被删除的数量。仅删除 sourceKeyId 精确匹配的模型，
  /// 不影响其他 key 同步的模型。
  Future<int> removeBySourceKey(String sourceKeyId) async {
    if (sourceKeyId.isEmpty) return 0;
    final ids = <String>[];
    for (final m in getAll()) {
      if (m.sourceKeyId == sourceKeyId) ids.add(m.id);
    }
    if (ids.isNotEmpty) await _box.deleteAll(ids);
    return ids.length;
  }

  /// 同步后：将 [provider] 下不在 [keepIds] 中的模型标记为已下线
  ///
  /// 返回被标记下线的数量（status=deprecated 且 isEnabled=false，保留 rawData 以便追溯）。
  /// 同步后：将 [provider] 下不在 [keepIds] 中的模型标记为已下线
  ///
  /// 返回被标记下线的数量（status=deprecated 且 isEnabled=false，保留 rawData 以便追溯）。
  ///
  /// 特例：若某模型此前已被用户手动启用（status 已是 deprecated 但 isEnabled=true），
  /// 则尊重用户选择，仅保留状态标记、不强制停用，避免「刚打开开关、同步后又被关上」。
  Future<int> markRemoved(Set<String> keepIds, String provider) async {
    final updates = <String, dynamic>{};
    for (final m in getAll()) {
      if (m.provider == provider && !keepIds.contains(m.id)) {
        if (m.isEnabled && m.status == 'deprecated') {
          // 用户此前已手动启用一个已下线的模型，尊重其选择
          updates[m.id] = m.copyWith(status: 'deprecated').toJson();
        } else {
          updates[m.id] =
              m.copyWith(status: 'deprecated', isEnabled: false).toJson();
        }
      }
    }
    if (updates.isNotEmpty) await _box.putAll(updates);
    return updates.length;
  }

  /// 某服务商最后同步时间戳（毫秒），无数据返回 0
  int lastSyncAt(String provider) {
    var max = 0;
    for (final m in getByProvider(provider)) {
      if (m.lastSynced > max) max = m.lastSynced;
    }
    return max;
  }

  /// 各服务商模型数量
  Map<String, int> providerCounts() {
    final map = <String, int>{};
    for (final m in getAll()) {
      map[m.provider] = (map[m.provider] ?? 0) + 1;
    }
    return map;
  }

  /// 清空全部模型（测试/重置用）
  Future<void> clear() async => _box.clear();

  /// 删除指定服务商下所有已下线（deprecated）模型
  ///
  /// 与 [markRemoved] 不同：markRemoved 只标记不删除（保留 rawData 以便追溯），
  /// 本方法真正从库中移除，避免「已下线模型越积越多」。
  /// 返回被删除的数量。
  Future<int> removeDeprecated({String? provider}) async {
    final ids = <String>[];
    for (final m in getAll()) {
      if (m.status == 'deprecated' &&
          (provider == null || m.provider == provider)) {
        ids.add(m.id);
      }
    }
    if (ids.isNotEmpty) await _box.deleteAll(ids);
    return ids.length;
  }

  /// 已下线（deprecated）模型数量，按服务商分组
  Map<String, int> deprecatedCounts() {
    final map = <String, int>{};
    for (final m in getAll()) {
      if (m.status == 'deprecated') {
        map[m.provider] = (map[m.provider] ?? 0) + 1;
      }
    }
    return map;
  }
}
