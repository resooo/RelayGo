/// 免费 API 提供商数据模型（Free LLM API Hub providers.json）
///
/// 解析 `https://raw.githubusercontent.com/pacocartones/free-llm-api-hub/v2.9.0/data/providers.json`
/// 中 `providers` 数组的每一项，并提供中文化展示辅助方法。
class FreeProvider {
  final String slug;
  final String name;
  final String category; // ongoing / trial
  final String freeType; // renewing-quota / trial-credit / perpetual / recurring-credit
  final String? freeTier; // 保留原文
  final String? rateLimits; // 保留原文
  final String? notes; // 保留原文
  final String? bestFor; // 保留原文
  final List<String> modalities;
  final List<String>? modelsFree;
  final String? expires;
  final String? docsUrl;
  final bool? phoneRequired;
  final bool? cardRequired;
  final bool? commercialOk;
  final bool? openaiCompatible;
  final String? openaiBaseUrl;
  final String? envKey;
  final bool verified;
  final String? lastVerified;

  const FreeProvider({
    required this.slug,
    required this.name,
    required this.category,
    required this.freeType,
    this.freeTier,
    this.rateLimits,
    this.notes,
    this.bestFor,
    this.modalities = const [],
    this.modelsFree,
    this.expires,
    this.docsUrl,
    this.phoneRequired,
    this.cardRequired,
    this.commercialOk,
    this.openaiCompatible,
    this.openaiBaseUrl,
    this.envKey,
    this.verified = false,
    this.lastVerified,
  });

  factory FreeProvider.fromJson(Map<String, dynamic> json) {
    return FreeProvider(
      slug: json['slug'] as String? ?? '',
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      freeType: json['free_type'] as String? ?? '',
      freeTier: json['free_tier'] as String?,
      rateLimits: json['rate_limits'] as String?,
      notes: json['notes'] as String?,
      bestFor: json['best_for'] as String?,
      modalities: (json['modalities'] as List?)
              ?.whereType<String>()
              .toList() ??
          const [],
      modelsFree:
          (json['models_free'] as List?)?.whereType<String>().toList(),
      expires: json['expires'] as String?,
      docsUrl: json['docs_url'] as String?,
      phoneRequired: json['phone_required'] as bool?,
      cardRequired: json['card_required'] as bool?,
      commercialOk: json['commercial_ok'] as bool?,
      openaiCompatible: json['openai_compatible'] as bool?,
      openaiBaseUrl: json['openai_base_url'] as String?,
      envKey: json['env_key'] as String?,
      verified: json['verified'] as bool? ?? false,
      lastVerified: json['last_verified'] as String?,
    );
  }

  // —— 中文化映射 ——

  /// category 字段
  String get categoryLabel {
    switch (category) {
      case 'ongoing':
        return '持续免费';
      case 'trial':
        return '试用额度';
      default:
        return category.isEmpty ? '未分类' : category;
    }
  }

  /// free_type 字段
  String get freeTypeLabel {
    switch (freeType) {
      case 'renewing-quota':
        return '周期性刷新配额';
      case 'trial-credit':
        return '一次性试用额度';
      case 'perpetual':
        return '永久免费';
      case 'recurring-credit':
        return '每月循环信用额';
      default:
        return freeType.isEmpty ? '未说明' : freeType;
    }
  }

  /// modalities 数组 → 中文标签
  String get modalitiesLabel {
    if (modalities.isEmpty) return '未指定';
    const map = {
      'text': '文本',
      'audio': '音频/语音',
      'image': '图像生成',
      'vision': '视觉/多模态',
      'embeddings': '嵌入向量',
      'ocr': 'OCR/文档解析',
      'rerank': '重排序',
    };
    return modalities.map((m) => map[m] ?? m).join('、');
  }

  /// 模型列表 → 展示文本
  String get modelsLabel {
    final list = modelsFree;
    if (list == null || list.isEmpty) return '未列出具体模型';
    return list.join('、');
  }

  /// 布尔值 → 中文
  static String boolLabel(bool? v) {
    if (v == null) return '未说明';
    return v ? '是' : '否';
  }

