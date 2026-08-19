import 'dart:async';
import 'dart:math';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:relaygo/models/api_key.dart';
import 'package:relaygo/models/key_test.dart';
import 'package:relaygo/models/provider_config.dart';
import 'package:relaygo/services/providers/base_provider.dart';
import 'package:relaygo/services/providers/provider_factory.dart';
import 'package:relaygo/utils/encryption.dart';

/// API Key 管理器
///
/// 负责 key 的增删改查、加密存储、有效性测试、批量导入导出。
/// key 明文仅在创建时加密、转发时临时解密，存储层不保留明文。
///
/// 需求 REQ-001 增强：
///  - 备注字段 [ApiKey.note]
///  - 细粒度测试结果（valid/invalid/timeout/error）与 [ApiKey.lastTested] 等
///  - [batchTestKeys] 并发批量测试（最多 5 个、单 key 超时 10s、瞬时失败重试 1 次）
class KeyManager {
  final Box _box;

  /// provider 解析器（默认走全局工厂，便于单测注入假 provider）
  final BaseProvider Function(ProviderType) providerResolver;

  KeyManager(
    this._box, {
    this.providerResolver = providerFor,
  });

  List<ApiKey> getAll() {
    final list = _box.values
        .whereType<Map>()
        .map((m) => ApiKey.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  ApiKey? getById(String id) {
    final v = _box.get(id);
    if (v == null) return null;
    return ApiKey.fromJson(Map<String, dynamic>.from(v as Map));
  }

  Future<void> addKey(ApiKey key) async => _box.put(key.id, key.toJson());

  Future<void> updateKey(ApiKey key) async => _box.put(key.id, key.toJson());

  Future<void> deleteKey(String id) async => _box.delete(id);

  List<ApiKey> getByProvider(String provider) =>
      getAll().where((k) => k.provider == provider).toList();

  List<ApiKey> getActiveByProvider(String provider) => getByProvider(provider)
      .where((k) => k.status == KeyStatus.active)
      .toList();

  /// 获取某提供商下当前「可用」的 key（用于构建候选池）。
  ///
  /// 与 [getActiveByProvider] 的区别：处于 `error` / `exhausted` 状态但冷却
  /// 已过期的 key 会自动恢复为 active 并持久化，从而打破
  /// 「标错/冷却后永远无法回到候选池 → 永远无法成功 → 永远无法恢复」的死锁。
  /// 其中 `exhausted`（额度耗尽）在冷却到期后同样自动恢复，使被静默跳过的
  /// key 在下一量周期内重新参与轮询。
  ///
  /// 注意：返回的 key 对象为内存副本，恢复状态已通过 [updateKey] 落库。
  List<ApiKey> getUsableByProvider(String provider) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final usable = <ApiKey>[];
    for (final k in getByProvider(provider)) {
      if (k.status == KeyStatus.active) {
        usable.add(k);
        continue;
      }
      if ((k.status == KeyStatus.error || k.status == KeyStatus.exhausted) &&
          k.cooldownUntil != null &&
          k.cooldownUntil! <= now) {
        // 冷却已结束：自动恢复为 active，并持久化
        k.status = KeyStatus.active;
        k.cooldownUntil = null;
        k.failureCount = 0;
        unawaited(updateKey(k));
        usable.add(k);
      }
    }
    return usable;
  }

  /// 用明文创建并加密存储
  Future<ApiKey> createKey({
    required String provider,
    required String plainKey,
    required String name,
    String? providerId,
    String? baseUrl,
    String note = '',
    int priority = 100,
    int weight = 1,
    int maxRpm = 60,
    int dailyQuota = 1000000,
    Map<String, dynamic> metadata = const {},
  }) async {
    final encrypted = EncryptionUtil.encrypt(plainKey);
    final key = ApiKey(
      id: _genId(),
      provider: provider,
      providerId: providerId ?? '',
      encryptedKey: encrypted,
      name: name,
      note: note,
      baseUrl: baseUrl,
      priority: priority,
      weight: weight,
      maxRequestsPerMinute: maxRpm,
      dailyQuota: dailyQuota,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      metadata: metadata,
    );
    await addKey(key);
    return key;
  }

  /// 解密明文 key（仅内部转发使用，切勿写入日志）
  String decryptKey(ApiKey key) => EncryptionUtil.decrypt(key.encryptedKey);

  /// 单个 key 有效性测试（带单 key 超时），并持久化结果
  Future<KeyTestOutcome> testKey(
    ApiKey key, {
    Duration timeout = const Duration(seconds: 10),
  }) =>
      _runTest(key, timeout);

  /// 仅执行一次测试 + 落库，不重试
  Future<KeyTestOutcome> _runTest(ApiKey key, Duration timeout) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    KeyTestOutcome outcome;
    try {
      outcome = await providerResolver(key.providerType)
          .test(key)
          .timeout(timeout, onTimeout: () => KeyTestOutcome.timeout());
    } on TimeoutException {
      outcome = KeyTestOutcome.timeout();
    } catch (e) {
      final msg = e.toString().replaceFirst(RegExp(r'^.*Exception: '), '');
      outcome = KeyTestOutcome.failure(msg);
    }
    key.lastTested = now;
    key.testResult = outcome.status.name;
    key.testError = outcome.error;
    await updateKey(key);
    return outcome;
  }

