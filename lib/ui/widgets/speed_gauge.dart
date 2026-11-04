/// 环形速度表：渐变弧 + 发光端点 + 刻度，随速度平滑追随。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class SpeedGauge extends StatelessWidget {
  const SpeedGauge({
    super.key,
    required this.value,
    required this.maxValue,
    required this.label,
    required this.unit,
    this.gradient,
    this.active = true,
    this.size,
  });

  final double value;
  final double maxValue;
  final String label;
  final String unit;
  final List<Color>? gradient;
  final bool active;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = context.palette;
    final colors = gradient ?? palette.downloadGradient;
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trackColor = isDark
        ? scheme.onSurface.withValues(alpha: 0.13)
        : scheme.surfaceContainerHighest.withValues(alpha: 0.85);

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = size ??
            math.min(constraints.maxWidth, 340.0).clamp(220.0, 360.0);
        return SizedBox(
          width: side,
          height: side * 0.80,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: value.clamp(0, maxValue)),
            duration: const Duration(milliseconds: 480),
            curve: Curves.easeOutCubic,
            builder: (context, animated, _) {
              return Semantics(
                label: '当前速率 ${value.toStringAsFixed(1)} Mbps，$label',
                child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _GaugePainter(
                        value: animated,
                        maxValue: maxValue,
                        colors: colors,
                        trackColor: trackColor,
                        glowColor: colors.first.withValues(alpha: 0.45),
                        tickColor: scheme.outlineVariant,
                        labelColor: scheme.onSurfaceVariant,
                        labelStyle: text.labelSmall ?? const TextStyle(),
                        active: active,
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: side * 0.10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              animated >= 1000
                                  ? animated.toStringAsFixed(0)
                                  : animated.toStringAsFixed(1),
                              style: text.displayMedium?.copyWith(
                                fontSize: side * 0.19,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -2,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Text(
                                unit,
                                style: text.labelLarge?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        AnimatedSwitcher(
                          duration: AppMotion.short,
                          child: Text(
                            label,
                            key: ValueKey(label),
                            style: text.labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              );
            },
          ),
        );
      },
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.value,
    required this.maxValue,
    required this.colors,
    required this.trackColor,
    required this.glowColor,
    required this.tickColor,
    required this.labelColor,
    required this.labelStyle,
    required this.active,
  });

  final double value;
  final double maxValue;
  final List<Color> colors;
  final Color trackColor;
  final Color glowColor;
  final Color tickColor;
  final Color labelColor;
  final TextStyle labelStyle;
  final bool active;

  static const double _startAngle = math.pi * 0.8; // 144°
  static const double _sweep = math.pi * 1.4; // 252°

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + size.height * 0.02);
    final radius = math.min(size.width, size.height) * 0.5 - 18;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final stroke = math.max(12.0, radius * 0.075);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawArc(rect, _startAngle, _sweep, false, track);

    final ratio = maxValue <= 0 ? 0.0 : (value / maxValue).clamp(0.0, 1.0);
    if (ratio > 0.001) {
      final gradientPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ).createShader(rect);

      if (active) {
        final glow = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = glowColor
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
        canvas.drawArc(rect, _startAngle, _sweep * ratio, false, glow);
      }
      canvas.drawArc(rect, _startAngle, _sweep * ratio, false, gradientPaint);

      // 端点：白芯 + 彩色光环
      final angle = _startAngle + _sweep * ratio;
      final dot = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      canvas.drawCircle(
        dot,
        stroke * 0.82,
        Paint()
          ..color = colors.last
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawCircle(dot, stroke * 0.62, Paint()..color = Colors.white);
      canvas.drawCircle(
        dot,
        stroke * 0.30,
        Paint()..color = colors.first.withValues(alpha: 0.9),
      );
    }

    // 刻度
    final tickPaint = Paint()
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = tickColor.withValues(alpha: 0.8);
    for (var i = 0; i <= 20; i++) {
      final angle = _startAngle + _sweep * (i / 20);
      final major = i % 4 == 0;
      final inner = radius - stroke * 0.5 - (major ? 9 : 5);
      final outer = radius - stroke * 0.5 - 2;
      canvas.drawLine(
        center + Offset(math.cos(angle), math.sin(angle)) * inner,
        center + Offset(math.cos(angle), math.sin(angle)) * outer,
        tickPaint..color = tickColor.withValues(alpha: major ? 0.85 : 0.35),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.value != value ||
      old.maxValue != maxValue ||
      old.colors != colors ||
      old.active != active;
}
