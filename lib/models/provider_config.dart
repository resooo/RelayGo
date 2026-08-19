/// 支持的 AI 服务提供商类型
enum ProviderType { openai, anthropic, google, azure, custom }

extension ProviderTypeX on ProviderType {
  String get name => toString().split('.').last;

  static ProviderType fromString(String value) {
    switch (value) {
      case 'openai':
        return ProviderType.openai;
      case 'anthropic':
        return ProviderType.anthropic;
      case 'google':
        return ProviderType.google;
      case 'azure':
        return ProviderType.azure;
      case 'custom':
      default:
        return ProviderType.custom;
    }
  }

  /// 是否要求用户必须填写自定义 base_url
  bool get requiresBaseUrl =>
      this == ProviderType.azure || this == ProviderType.custom;

  String get displayName {
    switch (this) {
      case ProviderType.openai:
        return 'OpenAI';
      case ProviderType.anthropic:
        return 'Anthropic';
      case ProviderType.google:
        return 'Google AI';
      case ProviderType.azure:
        return 'Azure OpenAI';
      case ProviderType.custom:
        return '自定义';
    }
  }
}

/// 提供商的静态配置（默认端点等）
class ProviderConfig {
  final ProviderType type;
  final String? defaultBaseUrl;

  const ProviderConfig(this.type, this.defaultBaseUrl);

  static const Map<ProviderType, ProviderConfig> presets = {
    ProviderType.openai: ProviderConfig(ProviderType.openai, 'https://api.openai.com/v1'),
    ProviderType.anthropic:
        ProviderConfig(ProviderType.anthropic, 'https://api.anthropic.com'),
    ProviderType.google: ProviderConfig(
        ProviderType.google, 'https://generativelanguage.googleapis.com'),
    ProviderType.azure: ProviderConfig(ProviderType.azure, null),
    ProviderType.custom: ProviderConfig(ProviderType.custom, null),
  };

  /// 解析最终使用的 base url：优先使用 key 自带，否则回退到预设
  static String resolveBaseUrl(ProviderType type, String? keyBaseUrl) {
    if (keyBaseUrl != null && keyBaseUrl.trim().isNotEmpty) return keyBaseUrl.trim();
    return presets[type]?.defaultBaseUrl ?? '';
  }
}
