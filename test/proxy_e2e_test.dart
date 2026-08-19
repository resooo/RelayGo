// 端到端集成测试：真实启动代理服务器，转发到本地 mock 上游，验证 2.1 / 2.2
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:relaygo/models/api_key.dart';
import 'package:relaygo/models/routing_rule.dart';
import 'package:relaygo/models/user_settings.dart';
import 'package:relaygo/services/key_manager.dart';
import 'package:relaygo/services/load_balancer.dart';
import 'package:relaygo/services/log_service.dart';
import 'package:relaygo/services/quota_monitor.dart';
import 'package:relaygo/services/rule_engine.dart';
import 'package:relaygo/services/proxy_server.dart';
import 'package:relaygo/database/model_repository.dart';
import 'package:relaygo/models/model_info.dart';
import 'package:relaygo/utils/encryption.dart';

/// 简易 mock 上游：记录收到的请求，可配置返回内容/状态码/是否为 SSE
class MockUpstream {
  final HttpServer server;
  final int port;
  final List<Map<String, dynamic>> received = [];
  int failUntil = 0; // 前 N 次返回 503，用于测试重试
  bool sse = false;
  int errorStatus = 0; // 非 0 时所有请求返回该状态码 + errorBody
  String errorBody = '{"error":{"message":"mock upstream error"}}';

  MockUpstream(this.server, this.port);

  static Future<MockUpstream> bind() async {
    final s = await HttpServer.bind('127.0.0.1', 0);
    final inst = MockUpstream(s, s.port);
    s.listen((req) async {
      final body = await req.fold<List<int>>([], (p, e) => [...p, ...e]);
      final decoded =
          body.isNotEmpty ? jsonDecode(utf8.decode(body)) : <String, dynamic>{};
      inst.received.add({
        'path': req.uri.path,
        'model': decoded['model'],
        'body': decoded,
      });
      if (inst.errorStatus != 0) {
        req.response
          ..statusCode = inst.errorStatus
          ..headers.contentType = ContentType.json
          ..write(inst.errorBody);
        await req.response.close();
        return;
      }
      if (inst.failUntil > 0) {
        inst.failUntil--;
        req.response
          ..statusCode = 503
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'mock upstream unavailable'}));
        await req.response.close();
        return;
      }
      if (inst.sse) {
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType('text', 'event-stream');
        req.response.write('data: {"choices":[{"delta":{"content":"hi"}}]}\n\n');
        req.response.write('data: [DONE]\n\n');
        await req.response.close();
        return;
      }
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'model': decoded['model'] ?? 'gpt-4o-mini',
          'usage': {'prompt_tokens': 5, 'completion_tokens': 7},
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'hello from mock'}
            }
          ],
        }));
      await req.response.close();
    });
    return inst;
  }

  Future<void> close() => server.close(force: true);
}

