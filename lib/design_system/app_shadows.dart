import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Owl 设计系统 - 阴影 & 发光效果（主题感知）
///
/// 所有阴影都从当前主题的 [AppSemanticColors] 取色，确保日 / 夜主题下都自然。
abstract final class AppShadows {
  /// 主题感知的主色发光 - 从 [BuildContext] 取色
  static List<BoxShadow> glowPrimary(BuildContext context) {
    final c = AppSemanticColors.of(context);
    return [
      BoxShadow(
        color: c.glowPrimary,
        blurRadius: 20,
        spreadRadius: -2,
      ),
    ];
  }

  /// 主题感知的蓝色发光
  static List<BoxShadow> glowAccent(BuildContext context) {
    final c = AppSemanticColors.of(context);
    return [
      BoxShadow(
        color: c.glowAccent,
        blurRadius: 16,
        spreadRadius: -2,
      ),
    ];
  }

  /// 卡片默认阴影 - 浅色用淡黑、深色用淡白
  static List<BoxShadow> card(BuildContext context) {
    final isLight = AppSemanticColors.isLight(context);
    return [
      BoxShadow(
        color: isLight
            ? Colors.black.withValues(alpha: 0.04)
            : Colors.white.withValues(alpha: 0.02),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ];
  }

  /// 浮层阴影 - 用于弹窗、底部弹出
  static List<BoxShadow> elevation(BuildContext context) {
    final isLight = AppSemanticColors.isLight(context);
    return [
      BoxShadow(
        color: isLight
            ? Colors.black.withValues(alpha: 0.12)
            : Colors.black.withValues(alpha: 0.4),
        blurRadius: 16,
        offset: const Offset(0, 4),
      ),
    ];
  }

  /// FAB 发光阴影
  static List<BoxShadow> fab(BuildContext context) {
    final c = AppSemanticColors.of(context);
    return [
      BoxShadow(
        color: c.glowPrimary,
        blurRadius: 24,
        spreadRadius: -4,
        offset: const Offset(0, 4),
      ),
    ];
  }

  /// 输入框聚焦发光
  static List<BoxShadow> inputFocus(BuildContext context) {
    final c = AppSemanticColors.of(context);
    return [
      BoxShadow(
        color: c.glowPrimary,
        blurRadius: 12,
        spreadRadius: -1,
      ),
    ];
  }

  // ═══ 保留旧静态常量（向后兼容） ═══

  /// [已弃用] 使用 [glowPrimary(context)]
  static const List<BoxShadow> glowCyan = [
    BoxShadow(
      color: AppColors.glowCyan,
      blurRadius: 20,
      spreadRadius: -2,
    ),
  ];

  /// [已弃用] 使用 [glowAccent(context)]
  static const List<BoxShadow> glowBlue = [
    BoxShadow(
      color: AppColors.glowBlue,
      blurRadius: 16,
      spreadRadius: -2,
    ),
  ];

  /// [已弃用] 使用 [card(context)]
  static const List<BoxShadow> card_ = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  /// [已弃用] 使用 [elevation(context)]
  static const List<BoxShadow> elevation_ = [
    BoxShadow(
      color: Color(0x33000000),
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
  ];

  /// [已弃用] 使用 [fab(context)]
  static const List<BoxShadow> fab_ = [
    BoxShadow(
      color: Color(0x5000D4AA),
      blurRadius: 24,
      spreadRadius: -4,
      offset: Offset(0, 4),
    ),
  ];

  /// [已弃用] 使用 [inputFocus(context)]
  static const List<BoxShadow> inputFocus_ = [
    BoxShadow(
      color: Color(0x3000D4AA),
      blurRadius: 12,
      spreadRadius: -1,
    ),
  ];
}