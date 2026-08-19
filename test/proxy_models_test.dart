// REQ-003：代理层 /v1/models 本地聚合接口（不透传上游）
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:relaygo/database/model_repository.dart';
import 'package:relaygo/models/model_info.dart';
import 'package:relaygo/models/user_settings.dart';
import 'package:relaygo/services/key_manager.dart';
import 'package:relaygo/services/load_balancer.dart';
import 'package:relaygo/services/log_service.dart';
import 'package:relaygo/services/proxy_server.dart';
import 'package:relaygo/services/quota_monitor.dart';
import 'package:relaygo/services/rule_engine.dart';
import 'package:relaygo/utils/encryption.dart';

void main() {
  late ModelRepository repo;
  late ProxyServer proxy;
  late UserSettings settings;

  setUpAll(() async {
    final tmp = Directory.systemTemp.createTempSync('proxy_models_test');
    Hive.init(tmp.path);
    await Hive.openBox('keys_pm_test');
    await Hive.openBox('logs_pm_test');
    await Hive.openBox('models_pm_test');
    EncryptionUtil.init(EncryptionUtil.generateMasterKeyBase64());
    repo = ModelRepository(Hive.box('models_pm_test'));
    settings = UserSettings(
      rulesEnabled: false,
      rateLimitEnabled: true, // 验证 /v1/models 不被入口限流拦截
      globalRpmLimit: 1,
      upstreamTimeoutSeconds: 5,
      virtualModelsEnabled: true, // 本文件各用例验证虚拟层收敛行为，显式开启
    );

    await repo.upsertAll([
      ModelInfo.unified(
        provider: 'openai',
        name: 'gpt-4o',
        ownedBy: 'openai',
        capabilities: const ['chat', 'vision'],
        createdAt: 1700000000000,
        lastSynced: 1700000001000,
      ),
      ModelInfo.unified(
        provider: 'openai',
        name: 'text-embedding-3-small',
        capabilities: const ['embedding'],
        lastSynced: 1700000001000,
      ),
      ModelInfo.unified(
        provider: 'openai',
        name: 'gpt-4-old',
        capabilities: const ['chat'],
        status: 'deprecated',
        isEnabled: false,
        lastSynced: 1700000001000,
      ),
      ModelInfo.unified(
        provider: 'anthropic',
        name: 'claude-3-5-sonnet-20241022',
        capabilities: const ['chat'],
        lastSynced: 1700000001000,
      ),
      ModelInfo.unified(
        provider: 'google',
        name: 'gemini-1.5-pro',
        capabilities: const ['chat'],
        isEnabled: false, // 用户手动停用
        lastSynced: 1700000001000,
      ),
      // 别名表未覆盖的未知模型：应通过能力兜底归到 chat-basic
      ModelInfo.unified(
        provider: 'custom',
        name: 'my-custom-chat-model',
        capabilities: const ['chat', 'function_calling'],
        lastSynced: 1700000001000,
      ),
    ]);

    proxy = ProxyServer(
      keyManager: KeyManager(Hive.box('keys_pm_test')),
      loadBalancer: LoadBalancer(),
      logService: LogService(Hive.box('logs_pm_test')),
      ruleEngine: RuleEngine(),
      quotaMonitor: QuotaMonitor(settings: settings),
      settings: settings,
      modelRepository: repo,
      port: 0,
    );
    await proxy.start();
  });

  tearDownAll(() async => proxy.stop());

  Future<Map<String, dynamic>> getModels([String query = '']) async {
    final client = HttpClient();
    final req = await client
        .getUrl(Uri.parse('http://127.0.0.1:${proxy.port}/v1/models$query'));
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    client.close();
    expect(resp.statusCode, 200);
    return jsonDecode(body) as Map<String, dynamic>;
  }

  test('默认收敛：返回少量能力虚拟模型（第三方客户端选择简单化）', () async {
    final json = await getModels();
    expect(json['object'], 'list');
    final data = List<Map<String, dynamic>>.from(
        (json['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
    final ids = data.map((m) => m['id'] as String).toList()..sort();
    // 默认仅启用模型，且收敛为能力虚拟模型（gpt-4o / claude-3-5-sonnet / embedding / 未知模型兜底）
    expect(ids, [
      'chat-advanced', // claude-3-5-sonnet
      'chat-basic', // my-custom-chat-model（能力兜底）
      'chat-premium', // gpt-4o
      'embedding', // text-embedding-3-small
    ]);
    final premium = data.firstWhere((m) => m['id'] == 'chat-premium');
    expect(premium['object'], 'model');
    expect(premium['virtual'], isTrue);
    expect(premium['owned_by'], 'relaygo');
    expect(premium['display_name'], isNotEmpty);
    expect(premium['capabilities'], isNotEmpty);
    expect(premium['providers'], contains('openai'));
    expect(premium['model_count'], 1);
  });

  test('expand=1 返回真实模型明细，每条附带 virtual_id', () async {
    final json = await getModels('?expand=1');
    final data = List<Map<String, dynamic>>.from(
        (json['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
    final ids = data.map((m) => m['id'] as String).toList()..sort();
    // 已停用（gpt-4-old）与手动停用（gemini-1.5-pro）被默认排除
    expect(ids, [
      'claude-3-5-sonnet-20241022',
      'gpt-4o',
      'my-custom-chat-model',
      'text-embedding-3-small',
    ]);
    final gpt4o = data.firstWhere((m) => m['id'] == 'gpt-4o');
    expect(gpt4o['object'], 'model');
    expect(gpt4o['provider'], 'openai');
    expect(gpt4o['owned_by'], 'openai');
    expect(gpt4o['created'], 1700000000);
    expect(gpt4o['capabilities'], ['chat', 'vision']);
    expect(gpt4o['status'], 'active');
    expect(gpt4o['virtual_id'], 'chat-premium');
    // 未知模型经能力兜底后也带 virtual_id
    final custom = data.firstWhere((m) => m['id'] == 'my-custom-chat-model');
    expect(custom['virtual_id'], 'chat-basic');
  });

  test('聚合多个服务商的模型（本地聚合，不透传上游）', () async {
    final json = await getModels();
    final ids = (json['data'] as List)
        .map((e) => (e as Map)['id'] as String)
        .toSet();
    // 至少出现一个合并了 openai+anthropic 的虚拟档位
    final providers = (json['data'] as List)
        .map((e) => ((e as Map)['providers'] as List))
        .expand((x) => x)
        .cast<String>()
        .toSet();
    expect(providers, containsAll(['openai', 'anthropic']));
    expect(ids, isNotEmpty);
  });

  test('按 provider 过滤', () async {
    final json = await getModels('?provider=anthropic');
    final data = json['data'] as List;
    expect(data.length, 1);
    expect((data.first as Map)['id'], 'chat-advanced');
  });

  test('按 capability 过滤', () async {
    final json = await getModels('?capability=embedding');
    final data = json['data'] as List;
    expect(data.length, 1);
    expect((data.first as Map)['id'], 'embedding');
  });

  test('enabled=false 且 expand 时包含被停用的模型', () async {
    final json = await getModels('?enabled=false&expand=1');
    final ids =
        (json['data'] as List).map((e) => (e as Map)['id'] as String).toSet();
    expect(ids, contains('gemini-1.5-pro'));
    expect(ids, contains('gpt-4-old'));
    expect(ids.length, 6);
  });

  test('status=deprecated 可单独查询已下线模型', () async {
    final json = await getModels('?status=deprecated&enabled=false&expand=1');
    final data = json['data'] as List;
    expect(data.length, 1);
    expect((data.first as Map)['id'], 'gpt-4-old');
    expect((data.first as Map)['status'], 'deprecated');
  });

  test('status=all 等价于不按状态过滤', () async {
    final json = await getModels('?status=all&enabled=false&expand=1');
    expect((json['data'] as List).length, 6);
  });

  test('模型查询不消耗入口限流额度（连续多次均 200）', () async {
    // globalRpmLimit = 1，但 /v1/models 在限流前被拦截处理
    for (var i = 0; i < 4; i++) {
      final json = await getModels();
      expect((json['data'] as List).isNotEmpty, isTrue);
    }
  });

  test('虚拟模型层关闭时 /v1/models 默认返回真实模型明细（纯转发）', () async {
    // 复用同一模型库，但用一个「虚拟层关闭」的独立实例验证默认行为
    final off = ProxyServer(
      keyManager: KeyManager(Hive.box('keys_pm_test')),
      loadBalancer: LoadBalancer(),
      logService: LogService(Hive.box('logs_pm_test')),
      ruleEngine: RuleEngine(),
      quotaMonitor: QuotaMonitor(
          settings: settings.copyWith(virtualModelsEnabled: false)),
      settings: settings.copyWith(virtualModelsEnabled: false),
      modelRepository: repo,
      port: 0,
    );
    await off.start();
    final client = HttpClient();
    final req = await client
        .getUrl(Uri.parse('http://127.0.0.1:${off.port}/v1/models'));
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    client.close();
    expect(resp.statusCode, 200);
    final json = jsonDecode(body) as Map<String, dynamic>;
    final ids = (json['data'] as List)
        .map((e) => (e as Map)['id'] as String)
        .toSet();
    // 返回真实模型名（含已启用模型），而非收敛后的虚拟档位
    expect(ids, contains('gpt-4o'));
    expect(ids, contains('text-embedding-3-small'));
    expect(ids, isNot(contains('chat-premium')));
    expect(ids, isNot(contains('chat-basic')));
    await off.stop();
  });
}
