import 'dart:convert';

/// Token 用量
class TokenUsage {
  final int promptTokens;
  final int completionTokens;

  const TokenUsage(this.promptTokens, this.completionTokens);

  static const TokenUsage empty = TokenUsage(0, 0);

  int get total => promptTokens + completionTokens;

  bool get isEmpty => promptTokens == 0 && completionTokens == 0;

  /// 合并：取各维度较大值
  ///
  /// 流式响应里 Anthropic 的 input_tokens 出现在 message_start、
  /// output_tokens 在 message_delta 中累积上报，取 max 才能得到最终值。
  TokenUsage merge(TokenUsage other) => TokenUsage(
        promptTokens > other.promptTokens ? promptTokens : other.promptTokens,
        completionTokens > other.completionTokens
            ? completionTokens
            : other.completionTokens,
      );

  @override
  String toString() => 'TokenUsage(prompt: $promptTokens, completion: $completionTokens)';
}

/// 请求体解析结果（用于规则引擎与提供商识别）
class RequestPayload {
  final String model;
  final bool stream;
  final int bytes;
  final int estimatedTokens;

  const RequestPayload({
    this.model = '',
    this.stream = false,
    this.bytes = 0,
    this.estimatedTokens = 0,
  });

  /// 从请求体字节解析（非 JSON / 解析失败时安全降级）
  factory RequestPayload.parse(List<int> body) {
    if (body.isEmpty) return const RequestPayload();
    String text;
    try {
      text = utf8.decode(body, allowMalformed: true);
    } catch (_) {
      return RequestPayload(bytes: body.length);
    }
    dynamic json;
    try {
      json = jsonDecode(text);
    } catch (_) {
      return RequestPayload(
        bytes: body.length,
        estimatedTokens: UsageParser.estimateTokens(text),
      );
    }
    if (json is! Map) {
      return RequestPayload(
        bytes: body.length,
        estimatedTokens: UsageParser.estimateTokens(text),
      );
    }
    final map = Map<String, dynamic>.from(json);
    return RequestPayload(
      model: UsageParser.extractModel(map) ?? '',
      stream: map['stream'] == true,
      bytes: body.length,
      estimatedTokens: UsageParser.estimateTokens(_promptText(map, text)),
    );
  }

  /// 提取用于估算 token 的文本（优先取 messages/contents/prompt）
  static String _promptText(Map<String, dynamic> map, String fallback) {
    final buf = StringBuffer();
    final messages = map['messages'];
    if (messages is List) {
      for (final m in messages) {
        if (m is Map && m['content'] != null) {
          buf.write(_flatten(m['content']));
          buf.write(' ');
        }
      }
    }
    final contents = map['contents']; // Google
    if (contents is List) {
      for (final c in contents) {
        if (c is Map && c['parts'] is List) {
          for (final p in (c['parts'] as List)) {
            if (p is Map && p['text'] != null) buf.write('${p['text']} ');
          }
        }
      }
    }
    if (map['prompt'] != null) buf.write(_flatten(map['prompt']));
    if (map['input'] != null) buf.write(_flatten(map['input']));
    final s = buf.toString();
    return s.trim().isEmpty ? fallback : s;
  }

  static String _flatten(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    if (v is List) return v.map(_flatten).join(' ');
    if (v is Map) {
      if (v['text'] is String) return v['text'] as String;
      return v.values.map(_flatten).join(' ');
    }
    return '$v';
  }
}

/// 从上游响应中解析 token 用量
///
/// 同时兼容：
///  - OpenAI 非流式：`usage.prompt_tokens` / `usage.completion_tokens`
///  - OpenAI 流式（include_usage）：最后一个 data 块中的 usage
///  - Anthropic：`usage.input_tokens` / `usage.output_tokens`（含 message_start / message_delta）
///  - Google：`usageMetadata.promptTokenCount` / `candidatesTokenCount`
class UsageParser {
  /// 从单个 JSON 对象里提取用量
  static TokenUsage fromJsonMap(Map<String, dynamic> json) {
    var usage = TokenUsage.empty;

    final u = json['usage'];
    if (u is Map) {
      usage = usage.merge(TokenUsage(
        _int(u['prompt_tokens']) + _int(u['input_tokens']),
        _int(u['completion_tokens']) + _int(u['output_tokens']),
      ));
    }

    // Anthropic message_start：usage 藏在 message 里
    final msg = json['message'];
    if (msg is Map && msg['usage'] is Map) {
      final mu = msg['usage'] as Map;
      usage = usage.merge(TokenUsage(
        _int(mu['input_tokens']) + _int(mu['prompt_tokens']),
        _int(mu['output_tokens']) + _int(mu['completion_tokens']),
      ));
    }

    // Google
    final meta = json['usageMetadata'];
    if (meta is Map) {
      usage = usage.merge(TokenUsage(
        _int(meta['promptTokenCount']),
        _int(meta['candidatesTokenCount']),
      ));
    }

    return usage;
  }

  /// 从响应体文本解析（自动判断 JSON / SSE / JSON 数组流）
  static TokenUsage parseBody(String body) {
    final text = body.trim();
    if (text.isEmpty) return TokenUsage.empty;

    // SSE：逐行取 data:
    if (text.contains('data:')) {
      var usage = TokenUsage.empty;
      for (final rawLine in const LineSplitter().convert(text)) {
        final line = rawLine.trim();
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty || payload == '[DONE]') continue;
        final parsed = _tryDecodeMap(payload);
        if (parsed != null) usage = usage.merge(fromJsonMap(parsed));
      }
      if (!usage.isEmpty) return usage;
    }

    // 普通 JSON 对象
    final obj = _tryDecodeMap(text);
    if (obj != null) return fromJsonMap(obj);

    // JSON 数组（Google 流式返回数组分片）
    try {
      final decoded = jsonDecode(text);
      if (decoded is List) {
        var usage = TokenUsage.empty;
        for (final item in decoded) {
          if (item is Map) {
            usage = usage.merge(fromJsonMap(Map<String, dynamic>.from(item)));
          }
        }
        return usage;
      }
    } catch (_) {
      // 截断的流式片段无法整体解析，忽略
    }
    return TokenUsage.empty;
  }

  /// 从字节解析（内部做 UTF-8 宽松解码）
  static TokenUsage parseBytes(List<int> bytes) {
    if (bytes.isEmpty) return TokenUsage.empty;
    try {
      return parseBody(utf8.decode(bytes, allowMalformed: true));
    } catch (_) {
      return TokenUsage.empty;
    }
  }

  /// 提取模型名（兼容 OpenAI `model` 与 Google 路径式 `models/gemini-pro`）
  static String? extractModel(Map<String, dynamic> json) {
    final m = json['model'];
    if (m is String && m.isNotEmpty) {
      return m.startsWith('models/') ? m.substring(7) : m;
    }
    final deployment = json['deployment_id'];
    if (deployment is String && deployment.isNotEmpty) return deployment;
    return null;
  }

  /// 粗略估算 token 数（无上游用量时的兜底）：
  /// 英文约 4 字符/token，CJK 约 1.5 字符/token，这里按混合系数 3 估算。
  static int estimateTokens(String text) {
    if (text.isEmpty) return 0;
    var cjk = 0;
    for (final code in text.runes) {
      if (code >= 0x4E00 && code <= 0x9FFF) cjk++;
    }
    final others = text.length - cjk;
    final est = cjk * 0.7 + others / 4;
    return est.ceil();
  }

  static Map<String, dynamic>? _tryDecodeMap(String s) {
    try {
      final decoded = jsonDecode(s);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
    return null;
  }

  static int _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}