void main() {
  late MockUpstream mock;
  late KeyManager keyManager;
  late LogService logService;
  late UserSettings settings;

  setUpAll(() async {
    final tmp = Directory.systemTemp.createTempSync('ai_relay_test');
    Hive.init(tmp.path);
    await Hive.openBox('api_keys');
    await Hive.openBox('request_logs');
    await Hive.openBox('routing_rules');
    await Hive.openBox('models');
    keyManager = KeyManager(Hive.box('api_keys'));
    logService = LogService(Hive.box('request_logs'));
    settings = UserSettings(
      rulesEnabled: true,
      rateLimitEnabled: false,
      maxRetryKeys: 3,
      upstreamTimeoutSeconds: 5,
    );
    EncryptionUtil.init(EncryptionUtil.generateMasterKeyBase64());
  });

  /// 用给定规则/key 起一个代理实例（每组测试独立）
  Future<ProxyServer> startProxy({
    required String baseUrl,
    List<RoutingRule> rules = const [],
    bool virtual = false,
  }) async {
    await keyManager.createKey(
      provider: 'openai',
      plainKey: 'sk-test-key',
      name: 'mock-key',
      baseUrl: baseUrl,
    );
    // 虚拟层默认关闭（纯转发）；仅虚拟模型用例显式开启
    final proxySettings = virtual
        ? settings.copyWith(virtualModelsEnabled: true)
        : settings;
    final proxySrv = ProxyServer(
      keyManager: keyManager,
      loadBalancer: LoadBalancer(),
      logService: logService,
      ruleEngine: RuleEngine(rules: rules),
      quotaMonitor: QuotaMonitor(settings: proxySettings),
      settings: proxySettings,
      port: 0,
    );
    await proxySrv.start();
    return proxySrv;
  }

  Future<void> stopProxy(ProxyServer p) async {
    await p.stop();
    for (final k in keyManager.getAll()) {
      await keyManager.deleteKey(k.id);
    }
  }

  test('虚拟模型请求被改写为真实模型名转发到上游', () async {
    mock = await MockUpstream.bind();
    final p = await startProxy(
      baseUrl: 'http://127.0.0.1:${mock.port}/v1',
      virtual: true, // 本用例验证虚拟层改写，显式开启
    );
    // 客户端发送能力虚拟模型 ID（第三方客户端从 /v1/models 拉取到的）
    final resp = await postJson(
      'http://127.0.0.1:${p.port}/v1/chat/completions',
      {'model': 'chat-premium', 'messages': [{'role': 'user', 'content': 'hi'}]},
    );
    expect(resp.statusCode, 200);
    // 上游必须收到改写后的真实模型名，而不是虚拟 ID
    expect(mock.received.first['model'], 'gpt-4o');
    // 日志应记录实际发送的模型名
    expect(logService.recent.first.actualModel, 'gpt-4o');
    await stopProxy(p);
    await mock.close();
  });

  test('上游 404 时日志包含上游错误正文（诊断模型不存在原因）', () async {
    mock = await MockUpstream.bind();
    mock.errorStatus = 404;
    mock.errorBody =
        '{"error":{"message":"The model \'gpt-4o\' does not exist or you do not have access to it"}}';
    final p = await startProxy(
      baseUrl: 'http://127.0.0.1:${mock.port}/v1',
      virtual: true, // 本用例验证虚拟层改写，显式开启
    );
    final resp = await postJson(
      'http://127.0.0.1:${p.port}/v1/chat/completions',
      {'model': 'chat-premium', 'messages': []},
    );
    expect(resp.statusCode, 503); // 重试耗尽后返回 503
    // 日志错误信息应包含上游返回的真实原因
    final log = logService.recent.first;
    expect(log.error, contains('404'));
    expect(log.error, contains('does not exist'));
    expect(log.actualModel, 'gpt-4o');
    await stopProxy(p);
    await mock.close();
  });

  test('模型库含「模型名即虚拟 ID」条目时仍改写为真实模型（不把虚拟 ID 透传上游）',
      () async {
    mock = await MockUpstream.bind();
    // 模型库中存在一个名字本身就是虚拟 ID 的模型（如上游是另一个中转站）
    final repo = ModelRepository(Hive.box('models'));
    await repo.clear();
    await repo.upsertAll([
      ModelInfo.unified(
        provider: 'openai',
        name: 'chat-premium',
        virtualId: 'chat-premium',
        capabilities: const ['chat'],
        lastSynced: DateTime.now().millisecondsSinceEpoch,
      ),
    ]);
    await keyManager.createKey(
      provider: 'openai',
      plainKey: 'sk-virtual-name',
      name: 'virtual-name-key',
      baseUrl: 'http://127.0.0.1:${mock.port}/v1',
    );
    final p = ProxyServer(
      keyManager: keyManager,
      loadBalancer: LoadBalancer(),
      logService: logService,
      ruleEngine: RuleEngine(),
      quotaMonitor: QuotaMonitor(
          settings: settings.copyWith(virtualModelsEnabled: true)),
      settings: settings.copyWith(virtualModelsEnabled: true),
      modelRepository: repo,
      port: 0,
    );
    await p.start();
    final resp = await postJson(
      'http://127.0.0.1:${p.port}/v1/chat/completions',
      {'model': 'chat-premium', 'messages': []},
    );
    expect(resp.statusCode, 200);
    // 上游必须收到改写后的真实模型（回退到内置典型 gpt-4o），而不是虚拟 ID
    expect(mock.received.first['model'], 'gpt-4o');
    await p.stop();
    for (final k in keyManager.getAll()) {
      await keyManager.deleteKey(k.id);
    }
    await repo.clear();
    await mock.close();
  });

  test('健康检查接口返回 ok', () async {
    mock = await MockUpstream.bind();
    final p = await startProxy(baseUrl: 'http://127.0.0.1:${mock.port}/v1');
    final body = await httpGetBody('http://127.0.0.1:${p.port}/health');
    final json = jsonDecode(body);
    expect(json['status'], 'ok');
    await stopProxy(p);
    await mock.close();
  });

  test('转发 /v1/chat/completions 到上游并返回 200 + 计费', () async {
    mock = await MockUpstream.bind();
    final p = await startProxy(baseUrl: 'http://127.0.0.1:${mock.port}/v1');
    final resp = await postJson(
      'http://127.0.0.1:${p.port}/v1/chat/completions',
      {'model': 'gpt-4o-mini', 'messages': [{'role': 'user', 'content': 'hi'}]},
    );
    expect(resp.statusCode, 200);
    final json = jsonDecode(resp.body);
    expect(json['choices'][0]['message']['content'], 'hello from mock');

    // 日志中应记录 token 计费
    final log = logService.recent.first;
    expect(log.provider, 'openai');
    expect(log.promptTokens, 5);
    expect(log.completionTokens, 7);
    expect(mock.received.first['model'], 'gpt-4o-mini');
    await stopProxy(p);
    await mock.close();
  });

  test('命中的路由规则可改写目标提供商/分组', () async {
    mock = await MockUpstream.bind();
    // 规则：gpt-4 模型走 openai（覆盖检测）
    final rule = RoutingRule(
      id: 'r1',
      name: 'gpt4 路由',
      condition: "request.model contains 'gpt-4'",
      action: "use_provider('openai')",
      enabled: true,
      order: 0,
    );
    final p = await startProxy(
      baseUrl: 'http://127.0.0.1:${mock.port}/v1',
      rules: [rule],
    );
    final resp = await postJson(
      'http://127.0.0.1:${p.port}/v1/chat/completions',
      {'model': 'gpt-4', 'messages': []},
    );
    expect(resp.statusCode, 200);
    expect(logService.recent.first.ruleName, 'gpt4 路由');
    await stopProxy(p);
    await mock.close();
  });

  test('上游前两次 503 时自动重试切换 key 并最终成功', () async {
    mock = await MockUpstream.bind();
    mock.failUntil = 2; // 前两次失败
    // 提供两个 key 以触发切换
    await keyManager.createKey(
      provider: 'openai',
      plainKey: 'sk-a',
      name: 'key-a',
      baseUrl: 'http://127.0.0.1:${mock.port}/v1',
    );
    await keyManager.createKey(
      provider: 'openai',
      plainKey: 'sk-b',
      name: 'key-b',
      baseUrl: 'http://127.0.0.1:${mock.port}/v1',
    );
    final p = ProxyServer(
      keyManager: keyManager,
      loadBalancer: LoadBalancer(),
      logService: logService,
      ruleEngine: RuleEngine(),
      quotaMonitor: QuotaMonitor(settings: settings),
      settings: settings,
      port: 0,
    );
    await p.start();
    final resp = await postJson(
      'http://127.0.0.1:${p.port}/v1/chat/completions',
      {'model': 'gpt-4o-mini', 'messages': []},
    );
    expect(resp.statusCode, 200);
    // 上游前两次 503 均被重试，第三次成功
    expect(mock.received.length, 3);
    await p.stop();
    for (final k in keyManager.getAll()) {
      await keyManager.deleteKey(k.id);
    }
    await mock.close();
  });

  test('SSE 流式响应被透传', () async {
    mock = await MockUpstream.bind();
    mock.sse = true;
    final p = await startProxy(baseUrl: 'http://127.0.0.1:${mock.port}/v1');
    final client = HttpClient();
    final req = await client.postUrl(
        Uri.parse('http://127.0.0.1:${p.port}/v1/chat/completions'));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({'model': 'gpt-4o-mini', 'stream': true}));
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    expect(body, contains('delta'));
    expect(logService.recent.first.streaming, isTrue);
    client.close();
    await stopProxy(p);
    await mock.close();
  });

  test('无可用 key 时返回 503', () async {
    mock = await MockUpstream.bind();
    await keyManager.createKey(
      provider: 'openai',
      plainKey: 'sk-x',
      name: 'off',
      baseUrl: 'http://127.0.0.1:${mock.port}/v1',
    );
    final created = keyManager.getAll().last;
    await keyManager.updateKey(created.copyWith(status: KeyStatus.inactive));
    // 注意：不复用 startProxy（它会额外创建一个可用 key），仅保留已停用的 key
    final p = ProxyServer(
      keyManager: keyManager,
      loadBalancer: LoadBalancer(),
      logService: logService,
      ruleEngine: RuleEngine(),
      quotaMonitor: QuotaMonitor(settings: settings),
      settings: settings,
      port: 0,
    );
    await p.start();
    final resp = await postJson(
      'http://127.0.0.1:${p.port}/v1/chat/completions',
      {'model': 'gpt-4o-mini'},
    );
    expect(resp.statusCode, 503);
    await p.stop();
    for (final k in keyManager.getAll()) {
      await keyManager.deleteKey(k.id);
    }
    await mock.close();
  });

  test('20 并发请求均成功', () async {
    mock = await MockUpstream.bind();
    final p = await startProxy(baseUrl: 'http://127.0.0.1:${mock.port}/v1');
    final tasks = <Future>[];
    for (var i = 0; i < 20; i++) {
      tasks.add(postJson(
        'http://127.0.0.1:${p.port}/v1/chat/completions',
        {'model': 'gpt-4o-mini', 'messages': []},
      ).then((r) => expect(r.statusCode, 200)));
    }
    await Future.wait(tasks);
    expect(mock.received.length, 20);
    await stopProxy(p);
    await mock.close();
  });

  test('启用缓存后重复请求命中 HIT 且仅转发一次', () async {
    mock = await MockUpstream.bind();
    final cacheSettings = UserSettings(
      rulesEnabled: false,
      rateLimitEnabled: false,
      cacheEnabled: true,
      cacheTtlSeconds: 60,
      cacheMaxEntries: 500,
      upstreamTimeoutSeconds: 5,
    );
    await keyManager.createKey(
      provider: 'openai',
      plainKey: 'sk-cache',
      name: 'cache-key',
      baseUrl: 'http://127.0.0.1:${mock.port}/v1',
    );
    final p = ProxyServer(
      keyManager: keyManager,
      loadBalancer: LoadBalancer(),
      logService: logService,
      ruleEngine: RuleEngine(),
      quotaMonitor: QuotaMonitor(settings: cacheSettings),
      settings: cacheSettings,
      port: 0,
    );
    await p.start();
    final payload = {
      'model': 'gpt-4o-mini',
      'messages': [
        {'role': 'user', 'content': 'cache me'}
      ]
    };
    final r1 = await postJsonEx(
        'http://127.0.0.1:${p.port}/v1/chat/completions', payload);
    final r2 = await postJsonEx(
        'http://127.0.0.1:${p.port}/v1/chat/completions', payload);
    expect(r1.statusCode, 200);
    expect(r2.statusCode, 200);
    expect(r1.headers['x-relay-cache'], 'MISS');
    expect(r2.headers['x-relay-cache'], 'HIT');
    expect(mock.received.length, 1); // 仅首次转发到上游
    await p.stop();
    for (final k in keyManager.getAll()) {
      await keyManager.deleteKey(k.id);
    }
    await mock.close();
  });

  test('入口全局限流：超过阈值返回 429 + Retry-After', () async {
    mock = await MockUpstream.bind();
    final limitSettings = UserSettings(
      rulesEnabled: false,
      rateLimitEnabled: true,
      globalRpmLimit: 2,
      upstreamTimeoutSeconds: 5,
    );
    await keyManager.createKey(
      provider: 'openai',
      plainKey: 'sk-rl',
      name: 'rl-key',
      baseUrl: 'http://127.0.0.1:${mock.port}/v1',
    );
    final p = ProxyServer(
      keyManager: keyManager,
      loadBalancer: LoadBalancer(),
      logService: logService,
      ruleEngine: RuleEngine(),
      quotaMonitor: QuotaMonitor(settings: limitSettings),
      settings: limitSettings,
      port: 0,
    );
    await p.start();
    final url = 'http://127.0.0.1:${p.port}/v1/chat/completions';
    final r1 = await postJson(url, {'model': 'gpt-4o-mini'});
    final r2 = await postJson(url, {'model': 'gpt-4o-mini'});
    final r3 = await postJson(url, {'model': 'gpt-4o-mini'});
    expect(r1.statusCode, 200);
    expect(r2.statusCode, 200);
    expect(r3.statusCode, 429);
    expect(mock.received.length, 2); // 第 3 次在入口被拦，未到上游
    await p.stop();
    for (final k in keyManager.getAll()) {
      await keyManager.deleteKey(k.id);
    }
    await mock.close();
  });
}

Future<String> httpGetBody(String url) async {
  final client = HttpClient();
  final request = await client.getUrl(Uri.parse(url));
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  client.close();
  return body;
}

class Resp {
  final int statusCode;
  final String body;
  Resp(this.statusCode, this.body);
}

Future<Resp> postJson(String url, Map<String, dynamic> payload) async {
  final client = HttpClient();
  final request = await client.postUrl(Uri.parse(url));
  request.headers.contentType = ContentType.json;
  request.write(jsonEncode(payload));
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  client.close();
  return Resp(response.statusCode, body);
}

class RespEx {
  final int statusCode;
  final String body;
  final Map<String, String> headers;
  RespEx(this.statusCode, this.body, this.headers);
}

Future<RespEx> postJsonEx(String url, Map<String, dynamic> payload) async {
  final client = HttpClient();
  final request = await client.postUrl(Uri.parse(url));
  request.headers.contentType = ContentType.json;
  request.write(jsonEncode(payload));
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  final headers = <String, String>{};
  response.headers.forEach((k, v) => headers[k.toLowerCase()] = v.join(','));
  client.close();
  return RespEx(response.statusCode, body, headers);
}
