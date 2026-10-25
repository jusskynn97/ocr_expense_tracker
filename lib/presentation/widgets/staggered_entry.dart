import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Hiệu ứng xuất hiện so le (fade + trượt lên) cho các item trong danh sách.
class StaggeredEntry extends StatelessWidget {
  const StaggeredEntry({
    super.key,
    required this.index,
    required this.child,
    this.step = const Duration(milliseconds: 55),
    this.base = const Duration(milliseconds: 240),
    this.offset = 16,
  });

  final int index;
  final Widget child;
  final Duration step;
  final Duration base;
  final double offset;

  @override
  Widget build(BuildContext context) {
    final Duration total = base + step * index;
    final double start = (step.inMilliseconds * index) / total.inMilliseconds;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: total,
      curve: Interval(start.clamp(0.0, 0.85), 1, curve: kAppEmphasisCurve),
      builder: (BuildContext context, double value, Widget? inner) {
        return Opacity(
          opacity: value.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, offset * (1 - value)),
            child: inner,
          ),
        );
      },
      child: child,
    );
  }
}
