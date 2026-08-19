// 端到端集成测试：自定义提供商场景（用户报告：key 测试成功但模型同步失败 + 第三方 503）
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:relaygo/models/api_key.dart';
import 'package:relaygo/models/user_settings.dart';
import 'package:relaygo/services/key_manager.dart';
import 'package:relaygo/services/load_balancer.dart';
import 'package:relaygo/services/log_service.dart';
import 'package:relaygo/services/quota_monitor.dart';
import 'package:relaygo/services/rule_engine.dart';
import 'package:relaygo/services/proxy_server.dart';
import 'package:relaygo/services/model_sync_service.dart';
import 'package:relaygo/database/model_repository.dart';
import 'package:relaygo/utils/encryption.dart';

/// 简易 mock 上游：支持 /models 与 /chat/completions
class MockUpstream {
  final HttpServer server;
  final int port;
  final List<String> paths = [];
  int chatStatus = 200;

  MockUpstream(this.server, this.port);

  static Future<MockUpstream> bind() async {
    final s = await HttpServer.bind('127.0.0.1', 0);
    final inst = MockUpstream(s, s.port);
    s.listen((req) async {
      inst.paths.add(req.uri.path);
      if (req.uri.path.endsWith('/models')) {
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'object': 'list',
            'data': [
              {'id': 'SenseChat-5', 'owned_by': 'sensetime'},
              {'id': 'SenseChat-5.5', 'owned_by': 'sensetime'},
            ]
          }));
        await req.response.close();
        return;
      }
      if (req.uri.path.endsWith('/chat/completions')) {
        req.response
          ..statusCode = inst.chatStatus
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'model': 'SenseChat-5',
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': 'hello from sensetime mock'
                }
              }
            ],
          }));
        await req.response.close();
        return;
      }
      req.response
        ..statusCode = 404
        ..write('not found');
      await req.response.close();
    });
    return inst;
  }

  Future<void> close() => server.close(force: true);
}

