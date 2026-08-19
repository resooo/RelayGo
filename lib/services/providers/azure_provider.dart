import 'dart:async';
import 'package:relaygo/models/api_key.dart';
import 'package:relaygo/models/model_info.dart';
import 'package:relaygo/models/provider_config.dart';
import 'package:relaygo/models/key_test.dart';
import 'package:relaygo/services/providers/base_provider.dart';
import 'package:relaygo/utils/encryption.dart';

/// Azure OpenAI 适配器
///
/// 端点形如 `https://{resource}.openai.azure.com`（可直接带
/// `/openai/deployments/{deployment}`），鉴权使用 `api-key` 头，
/// 且所有请求必须带 `api-version` query 参数。
///
/// 支持把 OpenAI 风格路径（`/v1/chat/completions`）自动改写为 Azure 路径
/// （`/openai/deployments/{deployment}/chat/completions?api-version=...`），
/// 因此现有 OpenAI SDK 客户端无需改动即可走 Azure。
class AzureProvider extends BaseHttpProvider {
  static const String defaultApiVersion = '2024-02-01';

  @override
  ProviderType get type => ProviderType.azure;

  @override
  String resolveBaseUrl(ApiKey key) {
    final url = ProviderConfig.resolveBaseUrl(ProviderType.azure, key.baseUrl);
    if (url.isEmpty) {
      throw StateError('Azure 需要在 key 中配置端点（如 https://xxx.openai.azure.com）');
    }
    return url;
  }

  String _apiVersion(ApiKey key) {
    final v = key.metadata['api_version'];
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return defaultApiVersion;
  }

  String? _deployment(ApiKey key) {
    final v = key.metadata['deployment'];
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return null;
  }

  @override
  String get testPath => '/openai/models';

  @override
  Uri buildUri(ApiKey key, ProxyRequest request) {
    final base = resolveBaseUrl(key);
    var path = request.path;

    // OpenAI 风格 -> Azure 风格
    if (path.startsWith('/v1/')) {
      final rest = path.substring(3); // '/chat/completions'
      if (base.contains('/openai/deployments/')) {
        path = rest; // base 已含部署名
      } else {
        final deployment = _deployment(key) ??
            (request.model.isNotEmpty ? request.model : null);
        if (deployment == null) {
          throw StateError('Azure 需要指定部署名（key.metadata.deployment 或请求体 model）');
        }
        path = '/openai/deployments/$deployment$rest';
      }
    }

    final uri = Uri.parse(BaseHttpProvider.joinPath(
        base, request.query.isEmpty ? path : '$path?${request.query}'));
    if (uri.queryParameters.containsKey('api-version')) return uri;
    return uri.replace(queryParameters: <String, String>{
      ...uri.queryParameters,
      'api-version': _apiVersion(key),
    });
  }

  @override
  Map<String, String> authHeaders(String decryptedKey) =>
      {'api-key': decryptedKey};

  @override
  Future<List<ModelInfo>> fetchModels(ApiKey key) async {
    final api = _apiVersion(key);
    final json = await modelsGet(key, '/openai/models?api-version=$api');
    return BaseHttpProvider.parseModelsOpenAI(
        json, key.provider, BaseHttpProvider.nowMs());
  }

  /// Azure 没有统一的 key 校验接口：
  /// 以「端点可达且鉴权未被拒（非 401/403）」判定 key 有效。
  @override
  Future<KeyTestOutcome> test(ApiKey key) async {
    final sw = Stopwatch()..start();
    try {
      final uri = buildUri(key, const ProxyRequest(method: 'GET', path: '/openai/models'));
      final req = await BaseHttpProvider.client
          .openUrl('GET', uri)
          .timeout(const Duration(seconds: 10));
      authHeaders(EncryptionUtil.decrypt(key.encryptedKey))
          .forEach(req.headers.set);
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
