import 'package:flutter/material.dart';
import '../../design_system/design_system.dart';

/// 分区面板（可折叠）
///
/// 参考设计稿中设置页的分组面板效果：
/// 深色卡片 + 区域标题 + 内部列表项。
class SectionPanel extends StatefulWidget {
  const SectionPanel({
    super.key,
    required this.title,
    required this.children,
    this.icon,
    this.initiallyExpanded = true,
    this.trailing,
  });

  final String title;
  final List<Widget> children;
  final IconData? icon;
  final bool initiallyExpanded;
  final Widget? trailing;

  @override
  State<SectionPanel> createState() => _SectionPanelState();
}

class _SectionPanelState extends State<SectionPanel>
    with SingleTickerProviderStateMixin {
  late bool _isExpanded;
  late AnimationController _controller;
  late Animation<double> _iconTurns;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _controller = AnimationController(
      duration: const Duration(milliseconds: AppSpacing.durationNormal),
      vsync: this,
      value: _isExpanded ? 1.0 : 0.0,
    );
    _iconTurns = _controller.drive(Tween(begin: 0.0, end: 0.5)
        .chain(CurveTween(curve: Curves.easeInOut)));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pageHorizontal,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: c.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          GestureDetector(
            onTap: _toggleExpanded,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.base,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  if (widget.icon != null) ...[
                    Icon(
                      widget.icon,
                      size: AppSpacing.iconSizeSm,
                      color: c.primary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Expanded(
                    child: Text(
                      widget.title,
                      style: AppTypography.titleMedium.copyWith(
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  if (widget.trailing case final t?) ...[
                    t,
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  RotationTransition(
                    turns: _iconTurns,
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: c.textTertiary,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 分割线
          if (_isExpanded) Divider(height: 0.5, color: c.divider),
          // 内容
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Column(children: widget.children),
            ),
            crossFadeState: _isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: AppSpacing.durationNormal),
          ),
        ],
      ),
    );
  }
}

/// SectionPanel 内的设置项行
class SectionItem extends StatelessWidget {
  const SectionItem({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    return InkWell(
      onTap: onTap,
      splashColor: c.primary.withValues(alpha: 0.05),
      highlightColor: c.primary.withValues(alpha: 0.03),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: c.textSecondary),
              const SizedBox(width: AppSpacing.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.bodyLarge.copyWith(
                      color: c.textPrimary,
                      fontSize: 15,
                    ),
                  ),
                  if (subtitle case final s?) ...[
                    const SizedBox(height: 2),
                    Text(
                      s,
                      style: AppTypography.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing case final t?) t,
          ],
        ),
      ),
    );
  }
}
