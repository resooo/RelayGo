import 'dart:async';
import 'dart:convert';
import 'package:relaygo/config/constants.dart';
import 'package:relaygo/models/api_key.dart';
import 'package:relaygo/models/model_info.dart';
import 'package:relaygo/models/provider_config.dart';
import 'package:relaygo/models/key_test.dart';
import 'package:relaygo/services/providers/base_provider.dart';
import 'package:relaygo/utils/encryption.dart';

/// Anthropic（Claude）适配器
///
/// 使用 `x-api-key` + `anthropic-version` 鉴权，`/v1/messages` 原生支持 SSE 流式。
class AnthropicProvider extends BaseHttpProvider {
  /// 默认 API 版本，可通过 key.metadata['anthropic_version'] 覆盖
  static const String defaultVersion = '2023-06-01';

  @override
  ProviderType get type => ProviderType.anthropic;

  @override
  String resolveBaseUrl(ApiKey key) =>
      ProviderConfig.resolveBaseUrl(ProviderType.anthropic, key.baseUrl);

  @override
  Map<String, String> authHeaders(String decryptedKey) => {
        'x-api-key': decryptedKey,
        'anthropic-version': defaultVersion,
      };

  @override
  Map<String, String> providerHeaders(ApiKey key) {
    final v = key.metadata['anthropic_version'];
    if (v is String && v.trim().isNotEmpty) {
      return {'anthropic-version': v.trim()};
    }
    return const {};
  }

  @override
  Future<List<ModelInfo>> fetchModels(ApiKey key) async {
    final json = await modelsGet(key, '/v1/models');
    return BaseHttpProvider.parseModelsAnthropic(
        json, key.provider, BaseHttpProvider.nowMs());
  }

  /// Anthropic 无 /models 接口，改用最小 [POST /v1/messages] 验证鉴权：
  /// 返回 401/403（鉴权被拒）视为无效，其余均视为 key 可用，避免模型名
  /// 差异造成的误判。
  @override
  Future<KeyTestOutcome> test(ApiKey key) async {
    final sw = Stopwatch()..start();
    try {
      final uri = buildUri(key, const ProxyRequest(method: 'POST', path: '/v1/messages'));
      final req = await BaseHttpProvider.client
          .openUrl('POST', uri)
          .timeout(const Duration(seconds: 10));
      authHeaders(EncryptionUtil.decrypt(key.encryptedKey))
          .forEach(req.headers.set);
      providerHeaders(key).forEach(req.headers.set);
      req.headers.set('content-type', 'application/json');
      req.headers.set('user-agent', 'RelayGo/${Constants.appVersion}');
      final model = key.metadata['test_model'] ?? 'claude-3-5-sonnet-latest';
      req.add(utf8.encode(jsonEncode({
        'model': model,
        'max_tokens': 1,
        'messages': [
          {'role': 'user', 'content': 'hi'}
        ],
      })));
      final resp = await req.close().timeout(const Duration(seconds: 12));
      await resp.drain<void>();
      final elapsed = sw.elapsed;
      final code = resp.statusCode;
      if (code != 401 && code != 403) return KeyTestOutcome.valid(elapsed);
      return KeyTestOutcome.invalid(code, '', elapsed);
    } on TimeoutException {
      return KeyTestOutcome.timeout();
    } catch (e) {
      final msg = e.toString().replaceFirst(RegExp(r'^.*Exception: '), '');
      return KeyTestOutcome.failure(msg);
    }
  }
}
