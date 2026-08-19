import 'package:relaygo/models/api_key.dart';
import 'package:relaygo/models/provider_config.dart';
import 'package:relaygo/services/providers/base_provider.dart';

/// OpenAI 适配器
///
/// 覆盖 GPT 系列、DALL·E、Embeddings、Whisper/TTS 等全部 `/v1/*` 接口。
class OpenAIProvider extends BaseHttpProvider {
  @override
  ProviderType get type => ProviderType.openai;

  @override
  String resolveBaseUrl(ApiKey key) =>
      ProviderConfig.resolveBaseUrl(ProviderType.openai, key.baseUrl);

  @override
  String get testPath => '/v1/models';

  @override
  Map<String, String> authHeaders(String decryptedKey) {
    final headers = <String, String>{'authorization': 'Bearer $decryptedKey'};
    return headers;
  }
}
