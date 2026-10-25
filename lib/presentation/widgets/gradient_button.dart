import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'app_tap_scale.dart';

/// Nút gradient bo tròn, có trạng thái loading và hiệu ứng nhấn.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.gradient,
    this.height = 56,
    this.expand = true,
    this.foreground = Colors.white,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final Gradient? gradient;
  final double height;
  final bool expand;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null && !loading;

    return SizedBox(
      height: height,
      width: expand ? double.infinity : null,
      child: AnimatedOpacity(
        duration: AppDurations.fast,
        opacity: enabled ? 1 : 0.6,
        child: AppTapScale(
          onTap: enabled ? onPressed : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: gradient ?? AppGradients.primary,
              borderRadius: BorderRadius.circular(height / 2),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: (gradient == null
                          ? AppColors.primary
                          : AppColors.primaryDeep)
                      .withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Center(
              child: AnimatedSwitcher(
                duration: AppDurations.fast,
                child: loading
                    ? const SizedBox(
                        key: ValueKey<String>('loading'),
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Row(
                        key: const ValueKey<String>('label'),
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (icon != null) ...<Widget>[
                            Icon(icon, size: 19, color: foreground),
                            const SizedBox(width: 10),
                          ],
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              color: foreground,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
