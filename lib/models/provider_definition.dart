import 'dart:convert';

/// 提供商定义（用户手动添加 + 内置预设）
///
/// 每个提供商定义包含名称、API URL、API 路径等配置。
/// 内置预设无法删除，但用户可以修改其 API URL 和路径。
class ProviderDefinition {
  final String id;
  String name;
  String apiUrl; // 例如 https://api.openai.com/v1
  String apiPath; // 例如 /chat/completions（默认）
  String modelListPath; // 模型列表路径，例如 /models
  String authType; // 'bearer' | 'api-key' | 'header'
  bool builtIn;
  int createdAt;
  Map<String, String> extraHeaders;

  ProviderDefinition({
    required this.id,
    required this.name,
    required this.apiUrl,
    this.apiPath = '/chat/completions',
    this.modelListPath = '/models',
    this.authType = 'bearer',
    this.builtIn = false,
    int? createdAt,
    Map<String, String>? extraHeaders,
  })  : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        extraHeaders = extraHeaders ?? const {};

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'api_url': apiUrl,
        'api_path': apiPath,
        'model_list_path': modelListPath,
        'auth_type': authType,
        'built_in': builtIn,
        'created_at': createdAt,
        'extra_headers': extraHeaders,
      };

  factory ProviderDefinition.fromJson(Map<String, dynamic> json) =>
      ProviderDefinition(
        id: json['id'] as String,
        name: json['name'] as String,
        apiUrl: json['api_url'] as String,
        apiPath: json['api_path'] as String? ?? '/chat/completions',
        modelListPath: json['model_list_path'] as String? ?? '/models',
        authType: json['auth_type'] as String? ?? 'bearer',
        builtIn: json['built_in'] as bool? ?? false,
        createdAt: json['created_at'] as int?,
        extraHeaders: _parseExtraHeaders(json['extra_headers']),
      );

  /// 兼容两种存储形态的 extra_headers：
  /// - 旧版：JSON 字符串（如 '{"X-Key":"v"}'）
  /// - 新版：直接存 Map（toJson 当前输出）
  static Map<String, String> _parseExtraHeaders(dynamic v) {
    if (v == null) return const {};
    if (v is Map) {
      return Map<String, String>.from(v);
    }
    if (v is String && v.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(v);
        if (decoded is Map) return Map<String, String>.from(decoded);
      } catch (_) {
        // 非法 JSON 字符串，忽略
      }
    }
    return const {};
  }
}

