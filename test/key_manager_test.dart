import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:relaygo/models/api_key.dart';
import 'package:relaygo/models/key_test.dart';
import 'package:relaygo/models/provider_config.dart';
import 'package:relaygo/services/providers/base_provider.dart';
import 'package:relaygo/services/key_manager.dart';
import 'package:relaygo/models/model_info.dart';
import 'package:relaygo/utils/encryption.dart';

/// 按 key.name 前缀决定测试结果的假 provider（不触网）
class _FakeProvider extends BaseProvider {
  @override
  ProviderType get type => ProviderType.openai;

  @override
  Future<ProviderResult> forward(_, __, {Duration? timeout}) async =>
      throw UnimplementedError();

  @override
  Future<KeyTestOutcome> test(ApiKey key) async {
    final n = key.name;
    if (n.startsWith('bad')) return KeyTestOutcome.invalid(401, '');
    if (n.startsWith('slow')) return KeyTestOutcome.timeout();
    if (n.startsWith('err')) return KeyTestOutcome.failure('boom');
    return KeyTestOutcome.valid();
  }

  @override
  Future<List<ModelInfo>> fetchModels(ApiKey key) async => <ModelInfo>[];
}

/// 首次调用模拟超时、重试后成功的假 provider（验证重试逻辑）
class _FlakyProvider extends BaseProvider {
  final Set<String> _seen = {};
  bool retried = false;

  @override
  ProviderType get type => ProviderType.openai;

  @override
  Future<ProviderResult> forward(_, __, {Duration? timeout}) async =>
      throw UnimplementedError();

  @override
  Future<KeyTestOutcome> test(ApiKey key) async {
    if (_seen.contains(key.id)) {
      retried = true;
      return KeyTestOutcome.valid();
    }
    _seen.add(key.id);
    return KeyTestOutcome.timeout();
  }

  @override
  Future<List<ModelInfo>> fetchModels(ApiKey key) async => <ModelInfo>[];
}

