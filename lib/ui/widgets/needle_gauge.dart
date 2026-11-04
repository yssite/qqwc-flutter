/// 指针式速度表：厚渐变外环 + 等角刻度 + 锥形指针 + 等宽读数。
///
/// 参考 Speedtest 的仪表盘观感（外环粗、刻度少而清晰、指针利落），
/// 配色与圆角仍遵循 Material 3。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../engine/models.dart';
import '../../theme/app_theme.dart';

class NeedleGauge extends StatelessWidget {
  const NeedleGauge({
    super.key,
    required this.value,
    required this.maxValue,
    required this.phase,
    required this.label,
    this.score,
    this.grade,
    this.upload = false,
  });

  final double value;
  final double maxValue;
  final TestPhase phase;
  final String label;
  final int? score;
  final String? grade;
  final bool upload;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final colors = upload ? palette.uploadGradient : palette.downloadGradient;
    final idle = phase == TestPhase.idle;
    final spokenValue = idle
        ? '待机'
        : '${value >= 1000 ? value.toStringAsFixed(0) : value.toStringAsFixed(1)} Mbps';

    return Semantics(
      label: '速度仪表盘，${label.isEmpty ? '待机' : label}',
      value: spokenValue,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = math.min(constraints.maxWidth, 430.0);
          final height = side * 0.82;
          return SizedBox(
            width: side,
            height: height,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: value.clamp(0, maxValue)),
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeOutCubic,
              builder: (context, animated, _) {
                return CustomPaint(
                  painter: _GaugePainter(
                    value: animated,
                    maxValue: maxValue,
                    colors: colors,
                    track: dark
                        ? const Color(0xFF1A2438)
                        : scheme.onSurface.withValues(alpha: 0.08),
                    tickColor: dark
                        ? Colors.white.withValues(alpha: 0.60)
                        : scheme.onSurfaceVariant,
                    needleColor: dark ? Colors.white : const Color(0xFF16203A),
                    needleGlow: dark
                        ? Colors.white.withValues(alpha: 0.30)
                        : Colors.black.withValues(alpha: 0.12),
                  ),
                  child: _Readout(
                    value: animated,
                    phase: phase,
                    label: label,
                    score: score,
                    grade: grade,
                    side: side,
                    dark: dark,
                    scheme: scheme,
                    accent: colors.first,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({
    required this.value,
    required this.phase,
    required this.label,
    required this.score,
    required this.grade,
    required this.side,
    required this.dark,
    required this.scheme,
    required this.accent,
  });

  final double value;
  final TestPhase phase;
  final String label;
  final int? score;
  final String? grade;
  final double side;
  final bool dark;
  final ColorScheme scheme;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final idle = phase == TestPhase.idle;
    final onColor = dark ? Colors.white : scheme.onSurface;
    final subColor = dark
        ? Colors.white.withValues(alpha: 0.52)
        : scheme.onSurfaceVariant;

    final valueText = idle
        ? '0.0'
        : (value >= 1000 ? value.toStringAsFixed(0) : value.toStringAsFixed(1));

    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(top: side * 0.565),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              valueText,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: side * 0.155,
                fontWeight: FontWeight.w500,
                letterSpacing: -3,
                height: 1,
                color: onColor,
                fontFeatures: AppFonts.tabular,
              ),
            ),
            SizedBox(height: side * 0.016),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  phase == TestPhase.upload
                      ? Icons.north_rounded
                      : Icons.south_rounded,
                  size: side * 0.038,
                  color: idle ? subColor : accent,
                ),
                SizedBox(width: side * 0.012),
                Text(
                  'Mbps',
                  style: text.labelSmall?.copyWith(
                    color: subColor,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (!idle) ...[
                  SizedBox(width: side * 0.02),
                  Text(
                    '· $label',
                    style: text.labelSmall?.copyWith(color: subColor),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.value,
    required this.maxValue,
    required this.colors,
    required this.track,
    required this.tickColor,
    required this.needleColor,
    required this.needleGlow,
  });

  final double value;
  final double maxValue;
  final List<Color> colors;
  final Color track;
  final Color tickColor;
  final Color needleColor;
  final Color needleGlow;

  static const double _startDeg = 145;
  static const double _sweepDeg = 250;

  List<double> get _ticks {
    final max = maxValue;
    if (max <= 30) return [0, 5, 10, 20, 30];
    if (max <= 60) return [0, 10, 20, 30, 50];
    if (max <= 120) return [0, 1, 5, 10, 25, 50, 100];
    if (max <= 250) return [0, 10, 25, 50, 100, 250];
    if (max <= 600) return [0, 25, 50, 100, 250, 500];
    if (max <= 1200) return [0, 50, 100, 250, 500, 1000];
    return [0, 50, 250, 500, 1000, max.roundToDouble()];
  }

  /// 刻度等角度分布，数值按刻度表分段线性映射
  double _position(double v) {
    final ticks = _ticks;
    final n = ticks.length - 1;
    if (n <= 0) return 0;
    final clamped = v.clamp(ticks.first, ticks.last).toDouble();
    for (var i = 0; i < n; i++) {
      if (clamped <= ticks[i + 1]) {
        final span = ticks[i + 1] - ticks[i];
        final local = span == 0 ? 0.0 : (clamped - ticks[i]) / span;
        return (i + local) / n;
      }
    }
    return 1;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.47);
    final radius = math.min(size.width * 0.44, size.height * 0.38);
    // 外环：比原先粗一倍，并整体向外扩
    final stroke = radius * 0.20;
    final band = radius + stroke / 2;
    final rect = Rect.fromCircle(center: center, radius: band);
    final startRad = _startDeg * math.pi / 180;
    const sweepRad = _sweepDeg * math.pi / 180;

    canvas.drawArc(
      rect,
      startRad,
      sweepRad,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );

    final shader = SweepGradient(
      startAngle: startRad,
      endAngle: startRad + sweepRad,
      colors: [colors.first, colors[colors.length ~/ 2], colors.last],
      stops: const [0, 0.55, 1],
      tileMode: TileMode.clamp,
    ).createShader(rect);

    final ratio = _position(value);
    if (ratio <= 0.004) {
      canvas.drawArc(
        rect,
        startRad,
        sweepRad,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = (track.computeLuminance() > 0.5
              ? Colors.black.withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.14))
          ..shader = shader,
      );
    } else {
      canvas.drawArc(
        rect,
        startRad,
        sweepRad * ratio,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..shader = shader,
      );
    }

    // 先画指针再画刻度文字，保证刻度始终可读
    _paintNeedle(canvas, center, radius, stroke, startRad, sweepRad, ratio);
    _paintTicks(canvas, center, radius, stroke, startRad, sweepRad);
  }

  /// 只保留数值，不再画刻度短线（线条会让表盘显得杂乱）
  void _paintTicks(
    Canvas canvas,
    Offset center,
    double radius,
    double stroke,
    double startRad,
    double sweepRad,
  ) {
    final ticks = _ticks;
    final segments = ticks.length - 1;
    final ringInner = radius + stroke / 2 - stroke; // 外环内缘
    final labelR = ringInner - radius * 0.105;

    for (var i = 0; i < ticks.length; i++) {
      final t = segments == 0 ? 0.0 : i / segments;
      final angle = startRad + sweepRad * t;
      final dir = Offset(math.cos(angle), math.sin(angle));

      final tp = TextPainter(
        text: TextSpan(
          text: _fmtTick(ticks[i]),
          style: TextStyle(
            fontFamily: AppFonts.mono,
            color: tickColor,
            fontSize: radius * 0.098,
            fontWeight: FontWeight.w500,
            fontFeatures: AppFonts.tabular,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelCenter = center + dir * labelR;
      tp.paint(canvas, labelCenter - Offset(tp.width / 2, tp.height / 2));
    }
  }

  void _paintNeedle(
    Canvas canvas,
    Offset center,
    double radius,
    double stroke,
    double startRad,
    double sweepRad,
    double ratio,
  ) {
    final angle = startRad + sweepRad * ratio;
    final dir = Offset(math.cos(angle), math.sin(angle));
    final perp = Offset(-dir.dy, dir.dx);
    final length = radius - stroke * 0.55;
    final baseHalf = stroke * 0.22;
    final tip = center + dir * length;

    final path = Path()
      ..moveTo(center.dx + perp.dx * baseHalf, center.dy + perp.dy * baseHalf)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(center.dx - perp.dx * baseHalf, center.dy - perp.dy * baseHalf)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = needleGlow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    // 渐变刀锋：根部淡 → 针尖实
    final shader = LinearGradient(
      begin: Alignment.center,
      end: Alignment.centerRight,
      colors: [
        needleColor.withValues(alpha: 0.35),
        needleColor.withValues(alpha: 0.85),
        needleColor,
      ],
      stops: const [0, 0.55, 1],
    ).createShader(Rect.fromCircle(center: center, radius: length));
    canvas.drawPath(path, Paint()..shader = shader);

    canvas.drawCircle(center, stroke * 0.16, Paint()..color = needleColor);
  }

  String _fmtTick(double v) => v >= 1000
      ? '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k'
      : v.toStringAsFixed(0);

  /// 仪表盘只负责绘制，不参与命中测试（否则会吞掉下方卡片的点击）
  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.value != value ||
      old.maxValue != maxValue ||
      old.colors != colors ||
      old.track != track;
}
