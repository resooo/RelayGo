/// 标准虚拟模型体系（P0 能力分层）
///
/// 目标：把「客户端请求的能力档位」与「上游具体模型名」解耦。
/// 客户端只看到少量【能力虚拟模型】(virtualId)，例如 `chat-premium`；
/// 上游几十上百个真实模型名通过 [ModelNormalizer] 归一化后归类到这些档位之下，
/// 转发时再把档位改写成该提供商实际支持的模型名（见 proxy_server / model_normalizer）。
///
/// 本文件只做纯配置声明，不含 IO 与状态，可安全地被 proxy_server / 同步服务
/// / 单测共同复用。
library;

/// 能力虚拟模型的元数据
class StandardModel {
  /// 能力虚拟模型 id，如 `chat-premium`（客户端直接请求它）
  final String id;

  /// 分类：chat / embedding / image / audio / rerank
  final String category;

  /// 能力档位：basic / standard / advanced / premium
  final String capability;

  /// 典型上下文窗口（用于划分大小档，展示用，非硬约束）
  final int contextWindow;

  /// 能力标记集（vision / function_calling / audio / ...）
  final List<String> features;

  const StandardModel({
    required this.id,
    required this.category,
    required this.capability,
    required this.contextWindow,
    this.features = const [],
  });

  /// 用户可读的展示名，如「对话 · 高级」；用于 /v1/models 收敛后展示
  String get displayName {
    final capName = <String, String>{
      'basic': '基础',
      'standard': '标准',
      'advanced': '高级',
      'premium': '旗舰',
    }[capability] ?? capability;
    final catName = <String, String>{
      'chat': '对话',
      'embedding': '向量',
      'image': '图像',
      'audio': '音频',
      'rerank': '重排',
    }[category] ?? category;
    return '$catName · $capName';
  }
}

/// 标准虚拟模型注册表（运行期只读配置）
class StandardModelRegistry {
  StandardModelRegistry._();

  /// 内置 6 分类、10 档能力虚拟模型。
  ///
  /// 逻辑：对话(4 档) + 向量 + 图像 + 音频转写 + 音频合成 + 重排。
  /// 客户端拉取 /v1/models 时默认只看到这 10 条，而非上游上百条真实模型。
  static const List<StandardModel> all = [
    StandardModel(
        id: 'chat-basic',
        category: 'chat',
        capability: 'basic',
        contextWindow: 8192,
        features: ['chat', 'function_calling']),
    StandardModel(
        id: 'chat-standard',
        category: 'chat',
        capability: 'standard',
        contextWindow: 32768,
        features: ['chat', 'function_calling']),
    StandardModel(
        id: 'chat-advanced',
        category: 'chat',
        capability: 'advanced',
        contextWindow: 128000,
        features: ['chat', 'function_calling', 'vision']),
    StandardModel(
        id: 'chat-premium',
        category: 'chat',
        capability: 'premium',
        contextWindow: 200000,
        features: ['chat', 'function_calling', 'vision', 'audio']),
    StandardModel(
        id: 'embedding',
        category: 'embedding',
        capability: 'standard',
        contextWindow: 8192,
        features: ['embedding']),
    StandardModel(
        id: 'image',
        category: 'image',
        capability: 'standard',
        contextWindow: 0,
        features: ['image_generation']),
    StandardModel(
        id: 'audio-transcribe',
        category: 'audio',
        capability: 'standard',
        contextWindow: 0,
        features: ['audio_transcription']),
    StandardModel(
        id: 'audio-tts',
        category: 'audio',
        capability: 'standard',
        contextWindow: 0,
        features: ['text_to_speech']),
    StandardModel(
        id: 'rerank',
        category: 'rerank',
        capability: 'standard',
        contextWindow: 8192,
        features: ['rerank']),
    StandardModel(
        id: 'moderation',
        category: 'moderation',
        capability: 'standard',
        contextWindow: 8192,
        features: ['moderation']),
  ];

  /// id → StandardModel 的快速索引
  static final Map<String, StandardModel> byId = {
    for (final m in all) m.id: m,
  };

  /// 是否是一个标准虚拟模型 id
  static bool isVirtualId(String id) => byId.containsKey(id);

