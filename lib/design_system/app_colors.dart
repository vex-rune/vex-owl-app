import 'package:flutter/material.dart';

/// Owl 设计系统 - 颜色系统（支持日 / 夜双主题）
///
/// 设计原则：
/// - 颜色全部通过 token 化 [AppSemanticColors] 暴露，避免硬编码
/// - 静态 [AppColors] 类保留为**深色主题兼容色**（旧代码引用不会断）
/// - 推荐新代码使用 `context.semanticColors` 访问当前主题色
/// - 主色：青色系（Cyan）—— 适配"科技感 Owl"品牌定位
abstract final class AppColors {
  // ═══════════════════════════════════════════
  //  静态常量（深色主题默认值，向后兼容）
  //  新代码请使用 [AppSemanticColors]
  // ═══════════════════════════════════════════

  // ── 主色调（青色/Cyan） ──
  static const Color primary = Color(0xFF00D4AA);
  static const Color primaryLight = Color(0xFF00F0C0);
  static const Color primaryDark = Color(0xFF00A88A);

  // ── 辅助色 ──
  static const Color accent = Color(0xFF4B7BEC);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color orange = Color(0xFFFFA726);
  static const Color error = Color(0xFFEF4444);

  // ── 深色主题背景 ──
  static const Color background = Color(0xFF080C15);
  static const Color surface = Color(0xFF0F1520);
  static const Color surfaceVariant = Color(0xFF141C2B);

