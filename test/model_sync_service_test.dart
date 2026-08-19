// REQ-003：模型同步服务（并发拉取、新增/更新/下线统计、进度、取消、错误、历史）
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:relaygo/database/model_repository.dart';
import 'package:relaygo/models/api_key.dart';
import 'package:relaygo/models/key_test.dart';
import 'package:relaygo/models/model_info.dart';
import 'package:relaygo/models/model_sync_exception.dart';
import 'package:relaygo/models/provider_config.dart';
import 'package:relaygo/services/key_manager.dart';
import 'package:relaygo/services/model_sync_service.dart';
import 'package:relaygo/services/providers/base_provider.dart';
import 'package:relaygo/utils/encryption.dart';

/// 可编程的假 provider：按 key.provider 返回目录内的模型，不触网
class _FakeProvider extends BaseProvider {
  /// provider -> 模型名列表
  final Map<String, List<String>> catalog = {};

  /// 需要抛 401 的 provider
  final Set<String> failProviders = {};

  /// 模拟慢响应
  Duration? delay;

  /// 二次同步时用于制造「字段变更」
  String? ownedBy;

  int calls = 0;

  @override
  ProviderType get type => ProviderType.openai;

  @override
  Future<ProviderResult> forward(_, __, {Duration? timeout}) async =>
      throw UnimplementedError();

  @override
  Future<KeyTestOutcome> test(ApiKey key) async => KeyTestOutcome.valid();

  @override
  Future<List<ModelInfo>> fetchModels(ApiKey key) async {
    calls++;
    // 自定义提供商按 providerId 区分目录（模拟真实 CustomProvider 行为）
    final providerKey = key.provider == 'custom' && key.providerId.isNotEmpty
        ? key.providerId
        : key.provider;
    if (failProviders.contains(providerKey)) {
      throw ModelSyncException(
          provider: providerKey, message: 'HTTP 401', statusCode: 401);
    }
    if (delay != null) await Future<void>.delayed(delay!);
    final now = DateTime.now().millisecondsSinceEpoch;
    return (catalog[providerKey] ?? const <String>[])
        .map((n) => ModelInfo.unified(
              provider: providerKey,
              name: n,
              ownedBy: ownedBy,
              capabilities: ModelInfo.inferCapabilities(n),
              lastSynced: now,
            ))
        .toList();
  }
}