  /// 品牌名 / 别名 → virtualId。
  ///
  /// 用途 1：客户端直接写品牌名（`gpt-4o`、`claude-opus`）也能解析到档位；
  /// 用途 2：归一化时把「已知真实模型名的 canonical」收敛到档位。
  static const Map<String, String> aliases = {
    // ——— 开放语义别名 ———
    'fast': 'chat-basic',
    'light': 'chat-basic',
    'smart': 'chat-advanced',
    'advanced': 'chat-advanced',
    'best': 'chat-premium',
    'premium': 'chat-premium',
    'pro': 'chat-premium',
    'max': 'chat-premium',
    'gpt4': 'chat-premium',
    'claude3': 'chat-advanced',
    'gemini': 'chat-advanced',
    // ——— OpenAI 系 ———
    'gpt-3.5-turbo': 'chat-basic',
    'gpt-3.5-turbo-16k': 'chat-basic',
    'gpt-4o-mini': 'chat-basic',
    'gpt-4-plus-mini': 'chat-basic',
    'gpt-4': 'chat-advanced',
    'gpt-4-turbo': 'chat-advanced',
    'gpt-4-32k': 'chat-advanced',
    'gpt-4o-2024-05-13': 'chat-premium',
    'gpt-4o': 'chat-premium',
    'gpt-4o1': 'chat-premium',
    'gpt-4.1': 'chat-premium',
    'gpt-5': 'chat-premium',
    'o1': 'chat-premium',
    'o1-mini': 'chat-standard',
    'o3': 'chat-premium',
    'o3-mini': 'chat-standard',
    'o4-mini': 'chat-standard',
    'gpt-vision': 'chat-premium',
    'text-embedding-3-small': 'embedding',
    'text-embedding-3-large': 'embedding',
    'text-embedding-ada-002': 'embedding',
    'dall-e-2': 'image',
    'dall-e-3': 'image',
    'gpt-image-1': 'image',
    'whisper-1': 'audio-transcribe',
    'gpt-4o-audio-preview': 'audio-tts',
    'tts-1': 'audio-tts',
    'tts-1-hd': 'audio-tts',
    'text-moderation-latest': 'moderation',
    'text-moderation-stable': 'moderation',
    // ——— Anthropic 系（去掉日期后缀后的 canonical） ———
    'claude-3-opus': 'chat-premium',
    'claude-3-5-sonnet': 'chat-advanced',
    'claude-3-5-haiku': 'chat-standard',
    'claude-3-sonnet': 'chat-advanced',
    'claude-3-haiku': 'chat-basic',
    'claude-4-opus': 'chat-premium',
    'claude-4-sonnet': 'chat-premium',
    'claude-3-7-sonnet': 'chat-advanced',
    'claude-3-6-sonnet': 'chat-advanced',
    // ——— Google Gemini 系（去掉前缀后的 canonical） ———
    'gemini-1.5-flash': 'chat-basic',
    'gemini-1.5-flash-8b': 'chat-basic',
    'gemini-2.0-flash': 'chat-standard',
    'gemini-1.5-pro': 'chat-advanced',
    'gemini-2.0-pro': 'chat-premium',
    'gemini-2.5-pro': 'chat-premium',
    'gemini-2.5-flash': 'chat-standard',
    'gemini-pro-vision': 'chat-premium',
    'gemini-embedding-001': 'embedding',
    'imagen-2.0': 'image',
    'imagen-3.0': 'image',
    // ——— 开源 / 国产（canonical） ———
    'deepseek-chat': 'chat-basic',
    'deepseek-coder': 'chat-basic',
    'deepseek-reasoner': 'chat-advanced',
    'qwen-turbo': 'chat-basic',
    'qwen-plus': 'chat-basic',
    'qwen-max': 'chat-advanced',
    'qwen-vl-plus': 'chat-advanced',
    'qwen2-7b': 'chat-basic',
    'qwen2-72b': 'chat-standard',
    'llama-3-8b': 'chat-basic',
    'llama-3-70b': 'chat-standard',
    'llama-3.1-8b': 'chat-basic',
    'llama-3.1-70b': 'chat-standard',
    'llama-3.1-405b': 'chat-premium',
    'mistral-small': 'chat-basic',
    'mistral-medium': 'chat-standard',
    'mistral-large': 'chat-advanced',
    'glm-4': 'chat-advanced',
    'glm-4v': 'chat-advanced',
    'glm-4-flash': 'chat-basic',
    'moonshot-v1-8k': 'chat-basic',
    'moonshot-v1-32k': 'chat-standard',
    'moonshot-v1-128k': 'chat-advanced',
    'minimax-01': 'chat-premium',
    'ernie-4.0': 'chat-premium',
    'doubao-pro': 'chat-premium',
  };

  /// virtualId → 各提供商的【典型】真实模型名。
  ///
  /// 仅用于把 virtualId 泛化为「该提供商最贴近该档位的模型」做兜底；
  /// 实际转发时优先用本地已同步目录里「该 provider 存在且 virtualId 命中」的真实模型，
  /// 以避免写了上级未提供的模型名导致 404（见 ModelResolver.resolveVirtual）。
  static const Map<String, List<Map<String, String>>> virtualTypical = {
    'chat-basic': [
      {'provider': 'openai', 'model': 'gpt-4o-mini'},
      {'provider': 'anthropic', 'model': 'claude-3-haiku-20240307'},
      {'provider': 'google', 'model': 'gemini-2.0-flash'},
    ],
    'chat-standard': [
      {'provider': 'openai', 'model': 'gpt-4o-mini'},
      {'provider': 'anthropic', 'model': 'claude-3-5-haiku-20241022'},
      {'provider': 'google', 'model': 'gemini-2.5-flash'},
    ],
    'chat-advanced': [
      {'provider': 'openai', 'model': 'gpt-4-turbo'},
      {'provider': 'anthropic', 'model': 'claude-3-5-sonnet-20241022'},
      {'provider': 'google', 'model': 'gemini-1.5-pro'},
    ],
    'chat-premium': [
      {'provider': 'openai', 'model': 'gpt-4o'},
      {'provider': 'anthropic', 'model': 'claude-3-5-sonnet-20241022'},
      {'provider': 'google', 'model': 'gemini-2.5-pro'},
    ],
    'embedding': [
      {'provider': 'openai', 'model': 'text-embedding-3-small'},
      {'provider': 'google', 'model': 'gemini-embedding-001'},
    ],
    'image': [
      {'provider': 'openai', 'model': 'dall-e-3'},
      {'provider': 'google', 'model': 'imagen-3.0'},
    ],
    'audio-transcribe': [
      {'provider': 'openai', 'model': 'whisper-1'},
    ],
    'audio-tts': [
      {'provider': 'openai', 'model': 'tts-1'},
    ],
  };
}