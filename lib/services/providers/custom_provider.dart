import 'package:relaygo/models/api_key.dart';
import 'package:relaygo/models/model_info.dart';
import 'package:relaygo/models/provider_config.dart';
import 'package:relaygo/models/key_test.dart';
import 'package:relaygo/services/providers/base_provider.dart';

/// 自定义提供商适配器（OpenAI 兼容接口）
///
/// 支持通过 key.metadata 定制：
///  - `headers`：自定义请求头 Map（如 `{"x-tenant":"abc"}`）
///  - `auth_header`：鉴权头名，默认 `authorization`
///  - `auth_prefix`：鉴权值前缀，默认 `Bearer `（设为空串则直接放明文 key）
///  - `test_path`：连通性测试路径，默认 `/models`
///  - `api_path`：聊天补全接口路径，默认 `/chat/completions`
///  - `model_list_path`：模型列表路径，默认 `/models`
class CustomProvider extends BaseHttpProvider {
  @override
  ProviderType get type => ProviderType.custom;

  @override
  String resolveBaseUrl(ApiKey key) {
    final url = ProviderConfig.resolveBaseUrl(ProviderType.custom, key.baseUrl);
    if (url.isEmpty) {
      throw StateError('自定义提供商必须配置 base_url');
    }
    return url;
  }

  ApiKey? _key; // 由 forward/test 注入，用于读取 metadata 定制项

  @override
  Map<String, String> authHeaders(String decryptedKey) {
    final meta = _key?.metadata ?? const <String, dynamic>{};
    final headerName =
        (meta['auth_header'] as String?)?.trim().toLowerCase() ?? 'authorization';
    final prefix = meta.containsKey('auth_prefix')
        ? (meta['auth_prefix'] as String? ?? '')
        : 'Bearer ';
    return {headerName.isEmpty ? 'authorization' : headerName: '$prefix$decryptedKey'};
  }

  @override
  Map<String, String> providerHeaders(ApiKey key) {
    final raw = key.metadata['headers'];
    if (raw is Map) {
      return raw.map((k, v) => MapEntry('$k', '$v'));
    }
    return const {};
  }

  @override
  String get testPath {
    final p = _key?.metadata['test_path'];
    if (p is String && p.trim().isNotEmpty) return p.trim();
    final m = _key?.metadata['model_list_path'];
    if (m is String && m.trim().isNotEmpty) return m.trim();
    return '/models';
  }

  /// 构造上游 URI：聊天补全接口使用提供商配置的 api_path，
  /// 其余接口（models/embeddings 等）沿用请求路径。
  @override
  Uri buildUri(ApiKey key, ProxyRequest request) {
    final base = resolveBaseUrl(key);
    final path = _mapPath(key, request.path);
    final query = request.query;
    return Uri.parse(
        BaseHttpProvider.joinPath(base, query.isEmpty ? path : '$path?$query'));
  }

  String _mapPath(ApiKey key, String path) {
    // 聊天补全 / 补全接口使用提供商配置的 api_path
    if (path.endsWith('/chat/completions') || path.endsWith('/completions')) {
      final apiPath = key.metadata['api_path'];
      if (apiPath is String && apiPath.trim().isNotEmpty) {
        return apiPath.trim();
      }
    }
    return path;
  }

  @override
  Future<List<ModelInfo>> fetchModels(ApiKey key) async {
    final p = key.metadata['model_list_path'];
    final path = (p is String && p.trim().isNotEmpty) ? p.trim() : '/models';
    final json = await modelsGet(key, path);
    // 模型归属：优先使用 providerId（如 sensetime），否则用 provider 名（custom）
    final modelProvider =
        key.providerId.isNotEmpty ? key.providerId : key.provider;
    return BaseHttpProvider.parseModelsOpenAI(
        json, modelProvider, BaseHttpProvider.nowMs());
  }

  @override
  Future<ProviderResult> forward(ProxyRequest request, ApiKey key,
      {Duration? timeout}) {
    _key = key;
    return super.forward(request, key, timeout: timeout);
  }

  @override
  Future<KeyTestOutcome> test(ApiKey key) {
    _key = key;
    return super.test(key);
  }
}