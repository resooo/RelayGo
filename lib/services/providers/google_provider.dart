import 'package:relaygo/models/api_key.dart';
import 'package:relaygo/models/model_info.dart';
import 'package:relaygo/models/provider_config.dart';
import 'package:relaygo/services/providers/base_provider.dart';
import 'package:relaygo/utils/encryption.dart';

/// Google AI（Gemini / PaLM）适配器
///
/// API key 通过 query 参数 `key=` 传递；流式接口为 `:streamGenerateContent`。
class GoogleProvider extends BaseHttpProvider {
  @override
  ProviderType get type => ProviderType.google;

  @override
  String resolveBaseUrl(ApiKey key) =>
      ProviderConfig.resolveBaseUrl(ProviderType.google, key.baseUrl);

  @override
  String get testPath => '/v1beta/models';

  @override
  Future<List<ModelInfo>> fetchModels(ApiKey key) async {
    final json = await modelsGet(key, '/v1beta/models');
    return BaseHttpProvider.parseModelsGoogle(
        json, key.provider, BaseHttpProvider.nowMs());
  }

  @override
  Uri buildUri(ApiKey key, ProxyRequest request) {
    final uri = Uri.parse(
        BaseHttpProvider.joinPath(resolveBaseUrl(key), request.fullPath));
    // 客户端可能已带 key，则不覆盖；否则注入中转站管理的 key
    if (uri.queryParameters.containsKey('key')) return uri;
    final decrypted = EncryptionUtil.decrypt(key.encryptedKey);
    return uri.replace(queryParameters: <String, String>{
      ...uri.queryParameters,
      'key': decrypted,
    });
  }

  @override
  Map<String, String> authHeaders(String decryptedKey) =>
      {'x-goog-api-key': decryptedKey};
}
