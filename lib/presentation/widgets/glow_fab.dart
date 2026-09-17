import 'package:flutter/material.dart';
import '../../design_system/design_system.dart';

/// 发光浮动操作按钮
///
/// 参考设计稿中右下角带青色光晕的圆形 FAB，
/// 支持渐变背景和发光阴影。
class GlowFab extends StatelessWidget {
  const GlowFab({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = AppSpacing.fabSize,
    this.mini = false,
    this.heroTag,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final double size;
  final bool mini;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    final effectiveSize = mini ? AppSpacing.fabSizeSmall : size;

    return SizedBox(
      width: effectiveSize,
      height: effectiveSize,
      child: FloatingActionButton(
        onPressed: onPressed,
        heroTag: heroTag,
        elevation: 0,
        highlightElevation: 0,
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        shape: CircleBorder(
          side: BorderSide(
            color: c.primary.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Icon(icon, size: mini ? 20 : 24),
      ),
    );
  }
}
