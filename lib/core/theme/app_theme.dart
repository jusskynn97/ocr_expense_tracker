import 'package:flutter/material.dart';

/// Bảng màu dùng chung cho toàn bộ ứng dụng.
class AppColors {
  const AppColors._();

  static const Color background = Color(0xFF070A13);
  static const Color backgroundSoft = Color(0xFF0D1223);
  static const Color surface = Color(0xFF131A2E);
  static const Color surfaceHigh = Color(0xFF1B2440);
  static const Color outline = Color(0x1FFFFFFF);

  static const Color primary = Color(0xFF6C7CFF);
  static const Color primaryDeep = Color(0xFF3D4BE0);
  static const Color mint = Color(0xFF22D3A8);
  static const Color sky = Color(0xFF4FC3F7);
  static const Color amber = Color(0xFFFFC46B);
  static const Color pink = Color(0xFFFF7AB6);
  static const Color lilac = Color(0xFFB388FF);
  static const Color danger = Color(0xFFFF6B6B);

  static const Color textPrimary = Color(0xFFF3F5FF);
  static const Color textSecondary = Color(0xFF97A1C2);
  static const Color textMuted = Color(0xFF616B8C);
}

/// Các gradient dùng lại nhiều nơi.
class AppGradients {
  const AppGradients._();

  static const LinearGradient primary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFF8391FF), Color(0xFF3D4BE0)],
  );

  static const LinearGradient mint = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFF39E8BE), Color(0xFF14A98A)],
  );

  static const LinearGradient sunset = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFFFFB86B), Color(0xFFFF6B8B)],
  );

  static const LinearGradient scene = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[Color(0xFF101733), Color(0xFF070A13), Color(0xFF070A13)],
    stops: <double>[0, 0.45, 1],
  );

  static LinearGradient glass = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      Colors.white.withValues(alpha: 0.10),
      Colors.white.withValues(alpha: 0.02),
    ],
  );
}

/// Bo góc & khoảng cách chuẩn.
class AppRadius {
  const AppRadius._();

  static const double sm = 12;
  static const double md = 18;
  static const double lg = 26;
  static const double xl = 34;
}

/// Thời lượng animation thống nhất giúp chuyển động "mượt" và đồng bộ.
class AppDurations {
  const AppDurations._();

  static const Duration fast = Duration(milliseconds: 180);
  static const Duration medium = Duration(milliseconds: 320);
  static const Duration slow = Duration(milliseconds: 620);
  static const Duration chart = Duration(milliseconds: 900);
}

/// Motion curve dùng chung (nhấn mạnh cảm giác tự nhiên).
const Curve kAppCurve = Curves.easeOutCubic;
const Curve kAppEmphasisCurve = Cubic(0.22, 1, 0.36, 1);

class AppTheme {
  const AppTheme._();

  static ThemeData get dark {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.mint,
      onSecondary: const Color(0xFF04231C),
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.danger,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      splashFactory: InkSparkle.splashFactory,
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
          color: AppColors.textPrimary,
        ),
        headlineSmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          color: AppColors.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          height: 1.35,
          color: AppColors.textSecondary,
        ),
        labelLarge: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
      visualDensity: VisualDensity.standard,
    );
  }
}
