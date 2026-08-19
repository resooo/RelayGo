import 'package:relaygo/config/standard_models.dart';
import 'package:relaygo/models/model_info.dart';

/// 模型归一化（P0 能力分层）
///
/// 职责：
/// 1. [canonicalize] 把上游五花八门的真实模型名规范化（去版本/日期后缀、
///    大小写/分隔符归一、品牌 canonical 收敛），得到稳定 canonical。
/// 2. [assignVirtualId] 把 canonical 归到某个能力虚拟模型（virtualId），
///    未知模型返回 null（不强归，保留原样）。
///
/// 归一化发生在模型同步入库之前，作为一道转换层接入 ModelSyncService，
/// 不修改同步框架本身；同时在转发入口用 [resolveRequestModel] 把
/// 客户端请求的 virtualId / 品牌别名解析为具体档位。
class ModelNormalizer {
  const ModelNormalizer._();

  /// 判断请求体里的模型名是否为虚拟模型 / 品牌别名。
  /// 若是则返回对应 virtualId；否则返回 null（走真实模型名原逻辑）。
  static String? resolveRequestModel(String requestedModel) {
    if (requestedModel.isEmpty) return null;
    final raw = requestedModel.trim().toLowerCase();
    // 1. 直接命中虚拟模型 id
    if (StandardModelRegistry.isVirtualId(raw)) return raw;
    // 2. 命中别名（不区分大小写）
    final direct = StandardModelRegistry.aliases[raw];
    if (direct != null) return direct;
    // 3. 归一化后命中别名（如 gpt-4o-2024-05-13 → gpt-4o）
    return StandardModelRegistry.aliases[canonicalize(raw)];
  }

  /// 规范化模型名。
  ///
  /// 处理顺序：trim+小写 → 去掉 google 'models/' 前缀 → 去日期/版本后缀 →
  /// 分隔符归一（_ → -，连续 - 折叠）→ 去尾随空格。
  /// 例：`CLAUDE-3-5-Sonnet-20241022` → `claude-3-5-sonnet`；
  ///    `models/gemini-1.5-pro-preview` → `gemini-1.5-pro`。
  ///
  /// 注意：保留版本间的点号（`gemini-1.5`、`llama-3.1` 的 `.` 不作为分隔符），
  /// 以避免把语义上的点号误拆。
  static String canonicalize(String raw) {
    var s = raw.trim().toLowerCase();
    // google 前缀
    if (s.startsWith('models/')) s = s.substring('models/'.length);

    // 中文/全角分隔符归一（下划线、空白吸收为 `-`；保留点号）
    s = s.replaceAll(RegExp(r'[\s_]+'), '-').replaceAll('－', '-');
    // 折叠连续中划线（避免 `a--b`)
    while (s.contains('--')) {
      s = s.replaceAll('--', '-');
    }
    s = s.replaceAll(RegExp(r'-+$'), '').trim();

    // 去日期/版本后缀：只剥「末尾连续的纯数字段」且该数字串形如日期/版本
    // （4 位年份 / 6+ 位紧凑日期 / 至少 2 段数字），避免误伤 `-3`、`-8b`、`-16k`。
    final parts = s.split('-');
    var end = parts.length;
    while (end > 1 && RegExp(r'^\d+$').hasMatch(parts[end - 1])) {
      end--;
    }
    final numericRun = parts.sublist(end);
    if (_isVersionNumericRun(numericRun)) {
      parts.removeRange(end, parts.length);
    }
    // 再剥 1~2 个显式预览标记（preview/latest/beta/...）
    const markers = {
      'preview', 'latest', 'beta', 'snapshot', 'lts', 'official',
    };
    while (parts.length > 1 && markers.contains(parts.last)) {
      parts.removeLast();
    }
    return parts.join('-');
  }

  /// 判断末尾数字段是否应作为版本/日期剥掉。
  /// 满足其中之一即剥：(a) 含 4 位年份或 ≥6 位紧凑日期；(b) 数字段数量 ≥ 2（如 -2024-05-13）。
  static bool _isVersionNumericRun(List<String> run) {
    if (run.isEmpty) return false;
    for (final seg in run) {
      final n = seg.length;
      if (n == 4 || n >= 6) return true; // 年份 / 紧凑日期
    }
    return run.length >= 2;
  }

