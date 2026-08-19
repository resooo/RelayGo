/// 统一模型信息（中转站聚合各服务商模型后的本地存储单元）
///
/// 设计要点：
/// - 内部 [id] 采用统一命名 `provider:model_name`，便于跨服务商去重与聚合；
/// - 对外接口（[toOpenAIFormat]）返回上游可识别的原始模型名 [name]，并附 `provider`
///   扩展字段，确保 AI 应用拿到后可直接用于请求（避免把 `provider:name` 透传给上游）。
class ModelInfo {
  final String id; // 统一 ID：provider:model_name
  final String provider; // 服务商标识（openai / anthropic / ...）
  final String name; // 模型原始名称（上游可识别，如 gpt-4-turbo）
  final String displayName; // 展示名（默认同 name）
  final String? ownedBy; // 所属组织
  final List<String> capabilities; // 能力标签
  final String status; // active / deprecated / coming_soon
  final bool isEnabled; // 是否启用（用户可手动关闭）
  final int? createdAt; // 上游创建时间（毫秒）
  final int lastSynced; // 最后同步时间（毫秒）
  final Map<String, dynamic> rawData; // 上游原始响应（保留用于排查）

  // —— P0 能力分层：virtualId 归类 ——
  /// 归一化归类指针，如 `chat-premium`；nullable（未归一前兼容旧数据，惰性回填）。
  final String? virtualId;

  /// 来源提供的典型上下文窗口（缺失时为 null，由归一化按名称推断）。
  final int? contextWindow;

  // —— 来源 key 关联 ——
  /// 拉取该模型的 key id（用于「删除 key 时清理其模型」与按 key 批量启停）。
  final String sourceKeyId;

  ModelInfo({
    required this.id,
    required this.provider,
    required this.name,
    required this.displayName,
    this.ownedBy,
    this.capabilities = const [],
    this.status = 'active',
    this.isEnabled = true,
    this.createdAt,
    required this.lastSynced,
    this.rawData = const {},
    this.virtualId,
    this.contextWindow,
    this.sourceKeyId = '',
  });

  /// 便捷构造：自动生成统一 id
  factory ModelInfo.unified({
    required String provider,
    required String name,
    String? displayName,
    String? ownedBy,
    List<String> capabilities = const [],
    String status = 'active',
    bool isEnabled = true,
    int? createdAt,
    required int lastSynced,
    Map<String, dynamic> rawData = const {},
    String? virtualId,
    int? contextWindow,
    String sourceKeyId = '',
  }) {
    return ModelInfo(
      id: unifiedId(provider, name),
      provider: provider,
      name: name,
      displayName: displayName ?? name,
      ownedBy: ownedBy,
      capabilities: capabilities,
      status: status,
      isEnabled: isEnabled,
      createdAt: createdAt,
      lastSynced: lastSynced,
      rawData: rawData,
      virtualId: virtualId,
      contextWindow: contextWindow,
      sourceKeyId: sourceKeyId,
    );
  }

  /// 统一 ID 生成规则
  static String unifiedId(String provider, String name) => '$provider:$name';

  /// 根据模型名推断能力标签
  static List<String> inferCapabilities(String modelId) {
    final id = modelId.toLowerCase();
    final caps = <String>[];

    if (id.contains('gpt-4') ||
        id.contains('gpt-3.5') ||
        id.contains('gpt-35') ||
        id.contains('gpt-4o') ||
        id.contains('o1') ||
        id.contains('o3') ||
        id.contains('chatgpt') ||
        id.contains('claude') ||
        id.contains('gemini') ||
        id.contains('qwen') ||
        id.contains('deepseek') ||
        id.contains('llama')) {
      caps.addAll(['chat', 'completion', 'function_calling']);
    }
    if (id.contains('embedding') || id.contains('text-embedding')) {
      caps.add('embedding');
    }
    if (id.contains('dall-e') ||
        id.contains('imagen') ||
        id.contains('image') ||
        id.contains('flux') ||
        id.contains('stable-diffusion')) {
      caps.add('image_generation');
    }
    if (id.contains('vision') || id.contains('-vision')) {
      caps.add('vision');
    }
    if (id.contains('whisper') || id.contains('audio')) {
      caps.add('audio_transcription');
    }
    if (id.contains('tts') || id.contains('audio-1') || id.contains('speech')) {
      caps.add('text_to_speech');
    }
    if (id.contains('moderation')) {
      caps.add('moderation');
    }
    if (caps.isEmpty) caps.add('completion');
    return caps;
  }

