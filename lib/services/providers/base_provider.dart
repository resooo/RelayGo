import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:relaygo/config/constants.dart';
import 'package:relaygo/models/api_key.dart';
import 'package:relaygo/models/model_info.dart';
import 'package:relaygo/models/model_sync_exception.dart';
import 'package:relaygo/models/provider_config.dart';
import 'package:relaygo/models/key_test.dart';
import 'package:relaygo/utils/encryption.dart';

/// 已解析的代理请求
///
/// 代理服务器只读取请求体一次，之后以本对象在「规则引擎 → 负载均衡 → 提供商适配」
/// 之间传递，既避免重复读流，也让适配器可脱离 dart:io 单测。
class ProxyRequest {
  final String method;
  final String path; // 例：/v1/chat/completions
  final String query; // 原始 query（不含 '?'）
  final Map<String, String> headers;
  final List<int> body;
  final String model; // 请求体中的模型名
  final bool stream; // 请求体中的 stream 标记
  final String clientIp;

  const ProxyRequest({
    required this.method,
    required this.path,
    this.query = '',
    this.headers = const {},
    this.body = const [],
    this.model = '',
    this.stream = false,
    this.clientIp = '',
  });

  String get fullPath => query.isEmpty ? path : '$path?$query';

  int get bodyBytes => body.length;
}

/// 上游响应封装
class ProviderResult {
  final int statusCode;
  final Map<String, String> headers;
  final Stream<List<int>> body;
  final bool streaming; // 是否 SSE/流式（决定是否关闭输出缓冲）

  ProviderResult({
    required this.statusCode,
    required this.headers,
    required this.body,
    this.streaming = false,
  });
}

/// 提供商适配器接口
abstract class BaseProvider {
  ProviderType get type;

  /// 转发请求到上游，返回流式响应
  Future<ProviderResult> forward(ProxyRequest request, ApiKey key,
      {Duration? timeout});

  /// 测试 key 有效性
  Future<KeyTestOutcome> test(ApiKey key);

  /// 拉取该服务商的模型列表（统一格式），失败时抛 [ModelSyncException]
  Future<List<ModelInfo>> fetchModels(ApiKey key);
}

/// 基于 HTTP 的转发基类（OpenAI 兼容风格）
///
/// 子类只需实现 [resolveBaseUrl] 与 [authHeaders]；
/// 需要改写 URL（如 Google 把 key 放 query、Azure 追加 api-version）的重写 [buildUri]。
abstract class BaseHttpProvider implements BaseProvider {
  // ——— 共享连接池（性能优化：keep-alive 复用，避免每请求新建连接）———
  static HttpClient? _shared;