  /// 把 canonical 归到能力虚拟模型（virtualId）。
  /// 命中别名表则返回档位；未知模型返回 null。
  static String? assignVirtualId(String canon) {
    if (canon.isEmpty) return null;
    if (StandardModelRegistry.isVirtualId(canon)) return canon;
    return StandardModelRegistry.aliases[canon];
  }

  /// 能力兜底归类：别名表未命中时，按能力标签归到最贴近的虚拟档位。
  ///
  /// 保证「只要模型有可识别能力，就能收敛到某个虚拟模型」，
  /// 避免 /v1/models 收敛后返回空列表（第三方客户端拉取不到模型）。
  static String? assignByCapabilities(List<String> capabilities) {
    final caps = capabilities.map((c) => c.toLowerCase()).toSet();
    if (caps.contains('embedding')) return 'embedding';
    if (caps.contains('image_generation') || caps.contains('image')) {
      return 'image';
    }
    if (caps.contains('text_to_speech') || caps.contains('audio-tts')) {
      return 'audio-tts';
    }
    if (caps.contains('audio_transcription') || caps.contains('audio')) {
      return 'audio-transcribe';
    }
    if (caps.contains('rerank')) return 'rerank';
    if (caps.contains('moderation')) return 'moderation';
    if (caps.contains('chat') ||
        caps.contains('completion') ||
        caps.contains('function_calling')) {
      return 'chat-basic';
    }
    return null;
  }

