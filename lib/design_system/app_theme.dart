import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';
import 'app_spacing.dart';

/// Owl 应用全局 ThemeData（支持日 / 夜双主题）
///
/// 设计原则：
/// - **light/dark 完整对称**：每个组件样式都提供两个主题版本
/// - 颜色全部通过 [AppSemanticColors] token 化，自动适配当前主题
/// - 状态栏/导航栏图标亮度自动反转
class AppTheme {
  AppTheme._();

  // ═══════════════════════════════════════════
  //  浅色主题（白天）
  // ═══════════════════════════════════════════
  static ThemeData get light {
    final c = AppSemanticColors.light;
    final colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: c.primary,
      onPrimary: c.onPrimary,
      primaryContainer: c.primarySoft,
      onPrimaryContainer: c.primary,
      secondary: c.accent,
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFE0EBFF),
      onSecondaryContainer: c.accent,
      surface: c.surface,
      onSurface: c.textPrimary,
      surfaceContainerHighest: c.surfaceVariant,
      error: c.error,
      onError: Colors.white,
      outline: c.border,
      outlineVariant: c.divider,
      shadow: Colors.black.withValues(alpha: 0.08),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: c.background,
      extensions: [c],
      // ── AppBar ──
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: c.textPrimary,
        ),
        iconTheme: IconThemeData(
          color: c.textSecondary,
          size: AppSpacing.iconSize,
        ),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.white,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
      ),
      // ── Bottom Navigation Bar ──
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: c.surface,
        selectedItemColor: c.primary,
        unselectedItemColor: c.textTertiary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        unselectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        elevation: 0,
        indicatorColor: c.primary.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: c.primary,
            );
          }
          return TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: c.textTertiary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: c.primary, size: AppSpacing.iconSize);
          }
          return IconThemeData(
              color: c.textTertiary, size: AppSpacing.iconSize);
        }),
      ),
      // ── Card ──
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          side: BorderSide(color: c.border, width: 0.5),
        ),
        margin: EdgeInsets.zero,
      ),
      // ── ListTile ──
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.sm,
        ),
        titleTextStyle: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: c.textPrimary,
        ),
        subtitleTextStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: c.textTertiary,
        ),
        iconColor: c.textSecondary,
      ),
      // ── Divider ──
      dividerTheme: DividerThemeData(
        color: c.divider,
        thickness: 0.5,
        space: 0,
      ),
      // ── Input Decoration ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: c.border, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: c.border, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: c.borderFocus, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: c.error, width: 1),
        ),
        hintStyle: TextStyle(fontSize: 15, color: c.textTertiary),
      ),
      // ── Elevated Button ──
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.primary,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base,
            vertical: AppSpacing.sm,
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      // ── Switch ──
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return c.textTertiary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return c.primary;
          }
          return c.surfaceVariant;
        }),
      ),
      // ── Chip ──
      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceVariant,
        selectedColor: c.primary.withValues(alpha: 0.12),
        side: BorderSide(color: c.border, width: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        labelStyle: TextStyle(fontSize: 13, color: c.textSecondary),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
      ),
      // ── Dialog ──
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          side: BorderSide(color: c.border, width: 0.5),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusLg),
          ),
        ),
      ),
      // ── Tooltip ──
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.textPrimary,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        textStyle: TextStyle(fontSize: 12, color: c.background),
      ),
      // ── Progress Indicator ──
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.primary,
        linearTrackColor: c.surfaceVariant,
      ),
      // ── SnackBar ──
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.textPrimary,
        contentTextStyle: TextStyle(fontSize: 14, color: c.background),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  深色主题（夜晚）— 保留原科技感
  // ═══════════════════════════════════════════
  static ThemeData get dark {
    final c = AppSemanticColors.dark;
    final colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: c.primary,
      onPrimary: c.onPrimary,
      primaryContainer: const Color(0xFF003D33),
      onPrimaryContainer: c.primary,
      secondary: c.accent,
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFF1E3A8A),
      onSecondaryContainer: c.accent,
      surface: c.surface,
      onSurface: c.textPrimary,
      surfaceContainerHighest: c.surfaceVariant,
      error: c.error,
      onError: Colors.white,
      outline: c.border,
      outlineVariant: c.divider,
      shadow: Colors.black.withValues(alpha: 0.5),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: c.background,
      extensions: [c],
      // ── AppBar ──
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: c.textPrimary,
        ),
        iconTheme: IconThemeData(
          color: c.textSecondary,
          size: AppSpacing.iconSize,
        ),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Color(0xFF080C15),
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: c.surface,
        selectedItemColor: c.primary,
        unselectedItemColor: c.textTertiary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        unselectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        elevation: 0,
        indicatorColor: c.primary.withValues(alpha: 0.15),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: c.primary,
            );
          }
          return TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: c.textTertiary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: c.primary, size: AppSpacing.iconSize);
          }
          return IconThemeData(
              color: c.textTertiary, size: AppSpacing.iconSize);
        }),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          side: BorderSide(color: c.border, width: 0.5),
        ),
        margin: EdgeInsets.zero,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.sm,
        ),
        titleTextStyle: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: c.textPrimary,
        ),
        subtitleTextStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: c.textTertiary,
        ),
        iconColor: c.textSecondary,
      ),
      dividerTheme: DividerThemeData(
        color: c.divider,
        thickness: 0.5,
        space: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: c.border, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: c.border, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: c.borderFocus, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: c.error, width: 1),
        ),
        hintStyle: TextStyle(fontSize: 15, color: c.textTertiary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.background,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.primary,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base,
            vertical: AppSpacing.sm,
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return c.textTertiary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return c.primary;
          }
          return c.surfaceVariant;
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceVariant,
        selectedColor: c.primary.withValues(alpha: 0.15),
        side: BorderSide(color: c.border, width: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        labelStyle: TextStyle(fontSize: 13, color: c.textSecondary),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          side: BorderSide(color: c.border, width: 0.5),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusLg),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.surfaceVariant,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(color: c.border, width: 0.5),
        ),
        textStyle: TextStyle(fontSize: 12, color: c.textSecondary),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.primary,
        linearTrackColor: c.surfaceVariant,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.surfaceVariant,
        contentTextStyle: TextStyle(fontSize: 14, color: c.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}