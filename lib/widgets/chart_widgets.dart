import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:relaygo/config/theme.dart';
import 'package:relaygo/l10n/app_strings.dart';

/// 简易横向柱状图（避免引入额外图表依赖）
class SimpleBarChart extends StatelessWidget {
  final Map<String, int> data; // 标签 -> 数值
  final Color color;

  const SimpleBarChart({
    Key? key,
    required this.data,
    this.color = AppTheme.accent,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Center(
          child: Text(L10n.tr('暂无数据'),
              style: const TextStyle(color: AppTheme.text3)));
    }
    final max = data.values.reduce((a, b) => a > b ? a : b).toDouble();
    return Column(
      children: data.entries.map((e) {
        final ratio = max > 0 ? e.value / max : 0.0;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              SizedBox(
                width: 90,
                child: Text(e.key,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.text2),
                    overflow: TextOverflow.ellipsis),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      height: 18,
                      decoration: BoxDecoration(
                        color: AppTheme.surface3,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: ratio,
                      child: Container(
                        height: 18,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('${e.value}',
                  style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.text2,
                      fontFamily: AppTheme.monoFontFamily)),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// 环形图（服务商占比等）
class DonutChart extends StatelessWidget {
  final Map<String, int> data; // 标签 -> 数值
  final double size;
  final double strokeWidth;

  const DonutChart({
    Key? key,
    required this.data,
    this.size = 120,
    this.strokeWidth = 22,
  }) : super(key: key);

  static const List<Color> _palette = [
    AppTheme.accent,
    AppTheme.accentStrong,
    AppTheme.info,
    AppTheme.warning,
    Color(0xFF9C27B0),
    AppTheme.danger,
    AppTheme.success,
    Color(0xFFF59E0B),
  ];

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Center(
          child: Text(L10n.tr('暂无数据'),
              style: const TextStyle(color: AppTheme.text3)));
    }
    final total = data.values.fold<int>(0, (a, b) => a + b).toDouble();
    final entries = data.entries.toList();

    return Row(
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _DonutPainter(entries, total, strokeWidth),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${total.round()}',
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.text,
                        fontFamily: AppTheme.monoFontFamily),
                  ),
                  Text(L10n.tr('总数'),
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.text3)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            children: entries.take(6).map((e) {
              final ratio = total > 0 ? e.value / total : 0.0;
              final idx = entries.indexOf(e);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _palette[idx % _palette.length],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(e.key,
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.text2),
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text(
                      '${(ratio * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.text2,
                          fontFamily: AppTheme.monoFontFamily),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<MapEntry<String, int>> entries;
  final double total;
  final double strokeWidth;

  _DonutPainter(this.entries, this.total, this.strokeWidth);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    var start = -math.pi / 2;
    for (var i = 0; i < entries.length; i++) {
      final sweep = total > 0
          ? (entries[i].value / total) * 2 * math.pi
          : 0.0;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt
        ..color = DonutChart._palette[i % DonutChart._palette.length];
      canvas.drawArc(rect, start, sweep - 0.02, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.entries != entries || oldDelegate.total != total;
}

/// 简易折线图（24 小时请求趋势等）
class SimpleLineChart extends StatelessWidget {
  final List<int> data; // 按小时/时段的有序数值
  final List<String> labels; // 与 data 等长的横轴标签
  final Color color;
  final double height;

  const SimpleLineChart({
    Key? key,
    required this.data,
    required this.labels,
    this.color = AppTheme.accent,
    this.height = 140,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Center(
          child: Text(L10n.tr('暂无数据'),
              style: const TextStyle(color: AppTheme.text3)));
    }
    final maxV = data.reduce((a, b) => a > b ? a : b).toDouble();
    final minV = data.reduce((a, b) => a < b ? a : b).toDouble();
    final range = (maxV - minV) == 0 ? 1.0 : (maxV - minV);

    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _LinePainter(data, labels, color, maxV, minV, range),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<int> data;
  final List<String> labels;
  final Color color;
  final double maxV;
  final double minV;
  final double range;

  _LinePainter(this.data, this.labels, this.color, this.maxV, this.minV, this.range);

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 8.0, padR = 8.0, padT = 12.0, padB = 22.0;
    final chartW = size.width - padL - padR;
    final chartH = size.height - padT - padB;
    if (chartW <= 0 || chartH <= 0 || data.length < 2) return;

    // 网格线
    final gridPaint = Paint()
      ..color = const Color(0xFF3B332A) // AppTheme.border
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = padT + chartH * i / 3;
      canvas.drawLine(Offset(padL, y), Offset(padL + chartW, y), gridPaint);
    }

    // 折线
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    final points = <Offset>[];
    for (var i = 0; i < data.length; i++) {
      final x = padL + chartW * i / (data.length - 1);
      final y = padT + chartH * (1 - (data[i] - minV) / range);
      points.add(Offset(x, y));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, linePaint);

    // 数据点 + 渐变填充
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withOpacity(0.25), color.withOpacity(0.0)],
      ).createShader(Rect.fromLTWH(0, padT, size.width, chartH));
    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, padT + chartH)
      ..lineTo(points.first.dx, padT + chartH)
      ..close();
    canvas.drawPath(fillPath, fillPaint);

    final dotPaint = Paint()..color = color;
    for (final p in points) {
      canvas.drawCircle(p, 3, dotPaint);
    }

    // 横轴标签（最多显示 6 个）
    final labelStyle = const TextStyle(
        fontSize: 9, color: AppTheme.text3, fontFamily: AppTheme.monoFontFamily);
    final step = math.max(1, (data.length / 6).ceil());
    for (var i = 0; i < data.length; i += step) {
      final x = padL + chartW * i / (data.length - 1);
      final tp = TextPainter(
        text: TextSpan(text: labels[i], style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
          canvas,
          Offset(
              (x - tp.width / 2).clamp(padL, padL + chartW - tp.width),
              size.height - tp.height));
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter oldDelegate) =>
      oldDelegate.data != data || oldDelegate.color != color;
}
