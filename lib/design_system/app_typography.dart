import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Owl 设计系统 - 字体规范
///
/// 使用系统默认字体栈（San Francisco / Roboto / 思源黑体）
/// 中文优先显示，跨平台一致性
abstract final class AppTypography {
  static const String _fontFamily = ''; // 使用系统默认

  /// 页面大标题 - 20sp / 600
  static const TextStyle displaySmall = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 28 / 20,
    color: AppColors.textPrimary,
  );

  /// 分区标题 - 18sp / 600
  static const TextStyle titleLarge = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 26 / 18,
    color: AppColors.textPrimary,
  );

  /// 卡片标题 - 16sp / 600
  static const TextStyle titleMedium = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 24 / 16,
    color: AppColors.textPrimary,
  );

  /// 正文内容 - 16sp / 400
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 24 / 16,
    color: AppColors.textSecondary,
  );

  /// 次要文本/摘要 - 14sp / 400
  static const TextStyle bodyMedium = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 20 / 14,
    color: AppColors.textSecondary,
  );

  /// 辅助提示文本 - 12sp / 400
  static const TextStyle bodySmall = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 18 / 12,
    color: AppColors.textTertiary,
  );

  /// 按钮文本 - 16sp / 500
  static const TextStyle labelLarge = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 24 / 16,
    color: AppColors.textPrimary,
  );

  /// 标签/Chip 文本 - 13sp / 500
  static const TextStyle labelMedium = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 18 / 13,
    color: AppColors.textSecondary,
  );

  /// 代码块文本 - 14sp / 400
  static const TextStyle code = TextStyle(
    fontFamily: 'monospace',
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 20 / 14,
    color: AppColors.textSecondary,
  );

  /// 对话消息文本 - 15sp / 400
  static const TextStyle chatMessage = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 22 / 15,
    color: AppColors.textPrimary,
  );

  /// 对话消息中的链接/Wiki内链
  static const TextStyle chatLink = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 22 / 15,
    color: AppColors.primary,
  );
}