/// 内置提供商预设列表
///
/// 参考 RikkaHub 的提供商列表，覆盖市面上主流的 AI API 服务商。
class BuiltInProviders {
  static const List<Map<String, String>> presets = [
    // —— 国际主流 ——
    {
      'id': 'openai',
      'name': 'OpenAI',
      'api_url': 'https://api.openai.com/v1',
      'api_path': '/chat/completions',
      'model_list_path': '/models',
      'auth_type': 'bearer',
    },
    {
      'id': 'anthropic',
      'name': 'Anthropic',
      'api_url': 'https://api.anthropic.com',
      'api_path': '/v1/messages',
      'model_list_path': '/v1/models',
      'auth_type': 'bearer',
    },
    {
      'id': 'google',
      'name': 'Google AI',
      'api_url': 'https://generativelanguage.googleapis.com',
      'api_path': '/v1beta/models',
      'model_list_path': '/v1beta/models',
      'auth_type': 'api-key',
    },
    {
      'id': 'xai',
      'name': 'xAI (Grok)',
      'api_url': 'https://api.x.ai/v1',
      'api_path': '/chat/completions',
      'model_list_path': '/models',
      'auth_type': 'bearer',
    },
    {
      'id': 'perplexity',
      'name': 'Perplexity',
      'api_url': 'https://api.perplexity.ai',
      'api_path': '/chat/completions',
      'model_list_path': '/models',
      'auth_type': 'bearer',
    },
    {
      'id': 'together',
      'name': 'Together AI',
      'api_url': 'https://api.together.xyz/v1',
      'api_path': '/chat/completions',
      'model_list_path': '/models',
      'auth_type': 'bearer',
    },
    {
      'id': 'openrouter',
      'name': 'OpenRouter',
      'api_url': 'https://openrouter.ai/api/v1',
      'api_path': '/chat/completions',
      'model_list_path': '/models',
      'auth_type': 'bearer',
    },
    {
      'id': 'mistral',
      'name': 'Mistral AI',
      'api_url': 'https://api.mistral.ai/v1',
      'api_path': '/chat/completions',
      'model_list_path': '/models',
      'auth_type': 'bearer',
    },
    {
      'id': 'cohere',
      'name': 'Cohere',
      'api_url': 'https://api.cohere.ai/v1',
      'api_path': '/chat/completions',
      'model_list_path': '/models',
      'auth_type': 'bearer',
    },
    {
      'id': 'groq',
      'name': 'Groq',
      'api_url': 'https://api.groq.com/openai/v1',
      'api_path': '/chat/completions',
      'model_list_path': '/models',
      'auth_type': 'bearer',
    },
    // —— 国产 ——
    {
      'id': 'deepseek',
      'name': 'DeepSeek',
      'api_url': 'https://api.deepseek.com',
      'api_path': '/chat/completions',
      'model_list_path': '/models',
      'auth_type': 'bearer',
    },
    {
      'id': 'moonshot',
      'name': 'Moonshot (月之暗面)',
      'api_url': 'https://api.moonshot.cn/v1',
      'api_path': '/chat/completions',
      'model_list_path': '/models',
      'auth_type': 'bearer',
    },
    {
      'id': 'zhipu',
      'name': '智谱 AI (Zhipu)',
      'api_url': 'https://open.bigmodel.cn/api/paas/v4',
      'api_path': '/chat/completions',
      'model_list_path': '/models',
      'auth_type': 'bearer',
    },
    {
      'id': 'qwen',
      'name': '阿里云百炼 (Qwen)',
      'api_url': 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      'api_path': '/chat/completions',
      'model_list_path': '/models',
      'auth_type': 'bearer',
    },
    {
      'id': 'baidu',
      'name': '百度千帆',
      'api_url': 'https://aip.baidubce.com',
      'api_path': '/chat/completions',
      'model_list_path': '/models',
      'auth_type': 'bearer',
    },
    {
      'id': 'hunyuan',
      'name': '腾讯云混元 (Hunyuan)',
      'api_url': 'https://api.hunyuan.cloud.tencent.com/v1',
      'api_path': '/chat/completions',
      'model_list_path': '/models',
      'auth_type': 'bearer',
    },
    {
      'id': 'xfyun',
      'name': '讯飞星火 (Spark)',
      'api_url': 'https://spark-api-open.xf-yun.com/v1',
      'api_path': '/chat/completions',
      'model_list_path': '/models',
      'auth_type': 'bearer',
    },
    {
      'id': 'doubao',
      'name': '火山引擎 (豆包)',
      'api_url': 'https://ark.cn-beijing.volces.com/api/v3',
      'api_path': '/chat/completions',
      'model_list_path': '/models',
      'auth_type': 'bearer',
    },
    {
      'id': 'stepfun',
      'name': '阶跃星辰 (StepFun)',
      'api_url': 'https://api.stepfun.com/v1',
      'api_path': '/chat/completions',
      'model_list_path': '/models',
      'auth_type': 'bearer',
    },
    {
      'id': 'minimax',
      'name': 'MiniMax',
      'api_url': 'https://api.minimax.chat/v1',
      'api_path': '/chat/completions',
      'model_list_path': '/models',
      'auth_type': 'bearer',
    },
    {
      'id': 'lingyi',
      'name': '零一万物 (Yi)',
      'api_url': 'https://api.lingyiwanwu.com/v1',
      'api_path': '/chat/completions',
      'model_list_path': '/models',
      'auth_type': 'bearer',
    },
    {
      'id': 'siliconflow',
      'name': 'SiliconFlow (硅基流动)',
      'api_url': 'https://api.siliconflow.cn/v1',
      'api_path': '/chat/completions',
      'model_list_path': '/models',
      'auth_type': 'bearer',
    },
    {
      'id': 'sensetime',
      'name': '商汤日日新',
      'api_url': 'https://token.sensenova.cn/v1',
      'api_path': '/chat/completions',
      'model_list_path': '/models',
      'auth_type': 'bearer',
    },
    {
      'id': 'baichuan',
      'name': '百川智能 (Baichuan)',
      'api_url': 'https://api.baichuan-ai.com/v1',
      'api_path': '/chat/completions',
      'model_list_path': '/models',
      'auth_type': 'bearer',
    },
    // —— 特殊 ——
    {
      'id': 'azure',
      'name': 'Azure OpenAI',
      'api_url': '',
      'api_path': '/chat/completions',
      'model_list_path': '/models',
      'auth_type': 'api-key',
    },
    {
      'id': 'custom',
      'name': '自定义 (OpenAI 兼容)',
      'api_url': '',
      'api_path': '/chat/completions',
      'model_list_path': '/models',
      'auth_type': 'bearer',
    },
  ];

  /// 获取内置预设列表
  static List<ProviderDefinition> get all => presets.map((p) {
        final id = p['id']!;
        return ProviderDefinition(
          id: id,
          name: p['name']!,
          apiUrl: p['api_url']!,
          apiPath: p['api_path']!,
          modelListPath: p['model_list_path']!,
          authType: p['auth_type']!,
          builtIn: true,
        );
      }).toList();

  /// 按 ID 查找内置预设
  static ProviderDefinition? byId(String id) {
    try {
      return all.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }
}