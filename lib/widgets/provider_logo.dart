import 'package:flutter/material.dart';
import 'package:relaygo/config/theme.dart';

/// 提供商小 Logo
///
/// 优先加载本地 assets/logos/{id}.png 图片资源，
/// 找不到时回退为首字母圆形图标。
class ProviderLogo extends StatelessWidget {
  final String providerId; // 提供商 ID（如 openai、deepseek、custom_xxx）
  final String? providerName; // 提供商显示名（回退字母用）
  final double size;

  const ProviderLogo({
    Key? key,
    required this.providerId,
    this.providerName,
    this.size = 24,
  }) : super(key: key);

  /// 从 providerId 提取 logo 文件对应的 key
  /// 内置提供商直接匹配；自定义提供商使用 providerId 本身
  static String? _logoKey(String id) {
    if (id.isEmpty) return null;
    // 内置提供商 ID 白名单（与 BuiltInProviders 的 id 一致）
    const builtInIds = {
      'openai', 'anthropic', 'google', 'xai', 'perplexity',
      'together', 'openrouter', 'mistral', 'cohere', 'groq',
      'deepseek', 'moonshot', 'zhipu', 'qwen', 'baidu',
      'hunyuan', 'doubao', 'stepfun', 'minimax', 'lingyi',
      'siliconflow', 'sensetime', 'baichuan', 'xfyun', 'azure',
    };
    if (builtInIds.contains(id)) return id;
    return null; // 自定义提供商无 logo
  }

  @override
  Widget build(BuildContext context) {
    final key = _logoKey(providerId);
    if (key != null) {
      return SizedBox(
        width: size,
        height: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.asset(
            'assets/logos/$key.png',
            width: size,
            height: size,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _fallback,
          ),
        ),
      );
    }
    return _fallback;
  }

  Widget get _fallback {
    final letter = (providerName ?? providerId).isNotEmpty
        ? (providerName ?? providerId)[0].toUpperCase()
        : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          fontSize: size * 0.5,
          fontWeight: FontWeight.w700,
          color: AppTheme.text2,
        ),
      ),
    );
  }
}