  static HttpClient get client {
    final c = _shared;
    if (c != null) return c;
    final created = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 30)
      ..maxConnectionsPerHost = 32
      ..autoUncompress = true; // 解压后转发，故响应头需剥离 content-encoding
    _shared = created;
    return created;
  }

  /// 释放共享连接池（应用退出/测试收尾）
  static void closeShared() {
    _shared?.close(force: true);
    _shared = null;
  }

  /// 解析最终 base url
  String resolveBaseUrl(ApiKey key);

  /// 鉴权头（传入已解密的明文 key）
  Map<String, String> authHeaders(String decryptedKey);

  /// 提供商附加头（在鉴权头之后应用，可读取具体 key 的配置）
  Map<String, String> providerHeaders(ApiKey key) => const {};

  /// 测试连通性用的相对路径
  String get testPath => '/models';

  /// 构造上游 URI
  Uri buildUri(ApiKey key, ProxyRequest request) {
    final base = resolveBaseUrl(key);
    return Uri.parse(joinPath(base, request.fullPath));
  }

  /// 拼接 base 与路径
  ///
  /// 处理两类常见问题：
  ///  1. 斜杠重复/缺失；
  ///  2. 前缀重叠 —— base 为 `https://api.openai.com/v1`、客户端路径为 `/v1/chat/completions`
  ///     时，直接相加会变成 `/v1/v1/chat/completions`，这里自动去掉重复段。
  static String joinPath(String base, String path) {
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    var p = path.startsWith('/') ? path : '/$path';
    final baseUri = Uri.tryParse(b);
    final segments = baseUri?.pathSegments ?? const <String>[];
    final last = segments.isEmpty ? '' : segments.last;
    if (last.isNotEmpty && (p == '/$last' || p.startsWith('/$last/'))) {
      p = p.substring(last.length + 1);
      if (p.isEmpty) p = '/';
    }
    return '$b$p';
  }

  /// 逐跳头（不应转发）
  static const Set<String> hopByHop = {
    'connection',
    'keep-alive',
    'proxy-authenticate',
    'proxy-authorization',
    'te',
    'trailers',
    'transfer-encoding',
    'upgrade',
  };

  /// 不从客户端转发到上游的请求头
  static final Set<String> _skipRequestHeaders = {
    ...hopByHop,
    'content-length', // 由本层按实际 body 重算
    'host', // 由 HttpClient 按目标地址设置
    'authorization', // 由适配器用中转站自己的 key 覆盖
    'x-api-key',
    'api-key',
    'accept-encoding', // 交给 HttpClient 协商，避免双重解压
    Constants.providerHeader,
    Constants.keyNameHeader,
  };

  /// 不回传给客户端的响应头
  static const Set<String> _skipResponseHeaders = {
    'transfer-encoding',
    'connection',
    'keep-alive',
    'content-encoding', // 已在本层解压
    'content-length', // 长度可能因解压而变化
  };

  /// 判断某响应头是否应被剥离（[lower] 为小写头名）
  static bool skipResponseHeader(String lower) =>
      _skipResponseHeaders.contains(lower);

  @override
  Future<ProviderResult> forward(ProxyRequest request, ApiKey key,
      {Duration? timeout}) async {
    final uri = buildUri(key, request);
    final decrypted = EncryptionUtil.decrypt(key.encryptedKey);
    final limit =
        timeout ?? const Duration(seconds: Constants.upstreamTimeoutSeconds);

    final upstream = await client
        .openUrl(request.method, uri)
        .timeout(const Duration(seconds: 20));
    upstream.followRedirects = false;
    upstream.persistentConnection = true;

    request.headers.forEach((name, value) {
      if (_skipRequestHeaders.contains(name.toLowerCase())) return;
      upstream.headers.set(name, value);
    });
    authHeaders(decrypted).forEach(upstream.headers.set);
    providerHeaders(key).forEach(upstream.headers.set);
    upstream.headers.set('user-agent', 'RelayGo/${Constants.appVersion}');

    upstream.contentLength = request.body.length;
    if (request.body.isNotEmpty) upstream.add(request.body);

    final response = await upstream.close().timeout(limit);

    final headers = <String, String>{};
    response.headers.forEach((name, values) {
      if (_skipResponseHeaders.contains(name.toLowerCase())) return;
      headers[name] = values.join(', ');
    });

    final mime = response.headers.contentType?.mimeType ?? '';
    final isStream = mime.contains('event-stream') ||
        mime.contains('x-ndjson') ||
        request.stream;

    return ProviderResult(
      statusCode: response.statusCode,
      headers: headers,
      body: response,
      streaming: isStream,
    );
  }

  @override
  Future<KeyTestOutcome> test(ApiKey key) async {
    final sw = Stopwatch()..start();
    const connectTimeout = Duration(seconds: 10);
    const readTimeout = Duration(seconds: 12);
    try {
      final uri = buildUri(
        key,
        ProxyRequest(method: 'GET', path: testPath),
      );
      final req = await client.openUrl('GET', uri).timeout(connectTimeout);
      authHeaders(EncryptionUtil.decrypt(key.encryptedKey))
          .forEach(req.headers.set);
      providerHeaders(key).forEach(req.headers.set);
      req.headers.set('user-agent', 'RelayGo/${Constants.appVersion}');
      final resp = await req.close().timeout(readTimeout);
      await resp.drain<void>();
      final elapsed = sw.elapsed;
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return KeyTestOutcome.valid(elapsed);
      }
      return KeyTestOutcome.invalid(resp.statusCode, '', elapsed);
    } on TimeoutException {
      return KeyTestOutcome.timeout();
    } catch (e) {
      // 连接被拒、DNS 失败、证书错误、鉴权头缺字段等
      final msg = e.toString().replaceFirst(RegExp(r'^.*Exception: '), '');
      return KeyTestOutcome.failure(msg);
    }
  }

  /// 拉取该服务商的模型列表（默认 OpenAI 兼容 GET /models）
  ///
  /// 子类可重写以支持非 OpenAI 兼容的响应格式。
  /// 失败时抛出 [ModelSyncException]，由同步服务捕获并汇总到结果。
  @override
  Future<List<ModelInfo>> fetchModels(ApiKey key) async {
    final json = await modelsGet(key, '/models');
    return parseModelsOpenAI(json, key.provider, nowMs());
  }

  /// GET 某路径并解析为 JSON Map；非 2xx 抛 [ModelSyncException]
  Future<Map<String, dynamic>> modelsGet(ApiKey key, String path) async {
    final uri = buildUri(key, ProxyRequest(method: 'GET', path: path));
    final decrypted = EncryptionUtil.decrypt(key.encryptedKey);
    final req = await client.openUrl('GET', uri).timeout(const Duration(seconds: 20));
    authHeaders(decrypted).forEach(req.headers.set);
    providerHeaders(key).forEach(req.headers.set);
    req.headers.set('user-agent', 'RelayGo/${Constants.appVersion}');
    final resp = await req.close().timeout(const Duration(seconds: 25));
    final body = await drainBody(resp);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ModelSyncException(
        provider: key.provider,
        message: 'HTTP ${resp.statusCode}',
        statusCode: resp.statusCode,
      );
    }
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } on FormatException catch (_) {
      throw ModelSyncException(
        provider: key.provider,
        message: '模型列表接口返回格式异常（非 JSON），响应内容：${body.length > 200 ? body.substring(0, 200) : body}',
      );
    }
  }

  static int nowMs() => DateTime.now().millisecondsSinceEpoch;

  static Future<String> drainBody(HttpClientResponse resp) async {
    final bytes = await resp.fold<List<int>>(<int>[], (prev, el) => prev..addAll(el));
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// 解析 OpenAI 风格的 created（秒 → 毫秒 / ISO 字符串 → 毫秒）
  static int? parseCreated(dynamic value) {
    if (value is int) return value * 1000;
    if (value is String) {
      final dt = DateTime.tryParse(value);
      if (dt != null) return dt.millisecondsSinceEpoch;
    }
    return null;
  }

  /// OpenAI 兼容：{data:[{id, owned_by, created}]}
  static List<ModelInfo> parseModelsOpenAI(
      Map<String, dynamic> json, String provider, int now) {
    final data = json['data'];
    if (data is! List) return const [];
    return data.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      final id = (m['id'] as String?) ?? '';
      return ModelInfo.unified(
        provider: provider,
        name: id,
        ownedBy: m['owned_by'] as String?,
        createdAt: parseCreated(m['created']),
        capabilities: ModelInfo.inferCapabilities(id),
        lastSynced: now,
        rawData: m,
      );
    }).toList();
  }

  /// Anthropic：{models:[{id, display_name, created_at}]}
  static List<ModelInfo> parseModelsAnthropic(
      Map<String, dynamic> json, String provider, int now) {
    final models = json['models'];
    if (models is! List) return const [];
    return models.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      final id = (m['id'] as String?) ?? '';
      return ModelInfo.unified(
        provider: provider,
        name: id,
        displayName: m['display_name'] as String? ?? id,
        createdAt: parseCreated(m['created_at']),
        capabilities: ModelInfo.inferCapabilities(id),
        lastSynced: now,
        rawData: m,
      );
    }).toList();
  }

  /// Google：{models:[{name:'models/gemini-pro', ...}]}
  static List<ModelInfo> parseModelsGoogle(
      Map<String, dynamic> json, String provider, int now) {
    final models = json['models'];
    if (models is! List) return const [];
    return models.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      final raw = (m['name'] as String?) ?? '';
      final id = raw.split('/').last; // 去掉 'models/' 前缀
      return ModelInfo.unified(
        provider: provider,
        name: id,
        displayName: m['displayName'] as String? ?? id,
        createdAt: parseCreated(m['createTime']),
        capabilities: ModelInfo.inferCapabilities(id),
        lastSynced: now,
        rawData: m,
      );
    }).toList();
  }
}

/// 供子类复用的 base url 解析（预设 + key 自定义）
String resolvePresetBaseUrl(ProviderType type, ApiKey key) =>
    ProviderConfig.resolveBaseUrl(type, key.baseUrl);