  ModelInfo copyWith({
    String? id,
    String? provider,
    String? name,
    String? displayName,
    String? ownedBy,
    List<String>? capabilities,
    String? status,
    bool? isEnabled,
    int? createdAt,
    int? lastSynced,
    Map<String, dynamic>? rawData,
    String? virtualId,
    int? contextWindow,
    String? sourceKeyId,
  }) {
    return ModelInfo(
      id: id ?? this.id,
      provider: provider ?? this.provider,
      name: name ?? this.name,
      displayName: displayName ?? this.displayName,
      ownedBy: ownedBy ?? this.ownedBy,
      capabilities: capabilities ?? this.capabilities,
      status: status ?? this.status,
      isEnabled: isEnabled ?? this.isEnabled,
      createdAt: createdAt ?? this.createdAt,
      lastSynced: lastSynced ?? this.lastSynced,
      rawData: rawData ?? this.rawData,
      virtualId: virtualId ?? this.virtualId,
      contextWindow: contextWindow ?? this.contextWindow,
      sourceKeyId: sourceKeyId ?? this.sourceKeyId,
    );
  }

  factory ModelInfo.fromJson(Map<String, dynamic> json) {
    return ModelInfo(
      id: json['id'] as String,
      provider: json['provider'] as String,
      name: json['name'] as String,
      displayName: json['display_name'] as String? ?? (json['name'] as String),
      ownedBy: json['owned_by'] as String?,
      capabilities: json['capabilities'] == null
          ? const <String>[]
          : List<String>.from(json['capabilities'] as List),
      status: json['status'] as String? ?? 'active',
      isEnabled: json['is_enabled'] as bool? ?? true,
      createdAt: json['created_at'] as int?,
      lastSynced: json['last_synced'] as int? ?? 0,
      rawData: json['raw_data'] == null
          ? const <String, dynamic>{}
          : Map<String, dynamic>.from(json['raw_data'] as Map),
      virtualId: json['virtual_id'] as String?,
      contextWindow: json['context_window'] as int?,
      sourceKeyId: json['source_key_id'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'provider': provider,
      'name': name,
      'display_name': displayName,
      'owned_by': ownedBy,
      'capabilities': capabilities,
      'status': status,
      'is_enabled': isEnabled,
      'created_at': createdAt,
      'last_synced': lastSynced,
      'raw_data': rawData,
      'virtual_id': virtualId,
      'context_window': contextWindow,
      'source_key_id': sourceKeyId,
    };
  }

  /// 转为 OpenAI /v1/models 兼容格式（供 AI 应用查询）
  ///
  /// 返回上游可识别的 [name] 作为 id，并附带 [provider] 扩展字段，
  /// 便于客户端按服务商筛选而不破坏标准 OpenAI 客户端解析。
  /// 若已归类，额外附上 [virtualId]（虚拟模型 id）。
  Map<String, dynamic> toOpenAIFormat() {
    return {
      'id': name,
      'object': 'model',
      'created': (createdAt ?? 0) ~/ 1000,
      'owned_by': ownedBy ?? provider,
      'permission': [],
      'root': name,
      'parent': null,
      // 扩展字段（中转站自定义）
      'provider': provider,
      'display_name': displayName,
      'capabilities': capabilities,
      'status': status,
      'enabled': isEnabled,
      'virtual_id': virtualId,
      'context_window': contextWindow,
    };
  }

  /// 转为 Anthropic 模型格式
  Map<String, dynamic> toAnthropicFormat() {
    return {
      'type': 'model',
      'id': name,
      'display_name': displayName,
      'created_at': createdAt != null
          ? DateTime.fromMillisecondsSinceEpoch(createdAt!)
              .toUtc()
              .toIso8601String()
          : DateTime.fromMillisecondsSinceEpoch(lastSynced)
              .toUtc()
              .toIso8601String(),
      'provider': provider,
    };
  }
}
