/// 输入校验工具
class Validators {
  /// API Key 基本格式校验（宽松：非空且长度 >= 8）
  static String? validateApiKey(String? value) {
    if (value == null || value.trim().isEmpty) return 'API Key 不能为空';
    if (value.trim().length < 8) return 'API Key 长度过短';
    return null;
  }

  /// 端口校验（1-65535）
  static String? validatePort(String? value) {
    if (value == null || value.trim().isEmpty) return '端口不能为空';
    final port = int.tryParse(value.trim());
    if (port == null) return '端口必须是数字';
    if (port < 1 || port > 65535) return '端口范围 1-65535';
    return null;
  }

  /// URL 校验（可为空，因为部分提供商有默认值）
  static String? validateUrl(String? value, {bool required = false}) {
    if (value == null || value.trim().isEmpty) {
      return required ? '自定义端点不能为空' : null;
    }
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasAbsolutePath && !uri.hasAuthority) {
      return 'URL 格式不正确';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'URL 必须以 http/https 开头';
    }
    return null;
  }

  /// 权重 / 优先级（正整数）
  static String? validatePositiveInt(String? value, String label) {
    if (value == null || value.trim().isEmpty) return '$label 不能为空';
    final n = int.tryParse(value.trim());
    if (n == null || n <= 0) return '$label 必须为正整数';
    return null;
  }
}
