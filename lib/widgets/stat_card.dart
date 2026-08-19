import 'package:flutter/material.dart';
import 'package:relaygo/config/theme.dart';

/// 统计卡片（Material 3 风格）
///
/// 白底 + 圆角16 + 阴影 Level 1 + 右上角光晕 + 等宽字体大号数值，
/// 对应设计稿 `.stat-card`（规格：圆角 16dp · 内边距 16dp · 阴影 0 2px 8px rgba(0,0,0,.1)）。
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? delta; // 可选增量文本（如 +12% / -3）
  final bool deltaUp; // delta 上升为成功色，否则危险色

  const StatCard({
    Key? key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.delta,
    this.deltaUp = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000), // rgba(0,0,0,.10)
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          // 右上角光晕装饰
          Positioned(
            right: -30,
            top: -30,
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    color.withOpacity(0.14),
                    color.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: AppTheme.text3, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.text2),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: AppTheme.monoFontFamily,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: color,
                  ),
                ),
                if (delta != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    delta!,
                    style: TextStyle(
                      fontFamily: AppTheme.monoFontFamily,
                      fontSize: 11.5,
                      color: deltaUp ? AppTheme.success : AppTheme.danger,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