void main() {
  late KeyManager keyManager;
  late ModelRepository repo;
  late Box history;
  late _FakeProvider fake;

  setUpAll(() async {
    final tmp = Directory.systemTemp.createTempSync('model_sync_test');
    Hive.init(tmp.path);
    await Hive.openBox('keys_sync_test');
    await Hive.openBox('models_sync_test');
    await Hive.openBox('history_sync_test');
    EncryptionUtil.init(EncryptionUtil.generateMasterKeyBase64());
    keyManager = KeyManager(Hive.box('keys_sync_test'));
    repo = ModelRepository(Hive.box('models_sync_test'));
    history = Hive.box('history_sync_test');
  });

  setUp(() async {
    for (final k in keyManager.getAll()) {
      await keyManager.deleteKey(k.id);
    }
    await repo.clear();
    await history.clear();
    fake = _FakeProvider();
  });

  ModelSyncService svc({Duration? timeout}) => ModelSyncService(
        keyManager,
        repo,
        providerResolver: (_) => fake,
        timeout: timeout ?? const Duration(seconds: 5),
        historyBox: history,
      );

  Future<void> addKey(String provider, {bool active = true}) async {
    final k = await keyManager.createKey(
      provider: provider,
      plainKey: 'sk-$provider',
      name: '$provider-key',
    );
    if (!active) {
      await keyManager.updateKey(k.copyWith(status: KeyStatus.inactive));
    }
  }

  group('activeProviderIds', () {
    test('仅包含拥有 active key 的服务商（去重）', () async {
      await addKey('openai');
      await addKey('openai'); // 同 provider 多 key 只算一次
      await addKey('anthropic');
      await addKey('google', active: false);
      final ids = svc().activeProviderIds.map((t) => t.id).toList()..sort();
      expect(ids, ['anthropic', 'openai']);
    });
  });

  group('syncProvider 单服务商', () {
    test('首次同步：全部计为新增并写入仓储', () async {
      await addKey('openai');
      fake.catalog['openai'] = ['gpt-4o', 'gpt-4o-mini'];
      final r = await svc().syncProvider('openai');
      expect(r.success, isTrue);
      expect(r.models.length, 2);
      expect(r.newModels, 2);
      expect(r.updatedModels, 0);
      expect(r.removedModels, 0);
      expect(repo.getAll().length, 2);
      expect(repo.getById('openai:gpt-4o')!.capabilities, contains('chat'));
    });

    test('同步的模型被关联来源 key 的 sourceKeyId', () async {
      final rawKey = await keyManager.createKey(
        provider: 'openai',
        plainKey: 'sk-openai',
        name: 'openai-key',
      );
      fake.catalog['openai'] = ['gpt-4o', 'gpt-4o-mini'];
      await svc().syncProvider('openai');
      expect(repo.getById('openai:gpt-4o')!.sourceKeyId, rawKey.id);
      expect(repo.getById('openai:gpt-4o-mini')!.sourceKeyId, rawKey.id);
    });

    test('二次同步：字段变更计为更新，消失的模型计为下线', () async {
      await addKey('openai');
      fake.catalog['openai'] = ['gpt-4o', 'gpt-4-old'];
      await svc().syncProvider('openai');

      fake.catalog['openai'] = ['gpt-4o']; // gpt-4-old 已被上游移除
      fake.ownedBy = 'openai-org'; // 制造字段变更
      final r2 = await svc().syncProvider('openai');
      expect(r2.newModels, 0);
      expect(r2.updatedModels, 1);
      expect(r2.removedModels, 1);
      final removed = repo.getById('openai:gpt-4-old')!;
      expect(removed.status, 'deprecated');
      expect(removed.isEnabled, isFalse);
      expect(repo.getById('openai:gpt-4o')!.ownedBy, 'openai-org');
    });

    test('保留用户的启用/停用偏好，不被同步覆盖', () async {
      await addKey('openai');
      fake.catalog['openai'] = ['gpt-4o'];
      await svc().syncProvider('openai');
      await repo.setEnabled('openai:gpt-4o', false);

      await svc().syncProvider('openai');
      expect(repo.getById('openai:gpt-4o')!.isEnabled, isFalse);
    });

    test('autoDisableRemoved=false 时不标记下线', () async {
      await addKey('openai');
      fake.catalog['openai'] = ['gpt-4o', 'gpt-4-old'];
      await svc().syncProvider('openai');

      fake.catalog['openai'] = ['gpt-4o'];
      final r = await svc()
          .syncProvider('openai', autoDisableRemoved: false);
      expect(r.removedModels, 0);
      expect(repo.getById('openai:gpt-4-old')!.status, 'active');
    });

    test('无可用 key 时抛出 ModelSyncException', () async {
      await addKey('google', active: false);
      await expectLater(
        svc().syncProvider('google'),
        throwsA(isA<ModelSyncException>().having(
            (e) => e.message, 'message', contains('未配置可用的 API Key'))),
      );
      expect(fake.calls, 0);
    });

    test('自定义提供商按 providerId 同步并归入正确名称', () async {
      await keyManager.createKey(
        provider: 'custom',
        providerId: 'sensetime',
        plainKey: 'sk-sensetime',
        name: '商汤',
        baseUrl: 'https://api.sensetime.com',
      );
      fake.catalog['sensetime'] = ['SenseChat-5'];
      final r = await svc().syncProvider('custom', providerId: 'sensetime');
      expect(r.success, isTrue);
      expect(r.provider, 'sensetime');
      expect(r.models.length, 1);
      // 模型应归入 providerId（sensetime）而非 'custom'
      expect(repo.getById('sensetime:SenseChat-5'), isNotNull);
      expect(repo.getByProvider('sensetime').length, 1);
      expect(repo.getByProvider('custom'), isEmpty);
    });

    test('内置提供商即使 providerId 非空也不视为自定义', () async {
      await keyManager.createKey(
        provider: 'openai',
        providerId: 'openai',
        plainKey: 'sk-openai',
        name: 'openai',
      );
      fake.catalog['openai'] = ['gpt-4o'];
      final r = await svc().syncProvider('openai', providerId: 'openai');
      expect(r.success, isTrue);
      expect(r.provider, 'openai');
      expect(repo.getById('openai:gpt-4o'), isNotNull);
    });

    test('超时按 timeout 中断并抛出连接超时', () async {
      await addKey('openai');
      fake.catalog['openai'] = ['gpt-4o'];
      fake.delay = const Duration(milliseconds: 400);
      await expectLater(
        svc(timeout: const Duration(milliseconds: 30)).syncProvider('openai'),
        throwsA(isA<ModelSyncException>()
            .having((e) => e.message, 'message', '连接超时')),
      );
    });
  });

  group('syncAll 多服务商', () {
    test('并发同步并汇总各服务商结果', () async {
      await addKey('openai');
      await addKey('anthropic');
      fake.catalog['openai'] = ['gpt-4o', 'gpt-4o-mini'];
      fake.catalog['anthropic'] = ['claude-3-5-sonnet'];

      final result = await svc().syncAll();
      expect(result.providerResults.length, 2);
      expect(result.successCount, 2);
      expect(result.failedCount, 0);
      expect(result.totalModels, 3);
      expect(result.newCount, 3);
      expect(repo.providerCounts(), {'anthropic': 1, 'openai': 2});
    });

    test('单个服务商失败不影响其他服务商，并给出友好错误', () async {
      await addKey('openai');
      await addKey('anthropic');
      fake.catalog['openai'] = ['gpt-4o'];
      fake.failProviders.add('anthropic');

      final result = await svc().syncAll();
      expect(result.successCount, 1);
      expect(result.failedCount, 1);
      expect(result.providerResults['anthropic']!.success, isFalse);
      expect(result.providerResults['anthropic']!.error, 'API Key 无效或已过期');
      expect(repo.getByProvider('openai').length, 1);
    });

    test('多个自定义提供商各自独立同步并归入各自名称', () async {
      await keyManager.createKey(
        provider: 'custom',
        providerId: 'sensetime',
        plainKey: 'sk-sensetime',
        name: '商汤',
      );
      await keyManager.createKey(
        provider: 'custom',
        providerId: 'deepseek',
        plainKey: 'sk-deepseek',
        name: 'DeepSeek',
      );
      fake.catalog['sensetime'] = ['SenseChat-5'];
      fake.catalog['deepseek'] = ['deepseek-chat'];
      final result = await svc().syncAll();
      expect(result.successCount, 2);
      // 两个自定义提供商分别同步，模型归入各自 providerId
      expect(repo.getById('sensetime:SenseChat-5'), isNotNull);
      expect(repo.getById('deepseek:deepseek-chat'), isNotNull);
      expect(repo.getByProvider('custom'), isEmpty);
      expect(repo.providerCounts(), {'sensetime': 1, 'deepseek': 1});
    });

    test('进度回调覆盖每个服务商的 syncing → completed', () async {
      await addKey('openai');
      await addKey('anthropic');
      fake.catalog['openai'] = ['gpt-4o'];
      fake.catalog['anthropic'] = ['claude-3-haiku'];

      final events = <SyncProgress>[];
      await svc().syncAll(onProgress: events.add);
      expect(events.where((e) => e.status == SyncStatus.syncing).length, 2);
      expect(events.where((e) => e.status == SyncStatus.completed).length, 2);
      expect(events.last.message, contains('同步完成'));
    });

    test('取消时不发起任何请求，结果标记为已取消', () async {
      await addKey('openai');
      fake.catalog['openai'] = ['gpt-4o'];
      final result = await svc().syncAll(isCancelled: () => true);
      expect(fake.calls, 0);
      expect(result.successCount, 0);
      expect(result.providerResults['openai']!.error, '已取消');
      expect(repo.getAll(), isEmpty);
    });

    test('无任何 active key 时返回空结果而不报错', () async {
      final result = await svc().syncAll();
      expect(result.providerResults, isEmpty);
      expect(result.totalModels, 0);
      expect(result.successCount, 0);
    });
  });

  group('性能验收', () {
    test('5 个服务商并发同步（总耗时远小于串行累加）', () async {
      const providers = ['openai', 'anthropic', 'google', 'azure', 'custom'];
      for (final p in providers) {
        await addKey(p);
        fake.catalog[p] = ['$p-model-1', '$p-model-2'];
      }
      fake.delay = const Duration(milliseconds: 300); // 串行需 ≥1500ms

      final sw = Stopwatch()..start();
      final result = await svc().syncAll();
      sw.stop();

      expect(result.successCount, 5);
      expect(result.totalModels, 10);
      expect(sw.elapsedMilliseconds, lessThan(1200),
          reason: '应并发执行，实际 ${sw.elapsedMilliseconds}ms');
      expect(sw.elapsedMilliseconds, lessThan(30000)); // 验收：< 30 秒
    });
  });

  group('同步历史', () {
    test('每次同步写入历史，最新在前且含明细', () async {
      await addKey('openai');
      fake.catalog['openai'] = ['gpt-4o'];
      await svc().syncAll();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      fake.catalog['openai'] = ['gpt-4o', 'gpt-4o-mini'];
      await svc().syncAll();

      final list = svc().getHistory();
      expect(list.length, 2);
      expect(list.first['timestamp'] as int,
          greaterThanOrEqualTo(list.last['timestamp'] as int));
      expect(list.first['total_models'], 2);
      final providers = List<Map>.from(list.first['providers'] as List);
      expect(providers.first['provider'], 'openai');
      expect(providers.first['success'], isTrue);
      expect(providers.first['new'], 1); // 第二次仅新增 gpt-4o-mini
    });

    test('历史最多保留 20 条', () async {
      await addKey('openai');
      fake.catalog['openai'] = ['gpt-4o'];
      final s = svc();
      for (var i = 0; i < 23; i++) {
        await s.syncAll();
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      expect(history.length, lessThanOrEqualTo(20));
      expect(s.getHistory(limit: 100).length, lessThanOrEqualTo(20));
    });
  });
}
