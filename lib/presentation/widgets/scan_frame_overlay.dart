import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Lớp phủ khung ngắm: làm tối vùng ngoài, vẽ 4 góc ngoặc và "tia quét" chạy dọc.
class ScanFrameOverlay extends StatelessWidget {
  const ScanFrameOverlay({
    super.key,
    required this.frame,
    required this.scanProgress,
    this.frameProgress = 1,
    this.accent = AppColors.mint,
  });

  /// Khung crop theo toạ độ pixel của vùng preview.
  final Rect frame;
  final double scanProgress;
  final double frameProgress;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _ScanFramePainter(
          frame: frame,
          scanProgress: scanProgress,
          frameProgress: frameProgress,
          accent: accent,
        ),
      ),
    );
  }
}

class _ScanFramePainter extends CustomPainter {
  _ScanFramePainter({
    required this.frame,
    required this.scanProgress,
    required this.frameProgress,
    required this.accent,
  });

  final Rect frame;
  final double scanProgress;
  final double frameProgress;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect target = frame;
    final RRect rounded = RRect.fromRectAndRadius(target, const Radius.circular(22));

    final Path overlay = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(rounded)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      overlay,
      Paint()..color = Colors.black.withValues(alpha: 0.58),
    );

    canvas.drawRRect(
      rounded,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.16),
    );

    _drawCornerBrackets(canvas, target);
    _drawScanBeam(canvas, target);
  }

  void _drawCornerBrackets(Canvas canvas, Rect rect) {
    final double length = 30 * frameProgress.clamp(0, 1);
    if (length <= 0.5) return;

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.6
      ..strokeCap = StrokeCap.round
      ..color = accent;

    void corner(Offset origin, Offset horizontal, Offset vertical) {
      canvas.drawLine(origin, origin + horizontal * length, paint);
      canvas.drawLine(origin, origin + vertical * length, paint);
    }

    corner(rect.topLeft, const Offset(1, 0), const Offset(0, 1));
    corner(rect.topRight, const Offset(-1, 0), const Offset(0, 1));
    corner(rect.bottomLeft, const Offset(1, 0), const Offset(0, -1));
    corner(rect.bottomRight, const Offset(-1, 0), const Offset(0, -1));
  }

  void _drawScanBeam(Canvas canvas, Rect rect) {
    final double y = rect.top + rect.height * scanProgress;
    final Rect beam = Rect.fromLTWH(rect.left, y - 34, rect.width, 34);

    canvas.drawRect(
      beam,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: <Color>[
            accent.withValues(alpha: 0.30),
            accent.withValues(alpha: 0),
          ],
        ).createShader(beam),
    );

    final Rect line = Rect.fromLTWH(rect.left, y, rect.width, 2);
    canvas.drawRect(
      line,
      Paint()
        ..shader = LinearGradient(
          colors: <Color>[
            accent.withValues(alpha: 0),
            accent,
            accent.withValues(alpha: 0),
          ],
        ).createShader(line),
    );
  }

  @override
  bool shouldRepaint(covariant _ScanFramePainter oldDelegate) {
    return oldDelegate.scanProgress != scanProgress ||
        oldDelegate.frameProgress != frameProgress ||
        oldDelegate.frame != frame ||
        oldDelegate.accent != accent;
  }
}