  /// 瞬时失败（超时/网络异常）重试 1 次；401/403 等鉴权失败不重试
  Future<KeyTestOutcome> _testWithRetry(
    ApiKey key,
    Duration timeout,
    int retries,
    bool Function()? isCancelled,
  ) async {
    var outcome = await _runTest(key, timeout);
    for (var attempt = 0;
        attempt < retries &&
            !outcome.ok &&
            outcome.status != KeyTestStatus.invalid &&
            (isCancelled?.call() != true);
        attempt++) {
      outcome = await _runTest(key, timeout);
    }
    return outcome;
  }

  /// 批量测试（需求 2.2）
  ///
  /// - [concurrency] 最大并发（默认 5）
  /// - [perKeyTimeout] 单 key 超时（默认 10s）
  /// - [retries] 瞬时失败重试次数（默认 1）
  /// - [onProgress] 每测完一个 key 回调（record / 已完成数 / 总数）
  /// - [isCancelled] 返回 true 时尽快中止（已开始的并发会等其结束）
  ///
  /// 返回 [BatchTestSummary] 汇总。
  Future<BatchTestSummary> batchTestKeys(
    List<ApiKey> keys, {
    Future<void> Function(KeyTestRecord record, int done, int total)?
        onProgress,
    bool Function()? isCancelled,
    int concurrency = 5,
    Duration perKeyTimeout = const Duration(seconds: 10),
    int retries = 1,
  }) async {
    final records = <KeyTestRecord>[];
    if (keys.isEmpty) return BatchTestSummary(records);
    final cap = concurrency < 1 ? 1 : concurrency;
    var done = 0;

    for (var i = 0; i < keys.length; i += cap) {
      if (isCancelled?.call() == true) break;
      final chunk = keys.skip(i).take(cap).toList();
      final chunkResults = await Future.wait(chunk.map(
        (k) => _testWithRetry(k, perKeyTimeout, retries, isCancelled),
      ));
      for (var j = 0; j < chunk.length; j++) {
        final k = chunk[j];
        final outcome = chunkResults[j];
        records.add(KeyTestRecord(
          id: k.id,
          provider: k.provider,
          name: k.name,
          note: k.note,
          maskedKey: k.maskedKey,
          outcome: outcome,
        ));
        done++;
        if (onProgress != null)
          await onProgress(records.last, done, keys.length);
      }
    }
    return BatchTestSummary(records);
  }

  /// 批量导入（明文行：provider, key, name?, note?, base_url?）
  ///
  /// 支持「无限添加」，同一 provider 可导入多个 key。
  /// 额外支持 provider_id / group / priority / weight / max_requests_per_minute /
  /// daily_quota 字段，可与 [exportKeys] 导出的 JSON 完整往返。
  Future<int> importKeys(List<Map<String, String>> rows) async {
    int count = 0;
    for (final row in rows) {
      final provider = row['provider'];
      final plain = row['key'];
      if (provider == null || plain == null || plain.isEmpty) continue;
      final group = row['group'] ?? '';
      final k = await createKey(
        provider: provider,
        providerId: row['provider_id'],
        plainKey: plain,
        name: row['name'] ?? '导入-$provider',
        baseUrl: row['base_url'],
        note: row['note'] ?? '',
        priority: int.tryParse(row['priority'] ?? '') ?? 100,
        weight: int.tryParse(row['weight'] ?? '') ?? 1,
        maxRpm: int.tryParse(row['max_requests_per_minute'] ?? '') ?? 60,
        dailyQuota: int.tryParse(row['daily_quota'] ?? '') ?? 1000000,
      );
      if (group.isNotEmpty) {
        await updateKey(k.copyWith(group: group));
      }
      count++;
    }
    return count;
  }

  /// 导出明文（用于用户主动备份 / 重装后导入）
  ///
  /// 返回的字段与 [importKeys] 兼容，可直接通过「批量导入」恢复。
  List<Map<String, String>> exportKeys() => getAll()
      .map((k) => {
            'provider': k.provider,
            'provider_id': k.providerId,
            'key': EncryptionUtil.decrypt(k.encryptedKey),
            'name': k.name,
            'note': k.note,
            'base_url': k.baseUrl ?? '',
            'group': k.group,
            'priority': '${k.priority}',
            'weight': '${k.weight}',
            'max_requests_per_minute': '${k.maxRequestsPerMinute}',
            'daily_quota': '${k.dailyQuota}',
          })
      .toList();

  String _genId() {
    final rnd = Random.secure();
    final t = DateTime.now().microsecondsSinceEpoch;
    final suffix = rnd.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return '${t.toRadixString(16)}$suffix';
  }
}
