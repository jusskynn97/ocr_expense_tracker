import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';

/// Số tiền đếm tăng dần mỗi khi giá trị thay đổi.
class AnimatedCounter extends StatefulWidget {
  const AnimatedCounter({
    super.key,
    required this.value,
    this.style,
    this.suffix = ' ₫',
    this.duration = const Duration(milliseconds: 900),
    this.compact = false,
  });

  final double value;
  final TextStyle? style;
  final String suffix;
  final Duration duration;
  final bool compact;

  @override
  State<AnimatedCounter> createState() => _AnimatedCounterState();
}

class _AnimatedCounterState extends State<AnimatedCounter> {
  late double _from = widget.value;
  late double _to = widget.value;

  @override
  void didUpdateWidget(covariant AnimatedCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _from = oldWidget.value;
      _to = widget.value;
    }
  }

  String _format(double value) {
    if (widget.compact) return '${CurrencyFormatter.compact(value)}${widget.suffix}';
    return '${CurrencyFormatter.thousands(value)}${widget.suffix}';
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: _from, end: _to),
      duration: widget.duration,
      curve: kAppEmphasisCurve,
      builder: (BuildContext context, double value, _) {
        return Text(_format(value), style: widget.style);
      },
    );
  }
}
