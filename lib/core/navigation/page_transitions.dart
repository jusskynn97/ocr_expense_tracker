import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Route trượt lên + fade, dùng cho các trang chi tiết (scanner, review...).
Route<T> slideUpRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (_, Animation<double> animation, Animation<double> secondary,
        Widget child) {
      final CurvedAnimation curved =
          CurvedAnimation(parent: animation, curve: kAppEmphasisCurve);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.06),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Route fade + scale nhẹ, dùng cho các trang dạng "modal".
Route<T> fadeScaleRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    opaque: false,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 360),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (_, Animation<double> animation, Animation<double> secondary,
        Widget child) {
      final CurvedAnimation curved =
          CurvedAnimation(parent: animation, curve: kAppCurve);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}
