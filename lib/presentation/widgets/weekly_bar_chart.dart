import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_time_formatter.dart';
import '../../domain/entities/spending_summary.dart';

/// Biểu đồ cột chi tiêu 7 ngày, vẽ tay bằng CustomPainter.
///
/// Cột mọc lần lượt (staggered) nhờ [Interval] trên cùng một AnimationController,
/// cột được chọn có glow và nhãn giá trị nổi bật.
class WeeklyBarChart extends StatefulWidget {
  const WeeklyBarChart({
    super.key,
    required this.days,
    this.highlightedIndex,
    this.onBarTap,
    this.height = 196,
  });

  final List<DailyTotal> days;
  final int? highlightedIndex;
  final ValueChanged<int>? onBarTap;
  final double height;

  @override
  State<WeeklyBarChart> createState() => _WeeklyBarChartState();
}

class _WeeklyBarChartState extends State<WeeklyBarChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant WeeklyBarChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool changed = oldWidget.days.length != widget.days.length ||
        _total(oldWidget.days) != _total(widget.days);
    if (changed) _controller.forward(from: 0);
  }

  double _total(List<DailyTotal> days) =>
      days.fold(0, (double sum, DailyTotal day) => sum + day.amount);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap(Offset position, Size size) {
    if (widget.days.isEmpty || widget.onBarTap == null) return;
    const double horizontalPadding = 10;
    final double plotWidth = size.width - horizontalPadding * 2;
    final double slot = plotWidth / widget.days.length;
    final int index =
        ((position.dx - horizontalPadding) / slot).floor().clamp(0, widget.days.length - 1);
    widget.onBarTap!(index);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Size size = Size(constraints.maxWidth, widget.height);
          return GestureDetector(
            onTapUp: (TapUpDetails details) =>
                _handleTap(details.localPosition, size),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (BuildContext context, Widget? _) => CustomPaint(
                size: size,
                painter: _WeeklyBarPainter(
                  days: widget.days,
                  highlightedIndex: widget.highlightedIndex,
                  animation: _controller.value,
                  today: DateTime.now(),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WeeklyBarPainter extends CustomPainter {
  _WeeklyBarPainter({
    required this.days,
    required this.highlightedIndex,
    required this.animation,
    required this.today,
  });

  final List<DailyTotal> days;
  final int? highlightedIndex;
  final double animation;
  final DateTime today;

  static const double _topPadding = 30;
  static const double _bottomPadding = 26;
  static const double _horizontalPadding = 10;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;

    final double plotHeight = size.height - _topPadding - _bottomPadding;
    final double plotWidth = size.width - _horizontalPadding * 2;
    if (plotHeight <= 0 || plotWidth <= 0) return;

    final double maxValue = days
        .map((DailyTotal day) => day.amount)
        .fold<double>(0, (double a, double b) => math.max(a, b));
    final double scaleMax = maxValue <= 0 ? 1 : maxValue * 1.15;

    _drawGrid(canvas, size, plotHeight);

    final double slot = plotWidth / days.length;
    final double barWidth = math.max(10, math.min(slot * 0.5, 30));

    for (int index = 0; index < days.length; index++) {
      final DailyTotal day = days[index];
      final double centerX =
          _horizontalPadding + slot * index + slot / 2;
      final bool isHighlighted = highlightedIndex == index ||
          (highlightedIndex == null && AppDateFormatter.isSameDay(day.date, today));

      final double rawRatio = day.amount / scaleMax;
      final double start = index / (days.length + 1.6);
      final double end = start + 0.55;
      final double progress = Interval(
        start.clamp(0.0, 1.0),
        end.clamp(0.0, 1.0),
        curve: kAppEmphasisCurve,
      ).transform(animation);

      final double barHeight = math.max(0, plotHeight * rawRatio * progress);
      final double bottom = size.height - _bottomPadding;
      final Rect trackRect = Rect.fromLTWH(
        centerX - barWidth / 2,
        _topPadding,
        barWidth,
        plotHeight,
      );
      final RRect track = RRect.fromRectAndRadius(
        trackRect,
        Radius.circular(barWidth / 2),
      );
      canvas.drawRRect(
        track,
        Paint()..color = Colors.white.withValues(alpha: 0.04),
      );

      final RRect bar = RRect.fromRectAndRadius(
        Rect.fromLTRB(
          centerX - barWidth / 2,
          bottom - barHeight,
          centerX + barWidth / 2,
          bottom,
        ),
        Radius.circular(barWidth / 2),
      );

      if (barHeight > 2) {
        final List<Color> colors = isHighlighted
            ? const <Color>[Color(0xFF39E8BE), Color(0xFF14A98A)]
            : const <Color>[Color(0xFF8391FF), Color(0xFF3D4BE0)];

        if (isHighlighted) {
          canvas.drawRRect(
            bar,
            Paint()
              ..color = colors.first.withValues(alpha: 0.35)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
          );
        }

        canvas.drawRRect(
          bar,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: colors,
            ).createShader(bar.outerRect),
        );
      }

      _drawValueLabel(
        canvas,
        centerX: centerX,
        bottom: bottom - barHeight - 20,
        amount: day.amount,
        highlighted: isHighlighted,
      );

      _drawDayLabel(
        canvas,
        centerX: centerX,
        y: bottom + 8,
        label: AppDateFormatter.weekdayShort(day.date),
        highlighted: isHighlighted,
      );
    }
  }

  void _drawGrid(Canvas canvas, Size size, double plotHeight) {
    final Paint paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    for (int i = 0; i <= 3; i++) {
      final double y = _topPadding + plotHeight * (i / 3);
      _drawDashedLine(
        canvas,
        Offset(_horizontalPadding, y),
        Offset(size.width - _horizontalPadding, y),
        paint,
      );
    }
  }

  void _drawDashedLine(Canvas canvas, Offset from, Offset to, Paint paint) {
    const double dash = 5;
    const double gap = 6;
    final double length = (to - from).distance;
    if (length <= 0) return;
    final Offset direction = (to - from) / length;
    double travelled = 0;
    while (travelled < length) {
      final double segment = math.min(dash, length - travelled);
      canvas.drawLine(
        from + direction * travelled,
        from + direction * (travelled + segment),
        paint,
      );
      travelled += dash + gap;
    }
  }

  void _drawValueLabel(
    Canvas canvas, {
    required double centerX,
    required double bottom,
    required double amount,
    required bool highlighted,
  }) {
    if (amount <= 0) return;
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: CurrencyFormatter.compact(amount),
        style: TextStyle(
          fontSize: highlighted ? 11 : 9.5,
          fontWeight: highlighted ? FontWeight.w800 : FontWeight.w600,
          color: highlighted ? AppColors.textPrimary : AppColors.textMuted,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(centerX - painter.width / 2, bottom - painter.height + 4),
    );
  }

  void _drawDayLabel(
    Canvas canvas, {
    required double centerX,
    required double y,
    required String label,
    required bool highlighted,
  }) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: highlighted ? 11.5 : 11,
          fontWeight: highlighted ? FontWeight.w800 : FontWeight.w500,
          color: highlighted ? AppColors.mint : AppColors.textMuted,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(centerX - painter.width / 2, y));
  }

  @override
  bool shouldRepaint(covariant _WeeklyBarPainter oldDelegate) {
    return oldDelegate.animation != animation ||
        oldDelegate.days != days ||
        oldDelegate.highlightedIndex != highlightedIndex;
  }
}
