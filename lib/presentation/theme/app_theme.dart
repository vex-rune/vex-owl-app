import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 全应用主题。
///
/// 浅色 / 暗色主题对称,基于 Material 3。所有颜色取自 [AppColors],
/// 间距、圆角、字号遵循 docs/UI设计.md § 2 的规范。
class AppTheme {
  AppTheme._();

  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 24;
  static const double space6 = 32;

  static const double radiusCard = 12;
  static const double radiusBubble = 16;
  static const double radiusBubbleCorner = 4;

  /// 浅色主题。
  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.lightPrimary,
      brightness: Brightness.light,
      surface: AppColors.lightSurface,
      onSurface: AppColors.lightOnSurface,
      surfaceContainerLowest: AppColors.lightSurface,
      surfaceContainerLow: AppColors.lightSurfaceContainerLow,
    );
    return _baseTheme(colorScheme).copyWith(
      scaffoldBackgroundColor: AppColors.lightSurface,
    );
  }

  /// 暗色主题。
  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.darkPrimary,
      brightness: Brightness.dark,
      surface: AppColors.darkSurface,
      onSurface: AppColors.darkOnSurface,
      surfaceContainerLowest: AppColors.darkSurface,
      surfaceContainerLow: AppColors.darkSurfaceContainerLow,
    );
    return _baseTheme(colorScheme).copyWith(
      scaffoldBackgroundColor: AppColors.darkSurface,
    );
  }

  static ThemeData _baseTheme(ColorScheme colorScheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        color: colorScheme.surface,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: space4,
          vertical: space3,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusBubble),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusBubble),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusBubble),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
        ),
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        thickness: 0.6,
        space: 1,
      ),
      textTheme: const TextTheme(
        bodySmall: TextStyle(fontSize: 12),
        bodyMedium: TextStyle(fontSize: 14),
        bodyLarge: TextStyle(fontSize: 16),
        titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        headlineSmall: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
      ),
    );
  }
}