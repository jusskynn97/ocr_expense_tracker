import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../domain/entities/spending_summary.dart';
import 'category_visuals.dart';

/// Biểu đồ donut vẽ hoàn toàn bằng CustomPainter (không dùng thư viện chart).
///
/// - Animation "nở" từng lát cắt khi dữ liệu thay đổi.
/// - Chạm vào một lát để làm nổi bật (các lát khác mờ đi).
/// - Phần giữa hiển thị tổng hoặc chi tiết lát đang chọn.
class CategoryDonutChart extends StatefulWidget {
  const CategoryDonutChart({
    super.key,
    required this.slices,
    required this.total,
    this.selectedIndex,
    this.onSliceSelected,
    this.size = 216,
    this.strokeRatio = 0.15,
  });

  final List<CategorySlice> slices;
  final double total;
  final int? selectedIndex;
  final ValueChanged<int?>? onSliceSelected;
  final double size;
  final double strokeRatio;

  @override
  State<CategoryDonutChart> createState() => _CategoryDonutChartState();
}

class _CategoryDonutChartState extends State<CategoryDonutChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.chart,
  );

  static const double _gap = 0.045;

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant CategoryDonutChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool changed = oldWidget.slices.length != widget.slices.length ||
        oldWidget.total != widget.total;
    if (changed) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap(Offset position) {
    if (widget.slices.isEmpty || widget.onSliceSelected == null) return;

    final Offset center = Offset(widget.size / 2, widget.size / 2);
    final Offset delta = position - center;
    final double distance = delta.distance;
    final double stroke = widget.size * widget.strokeRatio;
    final double outer = widget.size / 2 - 6;
    final double inner = outer - stroke - 10;
    if (distance < inner || distance > outer + 8) {
      widget.onSliceSelected!(null);
      return;
    }

    double angle = math.atan2(delta.dy, delta.dx);
    // Đưa góc về hệ bắt đầu từ -pi/2 (đỉnh).
    angle = (angle + math.pi / 2) % (2 * math.pi);
    if (angle < 0) angle += 2 * math.pi;

    final double available = 2 * math.pi - _gap * (widget.slices.length - 1);
    double cursor = 0;
    for (int index = 0; index < widget.slices.length; index++) {
      final double share = widget.total == 0
          ? 0
          : widget.slices[index].amount / widget.total;
      final double extent = share * available;
      if (angle >= cursor && angle <= cursor + extent) {
        widget.onSliceSelected!(widget.selectedIndex == index ? null : index);
        return;
      }
      cursor += extent + _gap;
    }
    widget.onSliceSelected!(null);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: GestureDetector(
        onTapUp: (TapUpDetails details) => _handleTap(details.localPosition),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, Widget? _) {
            final double progress = kAppEmphasisCurve.transform(_controller.value);
            return Stack(
              alignment: Alignment.center,
              children: <Widget>[
                CustomPaint(
                  size: Size.square(widget.size),
                  painter: _DonutPainter(
                    slices: widget.slices,
                    total: widget.total,
                    progress: progress,
                    selectedIndex: widget.selectedIndex,
                    gap: _gap,
                    strokeRatio: widget.strokeRatio,
                  ),
                ),
                _CenterLabel(
                  slices: widget.slices,
                  total: widget.total,
                  selectedIndex: widget.selectedIndex,
                  progress: progress,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CenterLabel extends StatelessWidget {
  const _CenterLabel({
    required this.slices,
    required this.total,
    required this.selectedIndex,
    required this.progress,
  });

  final List<CategorySlice> slices;
  final double total;
  final int? selectedIndex;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final CategorySlice? selected = selectedIndex != null &&
            selectedIndex! >= 0 &&
            selectedIndex! < slices.length
        ? slices[selectedIndex!]
        : null;

    final String value = CurrencyFormatter.thousands(
      (selected?.amount ?? total) * progress,
    );
    final String label = selected != null
        ? selected.category.label
        : 'Tổng chi tiêu';
    final String? shareText = selected != null
        ? '${(selected.share * 100).toStringAsFixed(1)}% • ${selected.count} giao dịch'
        : null;

    return AnimatedSwitcher(
      duration: AppDurations.medium,
      transitionBuilder: (Widget child, Animation<double> animation) =>
          FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: Column(
        key: ValueKey<String>('${label}_$value'),
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$value ₫',
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.6,
            ),
          ),
          if (shareText != null) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              shareText,
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.slices,
    required this.total,
    required this.progress,
    required this.selectedIndex,
    required this.gap,
    required this.strokeRatio,
  });

  final List<CategorySlice> slices;
  final double total;
  final double progress;
  final int? selectedIndex;
  final double gap;
  final double strokeRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double stroke = size.width * strokeRatio;
    final double radius = size.width / 2 - stroke / 2 - 6;
    final Rect rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = Colors.white.withValues(alpha: 0.05),
    );

    if (slices.isEmpty || total <= 0) return;

    final double available = 2 * math.pi - gap * (slices.length - 1);
    double cursor = -math.pi / 2;

    for (int index = 0; index < slices.length; index++) {
      final CategorySlice slice = slices[index];
      final double extent = (slice.amount / total) * available;
      final double sweep = extent * progress;
      final bool selected = selectedIndex == index;
      final bool dimmed = selectedIndex != null && !selected;

      if (sweep > 0.004) {
        final Color base = slice.category.color;
        final Color color = dimmed ? base.withValues(alpha: 0.32) : base;

        if (selected) {
          canvas.drawArc(
            rect.inflate(1),
            cursor,
            sweep,
            false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = stroke + 12
              ..strokeCap = StrokeCap.round
              ..color = color.withValues(alpha: 0.28)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
          );
        }

        canvas.drawArc(
          rect,
          cursor,
          sweep,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = selected ? stroke + 6 : stroke
            ..strokeCap = StrokeCap.round
            ..color = color,
        );
      }

      cursor += extent + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.total != total ||
        oldDelegate.slices != slices;
  }
}
