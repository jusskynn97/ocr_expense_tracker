import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Dấu tick vẽ tay: vòng tròn lớn dần rồi nét tick được "vẽ" theo.
class SuccessCheck extends StatefulWidget {
  const SuccessCheck({super.key, this.size = 92, this.color = AppColors.mint});

  final double size;
  final Color color;

  @override
  State<SuccessCheck> createState() => _SuccessCheckState();
}

class _SuccessCheckState extends State<SuccessCheck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? _) => CustomPaint(
          painter: _CheckPainter(
            progress: _controller.value,
            color: widget.color,
          ),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = size.width / 2 - 6;

    final double ringProgress = (progress / 0.55).clamp(0, 1);
    final double tickProgress = ((progress - 0.45) / 0.55).clamp(0, 1);

    final double easedRing = kAppEmphasisCurve.transform(ringProgress);

    canvas.drawCircle(
      center,
      radius,
      Paint()..color = color.withValues(alpha: 0.10),
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * easedRing,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round
        ..color = color,
    );

    if (tickProgress <= 0) return;

    final Path tick = Path()
      ..moveTo(center.dx - radius * 0.42, center.dy + radius * 0.04)
      ..lineTo(center.dx - radius * 0.08, center.dy + radius * 0.38)
      ..lineTo(center.dx + radius * 0.46, center.dy - radius * 0.34);

    final List<PathMetric> metrics = tick.computeMetrics().toList();
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    for (final PathMetric metric in metrics) {
      canvas.drawPath(
        metric.extractPath(0, metric.length * kAppEmphasisCurve.transform(tickProgress)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CheckPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