  /// 已验证 → 中文
  String get verifiedLabel => verified ? '已核实' : '待核实';

  /// 过期时间
  String get expiresLabel {
    final e = expires;
    return (e == null || e.isEmpty) ? '无过期时间' : e;
  }

  // —— 国家 / 地区（用于展示国旗图标）——

  /// 提供商所在国家/地区代码（ISO 3166-1 alpha-2），未知为空串
  String get countryCode => _countryBySlug[slug] ?? '';

  /// 国旗 Emoji（未知返回 🌐 地球图标）
  String get flagEmoji {
    final code = countryCode;
    if (code.length != 2) return '🌐';
    final first = code.codeUnitAt(0) - 0x41 + 0x1F1E6;
    final second = code.codeUnitAt(1) - 0x41 + 0x1F1E6;
    return String.fromCharCodes([first, second]);
  }

  /// 提供商 slug → 国家/地区代码映射（依据各公司总部所在地）
  static const Map<String, String> _countryBySlug = {
    'google-gemini': 'US',
    'groq': 'US',
    'openrouter': 'US',
    'cloudflare-workers-ai': 'US',
    'cohere': 'CA',
    'cerebras': 'US',
    'mistral': 'FR',
    'huggingface': 'US',
    'siliconflow': 'CN',
    'zai-glm': 'CN',
    'ibm-watsonx': 'US',
    'ovhcloud-ai-endpoints': 'FR',
    'fireworks-ai': 'US',
    'baseten': 'US',
    'nebius': 'NL',
    'novita': 'SG',
    'ai21': 'IL',
    'nlpcloud': 'FR',
    'alibaba-model-studio': 'CN',
    'modal': 'US',
    'sambanova': 'US',
    'scaleway': 'FR',
    'nvidia-nim': 'US',
    'vercel-ai-gateway': 'US',
    'jina-ai': 'DE',
    'deepgram': 'US',
    'assemblyai': 'US',
    'mixedbread': 'DE',
    'clarifai': 'US',
    'arli-ai': 'US',
    'ollama-cloud': 'US',
    'ai-horde': '', // 社区分布式项目，无固定国家
    'modelscope': 'CN',
    'pollinations': 'DE',
    'runware': 'US',
    'pinecone-inference': 'US',
    'twelve-labs': 'US',
    'ocr-space': 'US',
    'llamaparse': 'US',
    'nanonets': 'US',
    'moondream': 'US',
    'speechmatics': 'GB',
    'speechify': 'US',
    'hume-ai': 'US',
    'unreal-speech': 'US',
    'elevenlabs': 'US',
    'sarvam-ai': 'IN',
    'gladia': 'FR',
    'rime': 'US',
    'tencent-hunyuan': 'CN',
    'voyage-ai': 'US',
    'contextual-ai': 'US',
    'cartesia': 'US',
    'lmnt': 'US',
    'fish-audio': 'CN',
    'camb-ai': 'AE',
    'rev-ai': 'US',
    'unstructured': 'US',
    'nutrient': 'US',
    'photoroom': 'FR',
    'poolside': 'FR',
    'upstage': 'KR',
    'veryfi': 'US',
    'voicegain': 'US',
    'smallest-ai': 'IN',
    'retell-ai': 'US',
    'datalab': 'US',
    'wandb-inference': 'US',
    'typhoon': 'TH',
  };
}

/// 免费 API 数据集（providers.json 顶层结构）
class FreeApiDataset {
  final String version;
  final String generated;
  final String source;
  final String? note;
  final List<FreeProvider> providers;

  const FreeApiDataset({
    required this.version,
    required this.generated,
    required this.source,
    this.note,
    this.providers = const [],
  });

  factory FreeApiDataset.fromJson(Map<String, dynamic> json) {
    return FreeApiDataset(
      version: json['version'] as String? ?? '',
      generated: json['generated'] as String? ?? '',
      source: json['source'] as String? ?? '',
      note: json['note'] as String?,
      providers: (json['providers'] as List?)
              ?.whereType<Map>()
              .map((m) => FreeProvider.fromJson(Map<String, dynamic>.from(m)))
              .toList() ??
          const [],
    );
  }
}