void main() {
  late KeyManager keyManager;

  setUpAll(() async {
    final tmp = Directory.systemTemp.createTempSync('km_test');
    Hive.init(tmp.path);
    await Hive.openBox('api_keys_km');
    EncryptionUtil.init(EncryptionUtil.generateMasterKeyBase64());
    keyManager = KeyManager(Hive.box('api_keys_km'),
        providerResolver: (_) => _FakeProvider());
  });

  setUp(() async {
    for (final k in keyManager.getAll()) {
      await keyManager.deleteKey(k.id);
    }
  });

  group('批量导入与备注', () {
    test('importKeys 支持备注字段', () async {
      final n = await keyManager.importKeys([
        {'provider': 'openai', 'key': 'sk-1', 'name': 'ok-A', 'note': '免费额度'},
        {'provider': 'openai', 'key': 'sk-2', 'name': 'bad-B', 'note': '付费账户'},
      ]);
      expect(n, 2);
      final a = keyManager.getAll().firstWhere((k) => k.name == 'ok-A');
      expect(a.note, '免费额度');
      final b = keyManager.getAll().firstWhere((k) => k.name == 'bad-B');
      expect(b.note, '付费账户');
    });

    test('无限添加：同 provider 可导入多个 key', () async {
      final n = await keyManager.importKeys(List.generate(
        12,
        (i) => {'provider': 'openai', 'key': 'sk-$i', 'name': 'ok-$i'},
      ));
      expect(n, 12);
      expect(keyManager.getByProvider('openai').length, 12);
    });
  });

  group('导出与导入往返', () {
    test('exportKeys 导出的数据可被 importKeys 完整恢复', () async {
      final k = await keyManager.createKey(
        provider: 'openai',
        providerId: 'openai',
        plainKey: 'sk-roundtrip',
        name: '往返测试',
        note: '备注',
        baseUrl: 'https://api.openai.com/v1',
        priority: 50,
        weight: 2,
        maxRpm: 30,
        dailyQuota: 500000,
      );
      await keyManager.updateKey(k.copyWith(group: 'g1'));

      final exported = keyManager.exportKeys();
      expect(exported.length, 1);
      expect(exported.first['key'], 'sk-roundtrip'); // 明文
      expect(exported.first['group'], 'g1');
      expect(exported.first['priority'], '50');
      expect(exported.first['daily_quota'], '500000');

      // 清空后导入恢复
      for (final kk in keyManager.getAll()) {
        await keyManager.deleteKey(kk.id);
      }
      final n = await keyManager.importKeys(exported);
      expect(n, 1);
      final restored = keyManager.getAll().first;
      expect(restored.name, '往返测试');
      expect(restored.note, '备注');
      expect(restored.group, 'g1');
      expect(restored.priority, 50);
      expect(restored.weight, 2);
      expect(restored.maxRequestsPerMinute, 30);
      expect(restored.dailyQuota, 500000);
      expect(EncryptionUtil.decrypt(restored.encryptedKey), 'sk-roundtrip');
    });
  });

  group('单 key 测试持久化', () {
    test('有效 key 更新 lastTested / testResult', () async {
      final k = await keyManager.createKey(
          provider: 'openai', plainKey: 'sk-x', name: 'ok-C');
      final outcome = await keyManager.testKey(k);
      expect(outcome.ok, isTrue);
      final reloaded = keyManager.getById(k.id)!;
      expect(reloaded.lastTested, isNotNull);
      expect(reloaded.testResult, 'valid');
      expect(reloaded.tested, isTrue);
    });

    test('无效 key 记录 401 原因', () async {
      final k = await keyManager.createKey(
          provider: 'openai', plainKey: 'sk-y', name: 'bad-D');
      final outcome = await keyManager.testKey(k);
      expect(outcome.status, KeyTestStatus.invalid);
      expect(outcome.error, contains('401'));
      expect(keyManager.getById(k.id)!.testResult, 'invalid');
    });
  });

  group('批量测试 batchTestKeys', () {
    Future<List<ApiKey>> _seed() async {
      final names = ['ok-1', 'ok-2', 'bad-1', 'bad-2', 'slow-1', 'err-1'];
      final created = <ApiKey>[];
      for (final n in names) {
        created.add(await keyManager.createKey(
            provider: 'openai', plainKey: 'sk-$n', name: n));
      }
      return created;
    }

    test('汇总统计有效/无效/超时/异常数量', () async {
      final keys = await _seed();
      final summary = await keyManager.batchTestKeys(keys);
      expect(summary.total, 6);
      expect(summary.validCount, 2);
      expect(summary.invalidCount, 2);
      expect(summary.timeoutCount, 1);
      expect(summary.errorCount, 1);
      expect(summary.failed.length, 4);
    });

    test('progress 回调按完成数递增', () async {
      final keys = await _seed();
      var lastDone = 0;
      await keyManager.batchTestKeys(keys, onProgress: (_, done, total) async {
        expect(done, greaterThanOrEqualTo(lastDone));
        lastDone = done;
        expect(total, 6);
      });
      expect(lastDone, 6);
    });

    test('取消后不再测试剩余 key', () async {
      final keys = await _seed();
      final summary =
          await keyManager.batchTestKeys(keys, isCancelled: () => true);
      expect(summary.total, 0);
      // 未测试
      expect(keyManager.getById(keys.first.id)!.testResult, isNull);
    });

    test('瞬时失败（超时）重试 1 次后通过', () async {
      final flaky = _FlakyProvider();
      final mgr = KeyManager(Hive.box('api_keys_km'),
          providerResolver: (_) => flaky);
      final k = await mgr.createKey(
          provider: 'openai', plainKey: 'sk-r', name: 'slow-Retry');
      final outcome = await mgr.batchTestKeys([k], retries: 1);
      expect(outcome.records.first.outcome.ok, isTrue);
      expect(flaky.retried, isTrue);
    });
  });

  group('getUsableByProvider (自动恢复冷却过期)', () {
    test('active key 正常纳入候选', () async {
      await keyManager.createKey(
          provider: 'openai', plainKey: 'sk-1', name: 'ok-1');
      final usable = keyManager.getUsableByProvider('openai');
      expect(usable.length, 1);
      expect(usable.first.status, KeyStatus.active);
    });

    test('error + 冷却已过期 → 自动恢复为 active 并持久化', () async {
      final k = await keyManager.createKey(
          provider: 'openai', plainKey: 'sk-fail', name: 'err-1');
      k.status = KeyStatus.error;
      k.cooldownUntil = DateTime.now().millisecondsSinceEpoch - 1000; // 已过期
      k.failureCount = 3;
      await keyManager.updateKey(k);

      final all = keyManager.getByProvider('openai');
      expect(all.first.status, KeyStatus.error);

      final usable = keyManager.getUsableByProvider('openai');
      expect(usable.length, 1);
      expect(usable.first.status, KeyStatus.active);
      expect(usable.first.cooldownUntil, isNull);
      expect(usable.first.failureCount, 0);

      // 持久化后重新读取，状态已恢复
      final reloaded = keyManager.getById(all.first.id);
      expect(reloaded?.status, KeyStatus.active);
      expect(reloaded?.cooldownUntil, isNull);
      expect(reloaded?.failureCount, 0);
    });

    test('error + 冷却未过期 → 保持 error 不纳入候选', () async {
      final k = await keyManager.createKey(
          provider: 'openai', plainKey: 'sk-fail-2', name: 'err-2');
      k.status = KeyStatus.error;
      k.cooldownUntil = DateTime.now().millisecondsSinceEpoch + 60000;
      k.failureCount = 3;
      await keyManager.updateKey(k);

      final usable = keyManager.getUsableByProvider('openai');
      expect(usable.isEmpty, isTrue);
      final all = keyManager.getByProvider('openai');
      expect(all.first.status, KeyStatus.error);
    });

    test('exhausted 不参与恢复（由 quotaMonitor.rollIfNeeded 处理）', () async {
      final k = await keyManager.createKey(
          provider: 'openai', plainKey: 'sk-ex', name: 'ex-1');
      k.status = KeyStatus.exhausted;
      await keyManager.updateKey(k);

      final usable = keyManager.getUsableByProvider('openai');
      expect(usable.isEmpty, isTrue);
    });
  });
}