void main() {
  late MockUpstream mock;
  late KeyManager keyManager;
  late ModelRepository modelRepository;
  late UserSettings settings;

  setUpAll(() async {
    final tmp = Directory.systemTemp.createTempSync('ai_relay_custom_test');
    Hive.init(tmp.path);
    await Hive.openBox('api_keys');
    await Hive.openBox('request_logs');
    await Hive.openBox('routing_rules');
    await Hive.openBox('models');
    keyManager = KeyManager(Hive.box('api_keys'));
    modelRepository = ModelRepository(Hive.box('models'));
    settings = UserSettings(
      rulesEnabled: true,
      rateLimitEnabled: false,
      maxRetryKeys: 3,
      upstreamTimeoutSeconds: 5,
    );
    EncryptionUtil.init(EncryptionUtil.generateMasterKeyBase64());
  });

  tearDown(() async {
    for (final k in keyManager.getAll()) {
      await keyManager.deleteKey(k.id);
    }
    await modelRepository.clear();
  });

  test('自定义提供商：key 测试成功 + 模型同步成功 + 第三方转发成功', () async {
    mock = await MockUpstream.bind();
    final baseUrl = 'http://127.0.0.1:${mock.port}/v1';

    // 1) 添加自定义提供商 key（provider='custom', providerId='sensetime'）
    final key = await keyManager.createKey(
      provider: 'custom',
      providerId: 'sensetime',
      plainKey: 'sk-sensetime',
      name: '商汤',
      baseUrl: baseUrl,
      metadata: {
        'api_path': '/chat/completions',
        'model_list_path': '/models',
        'auth_header': 'authorization',
        'auth_prefix': 'Bearer ',
      },
    );

    // 2) key 测试应成功
    final outcome = await keyManager.testKey(key);
    expect(outcome.ok, isTrue, reason: 'key 测试应成功：${outcome.error}');

    // 3) 模型同步应成功，模型归入 sensetime
    final sync = ModelSyncService(keyManager, modelRepository);
    final result = await sync.syncProvider('custom', providerId: 'sensetime');
    expect(result.success, isTrue, reason: '模型同步应成功：${result.error}');
    expect(result.models.length, 2);
    expect(modelRepository.getByProvider('sensetime').length, 2);

    // 4) 第三方请求 /v1/chat/completions 应转发成功
    final proxySrv = ProxyServer(
      keyManager: keyManager,
      loadBalancer: LoadBalancer(),
      logService: LogService(Hive.box('request_logs')),
      ruleEngine: RuleEngine(),
      quotaMonitor: QuotaMonitor(settings: settings),
      settings: settings,
      modelRepository: modelRepository,
      port: 0,
    );
    await proxySrv.start();
    final resp = await postJson(
      'http://127.0.0.1:${proxySrv.port}/v1/chat/completions',
      {'model': 'SenseChat-5', 'messages': [{'role': 'user', 'content': 'hi'}]},
    );
    expect(resp.statusCode, 200,
        reason: '第三方请求应 200，实际 ${resp.statusCode}: ${resp.body}');
    expect(resp.body, contains('hello from sensetime mock'));

    // 5) /v1/models 应返回聚合模型（明细模式查看真实模型）
    final modelsResp = await httpGetBody(
        'http://127.0.0.1:${proxySrv.port}/v1/models?expand=1');
    final modelsJson = jsonDecode(modelsResp) as Map<String, dynamic>;
    final data = modelsJson['data'] as List;
    expect(data.length, 2, reason: '模型列表应有 2 个模型');
    final ids = data.map((m) => m['id']).toSet();
    expect(ids, containsAll(['SenseChat-5', 'SenseChat-5.5']));

    await proxySrv.stop();
    await mock.close();
  });

  test('自定义提供商：上游 chat 返回 5xx 时，503 应包含真实错误而非误导', () async {
    mock = await MockUpstream.bind();
    mock.chatStatus = 500;
    final baseUrl = 'http://127.0.0.1:${mock.port}/v1';
    await keyManager.createKey(
      provider: 'custom',
      providerId: 'sensetime',
      plainKey: 'sk-sensetime',
      name: '商汤',
      baseUrl: baseUrl,
      metadata: {
        'api_path': '/chat/completions',
        'model_list_path': '/models',
        'auth_header': 'authorization',
        'auth_prefix': 'Bearer ',
      },
    );
    final proxySrv = ProxyServer(
      keyManager: keyManager,
      loadBalancer: LoadBalancer(),
      logService: LogService(Hive.box('request_logs')),
      ruleEngine: RuleEngine(),
      quotaMonitor: QuotaMonitor(settings: settings),
      settings: settings,
      modelRepository: modelRepository,
      port: 0,
    );
    await proxySrv.start();
    final resp = await postJson(
      'http://127.0.0.1:${proxySrv.port}/v1/chat/completions',
      {'model': 'SenseChat-5', 'messages': []},
    );
    // 上游 5xx 被重试耗尽后返回 503，但错误信息应反映上游问题
    expect(resp.statusCode, 503);
    expect(resp.body, contains('上游 HTTP 500'),
        reason: '503 应说明是上游 5xx 而非误导为无 key：${resp.body}');
    await proxySrv.stop();
    await mock.close();
  });

  test('无 active key 时，503 应返回可定位的具体原因', () async {
    mock = await MockUpstream.bind();
    final baseUrl = 'http://127.0.0.1:${mock.port}/v1';
    // 创建后立即停用，模拟「key 状态非 active」
    final key = await keyManager.createKey(
      provider: 'custom',
      providerId: 'sensetime',
      plainKey: 'sk-sensetime',
      name: '商汤',
      baseUrl: baseUrl,
      metadata: {
        'api_path': '/chat/completions',
        'model_list_path': '/models',
        'auth_header': 'authorization',
        'auth_prefix': 'Bearer ',
      },
    );
    await keyManager.updateKey(key.copyWith(status: KeyStatus.inactive));
    final proxySrv = ProxyServer(
      keyManager: keyManager,
      loadBalancer: LoadBalancer(),
      logService: LogService(Hive.box('request_logs')),
      ruleEngine: RuleEngine(),
      quotaMonitor: QuotaMonitor(settings: settings),
      settings: settings,
      modelRepository: modelRepository,
      port: 0,
    );
    await proxySrv.start();
    final resp = await postJson(
      'http://127.0.0.1:${proxySrv.port}/v1/chat/completions',
      {'model': 'SenseChat-5', 'messages': []},
    );
    expect(resp.statusCode, 503);
    expect(resp.body, contains('1 个 key 已停用'),
        reason: '503 应说明 key 已停用：${resp.body}');
    expect(resp.body, contains('无可用 key'),
        reason: '503 应说明无可用 key：${resp.body}');
    await proxySrv.stop();
    await mock.close();
  });

  test('限流开启时，fresh key 仍应正常转发（不被误限流）', () async {
    mock = await MockUpstream.bind();
    final baseUrl = 'http://127.0.0.1:${mock.port}/v1';
    await keyManager.createKey(
      provider: 'custom',
      providerId: 'sensetime',
      plainKey: 'sk-sensetime',
      name: '商汤',
      baseUrl: baseUrl,
      metadata: {
        'api_path': '/chat/completions',
        'model_list_path': '/models',
        'auth_header': 'authorization',
        'auth_prefix': 'Bearer ',
      },
    );
    final proxySrv = ProxyServer(
      keyManager: keyManager,
      loadBalancer: LoadBalancer(),
      logService: LogService(Hive.box('request_logs')),
      ruleEngine: RuleEngine(),
      quotaMonitor: QuotaMonitor(settings: settings),
      settings: settings.copyWith(rateLimitEnabled: true),
      modelRepository: modelRepository,
      port: 0,
    );
    await proxySrv.start();
    final resp = await postJson(
      'http://127.0.0.1:${proxySrv.port}/v1/chat/completions',
      {'model': 'SenseChat-5', 'messages': [{'role': 'user', 'content': 'hi'}]},
    );
    expect(resp.statusCode, 200,
        reason: '限流开启时 fresh key 应正常转发，实际 ${resp.statusCode}: ${resp.body}');
    await proxySrv.stop();
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
