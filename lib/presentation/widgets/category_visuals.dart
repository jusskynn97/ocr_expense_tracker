import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/expense_category.dart';

/// Ánh xạ hình ảnh cho từng nhóm chi tiêu (giữ domain thuần Dart).
extension ExpenseCategoryVisuals on ExpenseCategory {
  IconData get icon {
    switch (this) {
      case ExpenseCategory.food:
        return Icons.ramen_dining_rounded;
      case ExpenseCategory.study:
        return Icons.auto_stories_rounded;
      case ExpenseCategory.travel:
        return Icons.commute_rounded;
      case ExpenseCategory.gear:
        return Icons.devices_other_rounded;
      case ExpenseCategory.entertainment:
        return Icons.movie_filter_rounded;
    }
  }

  Color get color {
    switch (this) {
      case ExpenseCategory.food:
        return AppColors.amber;
      case ExpenseCategory.study:
        return AppColors.sky;
      case ExpenseCategory.travel:
        return AppColors.mint;
      case ExpenseCategory.gear:
        return AppColors.lilac;
      case ExpenseCategory.entertainment:
        return AppColors.pink;
    }
  }

  LinearGradient get gradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          color,
          HSLColor.fromColor(color)
              .withLightness(
                (HSLColor.fromColor(color).lightness * 0.68).clamp(0.0, 1.0),
              )
              .toColor(),
        ],
      );

  /// Gradient mờ dùng cho nền/badge.
  LinearGradient get softGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          color.withValues(alpha: 0.28),
          color.withValues(alpha: 0.06),
        ],
      );
}
