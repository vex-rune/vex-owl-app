import 'package:flutter/material.dart';
import '../../design_system/design_system.dart';

/// Wiki 文件列表项
///
/// 参考设计稿中 Wiki 目录的文件卡片效果：
/// 深色背景 + 文件图标 + 标题/摘要 + 操作按钮。
enum WikiFileType {
  folder,
  wiki,
  raw,
  indexFile,
  schema,
  profileFile,
  todoFile,
  sessionFile,
  conceptFile,
}

class WikiFileTile extends StatelessWidget {
  const WikiFileTile({
    super.key,
    required this.name,
    required this.fileType,
    this.subtitle,
    this.modificationTime,
    this.onTap,
    this.onLongPress,
    this.trailing,
  });

  final String name;
  final WikiFileType fileType;
  final String? subtitle;
  final String? modificationTime;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.pageHorizontal,
          vertical: 4,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: c.border, width: 0.5),
        ),
        child: Row(
          children: [
            // 文件类型图标
            _buildIcon(c),
            const SizedBox(width: AppSpacing.md),
            // 文件信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: AppTypography.bodyLarge.copyWith(
                      color: c.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                  if (modificationTime != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      modificationTime!,
                      style: AppTypography.bodySmall.copyWith(fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
            // 操作按钮
            if (trailing case final t?) t,
          ],
        ),
      ),
    );
  }

  Widget _buildIcon(AppSemanticColors c) {
    final (icon, color) = switch (fileType) {
      WikiFileType.folder => (Icons.folder_outlined, c.warning),
      WikiFileType.wiki => (Icons.article_outlined, c.primary),
      WikiFileType.raw => (Icons.description_outlined, c.accent),
      WikiFileType.indexFile => (Icons.list_alt_outlined, c.primary),
      WikiFileType.schema => (Icons.rule_outlined, c.warning),
      WikiFileType.profileFile => (Icons.person_outline, c.accent),
      WikiFileType.todoFile => (Icons.check_box_outlined, c.warning),
      WikiFileType.sessionFile => (Icons.chat_bubble_outline, c.primary),
      WikiFileType.conceptFile => (Icons.lightbulb_outline, c.success),
    };

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }
}
