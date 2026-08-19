/// 路由规则（需求 2.2.3 规则引擎）
///
/// 示例：
///   name: "大模型路由"
///   condition: "request.model contains 'gpt-4'"
///   action: "use_provider('openai', priority='high')"
///
///   name: "免费额度优先"
///   condition: "time in ['00:00-06:00']"
///   action: "use_provider('free_keys', strategy='round_robin')"
class RoutingRule {
  final String id;
  final String name;
  final String condition; // 条件表达式
  final String action; // 动作表达式
  final bool enabled;
  final int order; // 数值越小越先匹配
  final String description;

  RoutingRule({
    required this.id,
    required this.name,
    required this.condition,
    required this.action,
    this.enabled = true,
    this.order = 100,
    this.description = '',
  });

  factory RoutingRule.fromJson(Map<String, dynamic> json) {
    return RoutingRule(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      condition: json['condition'] as String? ?? '',
      action: json['action'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      order: json['order'] as int? ?? 100,
      description: json['description'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'condition': condition,
      'action': action,
      'enabled': enabled,
      'order': order,
      'description': description,
    };
  }

  RoutingRule copyWith({
    String? name,
    String? condition,
    String? action,
    bool? enabled,
    int? order,
    String? description,
  }) {
    return RoutingRule(
      id: id,
      name: name ?? this.name,
      condition: condition ?? this.condition,
      action: action ?? this.action,
      enabled: enabled ?? this.enabled,
      order: order ?? this.order,
      description: description ?? this.description,
    );
  }
}
