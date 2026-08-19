/// 请求日志记录（需求 2.2.1）
class RequestLog {
  final String id;
  final int timestamp; // 毫秒
  final String method;
  final String path;
  final String provider; // 目标提供商
  final String keyId; // 使用的 key id（便于按 key 聚合）
  final String keyName; // key 名称
  final String keyMasked; // 使用的 key（脱敏，永不含明文）
  final String model; // 请求的模型名（客户端原始请求）
  final String actualModel; // 实际转发到上游的模型名（虚拟模型改写后；未改写时为空）
  final int statusCode; // 0 表示代理层错误（未到达上游）
  final int durationMs;
  final int promptTokens;
  final int completionTokens;
  final int requestBytes;
  final int responseBytes;
  final bool streaming; // 是否 SSE 流式响应
  final int retries; // 本次请求切换 key 的次数
  final String? ruleName; // 命中的路由规则
  final String? error;

  // —— Phase 3 ——
  final bool cached; // 命中响应缓存（需求 2.2.4）
  final String rateLimited; // 触发的限流维度，空串表示未触发（需求 2.2.6）

  RequestLog({
    required this.id,
    required this.timestamp,
    required this.method,
    required this.path,
    required this.provider,
    required this.keyMasked,
    required this.statusCode,
    required this.durationMs,
    this.keyId = '',
    this.keyName = '',
    this.model = '',
    this.actualModel = '',
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.requestBytes = 0,
    this.responseBytes = 0,
    this.streaming = false,
    this.retries = 0,
    this.ruleName,
    this.error,
    this.cached = false,
    this.rateLimited = '',
  });

  factory RequestLog.fromJson(Map<String, dynamic> json) {
    return RequestLog(
      id: json['id'] as String,
      timestamp: json['timestamp'] as int? ?? 0,
      method: json['method'] as String? ?? '',
      path: json['path'] as String? ?? '',
      provider: json['provider'] as String? ?? '',
      keyId: json['key_id'] as String? ?? '',
      keyName: json['key_name'] as String? ?? '',
      keyMasked: json['key_masked'] as String? ?? '',
      model: json['model'] as String? ?? '',
      actualModel: json['actual_model'] as String? ?? '',
      statusCode: json['status_code'] as int? ?? 0,
      durationMs: json['duration_ms'] as int? ?? 0,
      promptTokens: json['prompt_tokens'] as int? ?? 0,
      completionTokens: json['completion_tokens'] as int? ?? 0,
      requestBytes: json['request_bytes'] as int? ?? 0,
      responseBytes: json['response_bytes'] as int? ?? 0,
      streaming: json['streaming'] as bool? ?? false,
      retries: json['retries'] as int? ?? 0,
      ruleName: json['rule_name'] as String?,
      error: json['error'] as String?,
      cached: json['cached'] as bool? ?? false,
      rateLimited: json['rate_limited'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp,
      'method': method,
      'path': path,
      'provider': provider,
      'key_id': keyId,
      'key_name': keyName,
      'key_masked': keyMasked,
      'model': model,
      'actual_model': actualModel,
      'status_code': statusCode,
      'duration_ms': durationMs,
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
      'request_bytes': requestBytes,
      'response_bytes': responseBytes,
      'streaming': streaming,
      'retries': retries,
      'rule_name': ruleName,
      'error': error,
      'cached': cached,
      'rate_limited': rateLimited,
    };
  }

  bool get isError => statusCode < 200 || statusCode >= 400;

  int get totalTokens => promptTokens + completionTokens;

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp);

  /// CSV 表头（与 [toCsvRow] 一一对应）
  static const List<String> csvHeader = [
    'id',
    'timestamp',
    'datetime',
    'method',
    'path',
    'provider',
    'key_name',
    'key_masked',
    'model',
    'actual_model',
    'status_code',
    'duration_ms',
    'prompt_tokens',
    'completion_tokens',
    'total_tokens',
    'request_bytes',
    'response_bytes',
    'streaming',
    'retries',
    'rule_name',
    'cached',
    'rate_limited',
    'error',
  ];

  List<String> toCsvRow() {
    return [
      id,
      '$timestamp',
      dateTime.toIso8601String(),
      method,
      path,
      provider,
      keyName,
      keyMasked,
      model,
      actualModel,
      '$statusCode',
      '$durationMs',
      '$promptTokens',
      '$completionTokens',
      '$totalTokens',
      '$requestBytes',
      '$responseBytes',
      streaming ? 'true' : 'false',
      '$retries',
      ruleName ?? '',
      cached ? 'true' : 'false',
      rateLimited,
      error ?? '',
    ];
  }
}
