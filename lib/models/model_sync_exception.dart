/// 模型同步异常（[BaseHttpProvider.fetchModels] 抛出，UI 层据此给出友好提示）
class ModelSyncException implements Exception {
  final String provider;
  final String message;
  final int? statusCode;

  ModelSyncException({
    required this.provider,
    required this.message,
    this.statusCode,
  });

  @override
  String toString() => 'ModelSyncException($provider): $message';

  /// 将异常转换为对用户友好的中文提示
  static String friendly(Object error) {
    if (error is ModelSyncException) {
      switch (error.statusCode) {
        case 401:
          return 'API Key 无效或已过期';
        case 403:
          return '没有权限访问模型列表';
        case 404:
          return '模型列表接口不存在（请检查 base_url）';
        case 429:
          return '请求过于频繁，请稍后重试';
        case 500:
        case 502:
        case 503:
          return '服务商服务器错误';
        default:
          return error.message;
      }
    }
    final msg = error.toString();
    if (msg.contains('timed out') || msg.contains('TimeoutException')) {
      return '连接超时，请检查网络或 base_url';
    }
    return '未知错误：$msg';
  }
}