  /// 按模型名关键词兜底归类（别名表 / 能力标签均未命中时使用）。
  ///
  /// 与 [assignByCapabilities] 的区别：对话模型按名称关键词区分档位
  /// （premium / advanced / standard / basic），避免全部塌缩成 chat-basic，
  /// 导致第三方客户端只拉到 1~2 个模型。
  static String? assignByModelName(String name) {
    final id = name.toLowerCase();
    // —— 非对话能力优先 ——
    if (id.contains('embedding')) return 'embedding';
    if (id.contains('dall-e') ||
        id.contains('imagen') ||
        id.contains('flux') ||
        id.contains('stable-diffusion') ||
        id.contains('-image') ||
        id.contains('image-')) {
      return 'image';
    }
    if (id.contains('whisper') || id.contains('audio-transcribe')) {
      return 'audio-transcribe';
    }
    if (id.contains('tts') || id.contains('speech') || id.contains('audio-1')) {
      return 'audio-tts';
    }
    if (id.contains('rerank')) return 'rerank';
    if (id.contains('moderation')) return 'moderation';

    // —— 对话模型按名称关键词分档 ——
    // 旗舰档：GPT-4o/5、o 系列推理、Claude Opus/4、Gemini Pro、DeepSeek R1 等
    if (id.contains('gpt-4o') ||
        id.contains('gpt-5') ||
        id.contains('gpt-4.1') ||
        id.contains('o1') ||
        id.contains('o3') ||
        id.contains('o4') ||
        id.contains('opus') ||
        id.contains('claude-4') ||
        id.contains('claude-3-7') ||
        id.contains('gemini-2.5-pro') ||
        id.contains('gemini-2.0-pro') ||
        id.contains('gemini-1.5-pro') ||
        id.contains('deepseek-reasoner') ||
        id.contains('deepseek-r1') ||
        id.contains('qwen-max') ||
        id.contains('qwen3-max') ||
        id.contains('minimax') ||
        id.contains('ernie-4') ||
        id.contains('doubao-pro') ||
        id.contains('llama-3.1-405b') ||
        id.contains('llama-3-405b') ||
        id.contains('kimi-k2') ||
        id.contains('glm-4-plus')) {
      return 'chat-premium';
    }
    // 高级档：GPT-4、Claude Sonnet、Gemini Flash/Pro 旧版、Qwen-VL、GLM-4 等
    if (id.contains('gpt-4-turbo') ||
        id.contains('gpt-4-32k') ||
        id.contains('gpt-4') ||
        id.contains('claude-3-5-sonnet') ||
        id.contains('claude-3-6') ||
        id.contains('claude-3-sonnet') ||
        id.contains('gemini-2.5-flash') ||
        id.contains('gemini-2.0-flash') ||
        id.contains('deepseek-v3') ||
        id.contains('deepseek-coder') ||
        id.contains('qwen-vl') ||
        id.contains('qwen2.5-72b') ||
        id.contains('qwen2-72b') ||
        id.contains('llama-3.1-70b') ||
        id.contains('llama-3-70b') ||
        id.contains('mistral-large') ||
        id.contains('glm-4') ||
        id.contains('moonshot-v1-128k') ||
        id.contains('kimi') ||
        id.contains('yi-large')) {
      return 'chat-advanced';
    }
    // 标准档：Claude Haiku、Gemini Flash、Llama 70B、Mistral Medium 等
    if (id.contains('claude-3-5-haiku') ||
        id.contains('claude-3-haiku') ||
        id.contains('gemini-1.5-flash') ||
        id.contains('gemini-2.0-flash-lite') ||
        id.contains('llama-3.1-70b') ||
        id.contains('llama-3-70b') ||
        id.contains('mistral-medium') ||
        id.contains('moonshot-v1-32k') ||
        id.contains('qwen-plus') ||
        id.contains('qwen2.5-32b') ||
        id.contains('yi-medium')) {
      return 'chat-standard';
    }
    // 基础档：GPT-3.5、GPT-4o-mini、Claude Haiku、DeepSeek Chat、Llama 8B 等
    if (id.contains('gpt-3.5') ||
        id.contains('gpt-35') ||
        id.contains('gpt-4o-mini') ||
        id.contains('gpt-4-plus-mini') ||
        id.contains('claude-3-haiku') ||
        id.contains('deepseek-chat') ||
        id.contains('qwen-turbo') ||
        id.contains('qwen2-7b') ||
        id.contains('qwen2.5-7b') ||
        id.contains('llama-3.1-8b') ||
        id.contains('llama-3-8b') ||
        id.contains('mistral-small') ||
        id.contains('glm-4-flash') ||
        id.contains('moonshot-v1-8k') ||
        id.contains('yi-light') ||
        id.contains('doubao-lite') ||
        id.contains('ernie-speed')) {
      return 'chat-basic';
    }
    return null;
  }

  /// 对单个已同步的模型做归一化：赋 [virtualId] 与 [contextWindow]。
  ///
  /// 归一化失败（未知模型）时返回原对象（virtualId 保持 null），
  /// 不抛异常、不阻断同步链路。
  static ModelInfo normalize(ModelInfo m) {
    final canon = canonicalize(m.name);
    var vid = assignVirtualId(canon);
    vid ??= assignByModelName(m.name);
    // 别名 / 名称均未命中时按能力兜底，确保模型仍能收敛到虚拟档位
    vid ??= assignByCapabilities(m.capabilities);
    if (vid == null) return m;
    return m.copyWith(
      virtualId: vid,
      contextWindow: _inferContextWindow(canon, m),
    );
  }

  /// 按 canonical 推断典型上下文窗口（仅用于展示/分层，非硬约束）。
  static int _inferContextWindow(String canon, ModelInfo m) {
    // 明确带上下文标记（-128k / -32k / 数字+16k）时优先解析
    final k = RegExp(r'-(\d{1,3})k\b').firstMatch(canon);
    if (k != null) {
      final n = int.tryParse(k.group(1)!);
      if (n != null) return n * 1024;
    }
    if (canon.contains('128k')) return 128000;
    if (canon.contains('64k')) return 65536;
    if (canon.contains('32k')) return 32768;
    if (canon.contains('16k')) return 16384;
    if (canon.contains('8k')) return 8192;
    // 档位默认值
    final vid = m.virtualId;
    if (vid != null) {
      final std = StandardModelRegistry.byId[vid];
      if (std != null) return std.contextWindow;
    }
    return 4096;
  }
}