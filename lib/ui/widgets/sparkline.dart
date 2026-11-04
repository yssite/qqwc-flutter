/// 实时速度曲线：平滑贝塞尔 + 渐变填充 + 预热区弱化。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.samples,
    required this.colors,
    this.preheatCount = 0,
    this.height = 120,
    this.emptyHint = '等待采样…',
  });

  final List<double> samples;
  final List<Color> colors;
  final int preheatCount;
  final double height;
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: samples.length < 2
          ? Center(
              child: Text(
                emptyHint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            )
          : TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 260),
              builder: (context, t, _) => CustomPaint(
                painter: _SparkPainter(
                  samples: samples,
                  preheatCount: preheatCount,
                  colors: colors,
                  grid: scheme.outlineVariant.withValues(alpha: 0.28),
                  progress: t,
                ),
              ),
            ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({
    required this.samples,
    required this.preheatCount,
    required this.colors,
    required this.grid,
    required this.progress,
  });

  final List<double> samples;
  final int preheatCount;
  final List<Color> colors;
  final Color grid;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const padTop = 12.0;
    const padBottom = 10.0;
    final chartHeight = size.height - padTop - padBottom;
    final maxValue = samples.reduce(math.max).clamp(1.0, double.infinity) * 1.18;
    final count = samples.length;
    final dx = size.width / math.max(count - 1, 1);

    Offset pointAt(int i) => Offset(
          i * dx,
          padTop + chartHeight * (1 - (samples[i] / maxValue).clamp(0.0, 1.0)),
        );

    // 网格：三条水平线
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = padTop + chartHeight * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final path = Path();
    final fill = Path();
    path.moveTo(pointAt(0).dx, pointAt(0).dy);
    fill.moveTo(pointAt(0).dx, size.height - padBottom);
    fill.lineTo(pointAt(0).dx, pointAt(0).dy);

    for (var i = 0; i < count - 1; i++) {
      final p0 = i == 0 ? pointAt(0) : pointAt(i - 1);
      final p1 = pointAt(i);
      final p2 = pointAt(i + 1);
      final p3 = i + 2 < count ? pointAt(i + 2) : p2;
      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
      fill.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    fill
      ..lineTo(pointAt(count - 1).dx, size.height - padBottom)
      ..close();

    final areaShader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        colors.first.withValues(alpha: 0.28),
        colors.last.withValues(alpha: 0.02),
      ],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fill, Paint()..shader = areaShader);

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = LinearGradient(colors: colors).createShader(
        Rect.fromLTWH(0, 0, size.width, size.height),
      );
    canvas.drawPath(path, linePaint);

    // 预热区：底部细条标注
    if (preheatCount > 0 && preheatCount < count) {
      final w = preheatCount * dx;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, size.height - 4, w, 3),
        const Radius.circular(2),
      );
      canvas.drawRRect(rect, Paint()..color = grid);
    }

    // 末端光点
    final last = pointAt(count - 1);
    canvas.drawCircle(
      last,
      7,
      Paint()
        ..color = colors.last.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(last, 3.6, Paint()..color = Colors.white);
    canvas.drawCircle(last, 1.8, Paint()..color = colors.last);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      old.samples.length != samples.length ||
      old.progress != progress ||
      (old.samples.isNotEmpty && samples.isNotEmpty
          ? old.samples.last != samples.last
          : true);
}
