/// 各 AI 服务提供商默认端点与请求归属识别
class Environment {
  // 默认 Base URL
  static const Map<String, String> providerBaseUrls = {
    'openai': 'https://api.openai.com/v1',
    'anthropic': 'https://api.anthropic.com',
    'google': 'https://generativelanguage.googleapis.com',
    'azure': '', // 由用户在 key.baseUrl 中指定（含部署名）
    'custom': '', // 由用户在 key.baseUrl 中指定
  };

  // 接口路径 -> 提供商类型（用于自动识别请求归属，需求 2.1.4 接口映射）
  static const Map<String, String> pathToProvider = {
    '/v1/chat/completions': 'openai',
    '/v1/completions': 'openai',
    '/v1/embeddings': 'openai',
    '/v1/images/generations': 'openai',
    '/v1/audio/transcriptions': 'openai',
    '/v1/audio/speech': 'openai',
    '/v1/models': 'openai',
    '/v1/messages': 'anthropic',
    '/v1beta': 'google',
    '/openai/deployments': 'azure',
  };

  /// 模型名前缀 -> 提供商（用于按模型名智能路由）
  static const Map<String, String> modelPrefixToProvider = {
    'gpt-': 'openai',
    'o1': 'openai',
    'o3': 'openai',
    'o4': 'openai',
    'chatgpt': 'openai',
    'text-embedding': 'openai',
    'dall-e': 'openai',
    'whisper': 'openai',
    'tts-': 'openai',
    'claude': 'anthropic',
    'gemini': 'google',
    'palm': 'google',
    'chat-bison': 'google',
    'text-bison': 'google',
    'embedding-00': 'google',
  };

  /// 仅按请求路径识别（不看模型名）
  static String detectProviderByPath(String path) {
    if (path.startsWith('/v1/messages')) return 'anthropic';
    if (path.startsWith('/v1beta') || path.contains(':generateContent')) {
      return 'google';
    }
    if (path.startsWith('/openai/deployments')) return 'azure';
    // 其余 OpenAI 兼容接口（chat/completions/embeddings/images/audio...）
    return 'openai';
  }

  /// 按模型名识别，识别不出返回 null
  static String? detectProviderByModel(String? model) {
    if (model == null || model.isEmpty) return null;
    final m = model.toLowerCase();
    for (final entry in modelPrefixToProvider.entries) {
      if (m.startsWith(entry.key)) return entry.value;
    }
    return null;
  }

  /// 综合识别：请求头 > 模型名 > 请求路径
  ///
  /// [headerProvider] 来自 `x-relay-provider`，可让客户端强制指定；
  /// [model] 来自请求体的 `model` 字段。
  static String detectProvider(
    String path, {
    String? model,
    String? headerProvider,
  }) {
    if (headerProvider != null && headerProvider.trim().isNotEmpty) {
      final p = headerProvider.trim().toLowerCase();
      if (providerBaseUrls.containsKey(p)) return p;
    }
    final byPath = detectProviderByPath(path);
    // 路径已明确指向某家专有协议时（Anthropic/Google/Azure），不再被模型名覆盖
    if (byPath != 'openai') return byPath;
    return detectProviderByModel(model) ?? byPath;
  }

  /// 候选提供商列表：主选 + OpenAI 兼容降级
  ///
  /// 当主选提供商没有可用 key 时，OpenAI 风格接口可回落到「自定义（OpenAI 兼容）」，
  /// 反之自定义 key 也能接住 OpenAI 请求，实现多提供商自动切换（需求 10.1）。
  static List<String> candidateProviders(String primary, String path) {
    final list = <String>[primary];
    final openAiStyle = !path.startsWith('/v1/messages') &&
        !path.startsWith('/v1beta') &&
        !path.contains(':generateContent');
    if (openAiStyle) {
      if (primary != 'custom') list.add('custom');
      if (primary != 'openai') list.add('openai');
      if (primary != 'azure') list.add('azure');
    }
    return list;
  }

  /// 接口能力归类（便于日志/统计展示）
  static String endpointKind(String path) {
    if (path.contains('/chat/completions') || path.contains('/messages')) {
      return 'chat';
    }
    if (path.contains('/embeddings') || path.contains(':embedContent')) {
      return 'embedding';
    }
    if (path.contains('/images/')) return 'image';
    if (path.contains('/audio/transcriptions')) return 'audio';
    if (path.contains('/audio/speech')) return 'tts';
    if (path.contains('/completions')) return 'completion';
    if (path.contains(':generateContent') ||
        path.contains(':streamGenerateContent')) {
      return 'chat';
    }
    return 'other';
  }
}
