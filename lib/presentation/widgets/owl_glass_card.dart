import 'package:flutter/material.dart';
import '../../design_system/design_system.dart';

/// 玻璃质感卡片
///
/// 参考设计稿中半透明深色面板 + 微弱发光边框的效果，
/// 用于 Wiki 目录项、设置项、信息面板等。
class OwlGlassCard extends StatelessWidget {
  const OwlGlassCard({
    super.key,
    this.child,
    this.padding,
    this.margin,
    this.borderColor,
    this.glowColor,
    this.onTap,
  });

  final Widget? child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? borderColor;
  final Color? glowColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    final effectiveBorderColor = borderColor ?? c.border;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: AppSpacing.durationFast),
        margin: margin,
        padding: padding ?? const EdgeInsets.all(AppSpacing.cardPadding),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: effectiveBorderColor, width: 0.5),
          boxShadow: glowColor != null
              ? [
                  BoxShadow(
                    color: glowColor!,
                    blurRadius: 16,
                    spreadRadius: -2,
                  ),
                ]
              : null,
        ),
        child: child,
      ),
    );
  }
}
