import 'package:flutter/material.dart';

/// 应用主题颜色。
///
/// 浅色与暗色主题完整对称。详见 docs/UI设计.md § 2.1。
class AppColors {
  AppColors._();

  // ---- 浅色主题 ----
  static const Color lightPrimary = Color(0xFF1F6FEB);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightOnSurface = Color(0xFF1A1A1A);
  static const Color lightSurfaceContainerLow = Color(0xFFF5F7FA);
  static const Color lightUserBubble = Color(0xFF1F6FEB);
  static const Color lightAiBubble = Color(0xFFEEF1F6);
  static const Color lightOnBubbleUser = Color(0xFFFFFFFF);
  static const Color lightOnBubbleAi = Color(0xFF1A1A1A);

  // ---- 暗色主题 ----
  static const Color darkPrimary = Color(0xFF7AA7FF);
  static const Color darkSurface = Color(0xFF121417);
  static const Color darkOnSurface = Color(0xFFE8E8E8);
  static const Color darkSurfaceContainerLow = Color(0xFF1E2127);
  static const Color darkUserBubble = Color(0xFF2E5BBA);
  static const Color darkAiBubble = Color(0xFF262A31);
  static const Color darkOnBubbleUser = Color(0xFFFFFFFF);
  static const Color darkOnBubbleAi = Color(0xFFE8E8E8);

  // ---- 通用语义色 ----
  static const Color error = Color(0xFFE53935);
  static const Color warning = Color(0xFFFFA000);
  static const Color success = Color(0xFF43A047);
}