  // ── 文字（深色） ──
  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFFB0BEC5);
  static const Color textTertiary = Color(0xFF6B7B8D);
  static const Color textDisabled = Color(0xFF455566);

  // ── 边框/分割 ──
  static const Color divider = Color(0xFF1A2235);
  static const Color border = Color(0xFF1E293B);
  static const Color borderFocus = Color(0xFF00D4AA);

  // ── 玻璃质感 ──
  static const Color glassBackground = Color(0x1A1A2E40);
  static const Color glassBorder = Color(0x3300D4AA);

  // ── 对话气泡 ──
  static const Color userBubble = Color(0xFF1A3A6E);
  static const Color aiBubble = Color(0xFF111827);

  // ── 发光色 ──
  static const Color glowCyan = Color(0x4000D4AA);
  static const Color glowBlue = Color(0x304B7BEC);

  // ── 渐变（保持兼容） ──
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF00D4AA), Color(0xFF4B7BEC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient userBubbleGradient = LinearGradient(
    colors: [Color(0xFF00B894), Color(0xFF0984E3)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const RadialGradient backgroundGradient = RadialGradient(
    center: Alignment(0.0, -0.8),
    radius: 1.2,
    colors: [Color(0x1A00D4AA), Color(0xFF080C15)],
  );
}

// ══════════════════════════════════════════════════════════════════
//  主题感知颜色（推荐使用）
// ══════════════════════════════════════════════════════════════════

/// 主题感知的语义化颜色调色板。
///
/// 通过 [ThemeData.extensions] 注入到主题中。
/// 在 widget 中通过 [AppSemanticColors.of] / `context.semanticColors` 获取当前主题色。
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.brightness,
    required this.primary,
    required this.primarySoft,
    required this.onPrimary,
    required this.accent,
    required this.success,
    required this.warning,
    required this.error,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.glassBackground,
    required this.glassBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.divider,
    required this.border,
    required this.borderFocus,
    required this.userBubble,
    required this.aiBubble,
    required this.codeBackground,
    required this.glowPrimary,
    required this.glowAccent,
    required this.userBubbleGradient,
    required this.primaryGradient,
  });

  /// 当前主题亮度（用于自动选择颜色上下文）
  final Brightness brightness;

  // ── 主色 ──
  final Color primary;
  final Color primarySoft;
  final Color onPrimary;

  // ── 状态色 ──
  final Color accent;
  final Color success;
  final Color warning;
  final Color error;

  // ── 背景层 ──
  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color glassBackground;
  final Color glassBorder;

  // ── 文字 ──
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textDisabled;

  // ── 边框/分割 ──
  final Color divider;
  final Color border;
  final Color borderFocus;

  // ── 气泡 ──
  final Color userBubble;
  final Color aiBubble;
  final Color codeBackground;

  // ── 发光 ──
  final Color glowPrimary;
  final Color glowAccent;

  // ── 渐变 ──
  final LinearGradient userBubbleGradient;
  final LinearGradient primaryGradient;

  // ═══════════════════════════════════════════
  //  浅色主题（白天）
  // ═══════════════════════════════════════════
  static const AppSemanticColors light = AppSemanticColors(
    brightness: Brightness.light,

    // 主色：青色 → 在白底下饱和度提升以保证对比度
    primary: Color(0xFF009B82),       // 略深的青色（白底可读性）
    primarySoft: Color(0xFFE0F7F2),   // 浅薄荷背景
    onPrimary: Colors.white,

    // 状态色
    accent: Color(0xFF3B6EE0),
    success: Color(0xFF059669),
    warning: Color(0xFFD97706),
    error: Color(0xFFDC2626),

    // 背景：白底 + 极浅灰
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF7F9FC),       // 卡片底
    surfaceVariant: Color(0xFFEEF1F6), // 输入框 / 次级面板
    glassBackground: Color(0x66FFFFFF),
    glassBorder: Color(0x22009B82),

    // 文字：黑灰梯度
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF475569),
    textTertiary: Color(0xFF94A3B8),
    textDisabled: Color(0xFFCBD5E1),

    // 边框：淡灰
    divider: Color(0xFFE2E8F0),
    border: Color(0xFFE2E8F0),
    borderFocus: Color(0xFF009B82),

    // 气泡
    userBubble: Color(0xFFEEF4FF),
    aiBubble: Color(0xFFF1F5F9),
    codeBackground: Color(0xFFF1F5F9),

    // 发光
    glowPrimary: Color(0x33009B82),
    glowAccent: Color(0x223B6EE0),

    // 渐变
    userBubbleGradient: LinearGradient(
      colors: [Color(0xFF009B82), Color(0xFF3B6EE0)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    primaryGradient: LinearGradient(
      colors: [Color(0xFF009B82), Color(0xFF3B6EE0)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );

  // ═══════════════════════════════════════════
  //  深色主题（夜晚）— 保留原科技感风格
  // ═══════════════════════════════════════════
  static const AppSemanticColors dark = AppSemanticColors(
    brightness: Brightness.dark,

    primary: Color(0xFF00D4AA),
    primarySoft: Color(0x1A00D4AA),
    onPrimary: Color(0xFF080C15),

    accent: Color(0xFF4B7BEC),
    success: Color(0xFF10B981),
    warning: Color(0xFFF59E0B),
    error: Color(0xFFEF4444),

    background: Color(0xFF080C15),
    surface: Color(0xFF0F1520),
    surfaceVariant: Color(0xFF141C2B),
    glassBackground: Color(0x1A1A2E40),
    glassBorder: Color(0x3300D4AA),

    textPrimary: Color(0xFFF1F5F9),
    textSecondary: Color(0xFFB0BEC5),
    textTertiary: Color(0xFF6B7B8D),
    textDisabled: Color(0xFF455566),

    divider: Color(0xFF1A2235),
    border: Color(0xFF1E293B),
    borderFocus: Color(0xFF00D4AA),

    userBubble: Color(0xFF1A3A6E),
    aiBubble: Color(0xFF111827),
    codeBackground: Color(0xFF141C2B),

    glowPrimary: Color(0x4000D4AA),
    glowAccent: Color(0x304B7BEC),

    userBubbleGradient: LinearGradient(
      colors: [Color(0xFF00B894), Color(0xFF0984E3)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    primaryGradient: LinearGradient(
      colors: [Color(0xFF00D4AA), Color(0xFF4B7BEC)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );

  // ═══════════════════════════════════════════
  //  主题访问
  // ═══════════════════════════════════════════

  /// 从 [BuildContext] 取当前主题的语义色。
  /// 未注入主题时回退到深色调色板。
  static AppSemanticColors of(BuildContext context) {
    final ext = Theme.of(context).extension<AppSemanticColors>();
    return ext ?? dark;
  }

  /// 当前主题是否为亮色
  static bool isLight(BuildContext context) =>
      of(context).brightness == Brightness.light;

  // ═══ ThemeExtension 接口实现（lerp 用于主题切换动画） ═══
  @override
  AppSemanticColors copyWith({
    Brightness? brightness,
    Color? primary,
    Color? primarySoft,
    Color? onPrimary,
    Color? accent,
    Color? success,
    Color? warning,
    Color? error,
    Color? background,
    Color? surface,
    Color? surfaceVariant,
    Color? glassBackground,
    Color? glassBorder,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textDisabled,
    Color? divider,
    Color? border,
    Color? borderFocus,
    Color? userBubble,
    Color? aiBubble,
    Color? codeBackground,
    Color? glowPrimary,
    Color? glowAccent,
    LinearGradient? userBubbleGradient,
    LinearGradient? primaryGradient,
  }) {
    return AppSemanticColors(
      brightness: brightness ?? this.brightness,
      primary: primary ?? this.primary,
      primarySoft: primarySoft ?? this.primarySoft,
      onPrimary: onPrimary ?? this.onPrimary,
      accent: accent ?? this.accent,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      glassBackground: glassBackground ?? this.glassBackground,
      glassBorder: glassBorder ?? this.glassBorder,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textDisabled: textDisabled ?? this.textDisabled,
      divider: divider ?? this.divider,
      border: border ?? this.border,
      borderFocus: borderFocus ?? this.borderFocus,
      userBubble: userBubble ?? this.userBubble,
      aiBubble: aiBubble ?? this.aiBubble,
      codeBackground: codeBackground ?? this.codeBackground,
      glowPrimary: glowPrimary ?? this.glowPrimary,
      glowAccent: glowAccent ?? this.glowAccent,
      userBubbleGradient: userBubbleGradient ?? this.userBubbleGradient,
      primaryGradient: primaryGradient ?? this.primaryGradient,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      primary: Color.lerp(primary, other.primary, t)!,
      primarySoft: Color.lerp(primarySoft, other.primarySoft, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      glassBackground:
          Color.lerp(glassBackground, other.glassBackground, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderFocus: Color.lerp(borderFocus, other.borderFocus, t)!,
      userBubble: Color.lerp(userBubble, other.userBubble, t)!,
      aiBubble: Color.lerp(aiBubble, other.aiBubble, t)!,
      codeBackground: Color.lerp(codeBackground, other.codeBackground, t)!,
      glowPrimary: Color.lerp(glowPrimary, other.glowPrimary, t)!,
      glowAccent: Color.lerp(glowAccent, other.glowAccent, t)!,
      userBubbleGradient: t < 0.5 ? userBubbleGradient : other.userBubbleGradient,
      primaryGradient: t < 0.5 ? primaryGradient : other.primaryGradient,
    );
  }
}

/// BuildContext 扩展：便捷访问语义色
extension AppSemanticColorsX on BuildContext {
  AppSemanticColors get semanticColors => AppSemanticColors.of(this);
  bool get isLight => AppSemanticColors.isLight(this);
}