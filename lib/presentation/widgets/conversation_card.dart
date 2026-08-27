import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/model/conversation.dart';
import '../theme/app_theme.dart';

/// 对话卡片:HomePage 列表项。
class ConversationCard extends StatelessWidget {
  final Session conversation;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const ConversationCard({
    super.key,
    required this.conversation,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.space4,
            vertical: AppTheme.space3,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (conversation.pinned)
                    Padding(
                      padding: const EdgeInsets.only(right: AppTheme.space1),
                      child: Icon(
                        Icons.push_pin,
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      conversation.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.space1),
              Text(
                _preview(conversation),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppTheme.space2),
              Row(
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppTheme.space1),
                  Text(
                    '${(conversation.round * 2).clamp(1, 99)} 条消息',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: AppTheme.space3),
                  Icon(
                    Icons.schedule,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppTheme.space1),
                  Text(
                    _formatTime(conversation.updatedAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _preview(Session c) {
    return c.round == 0 ? '点击开始对话...' : '最近一轮:$c.round 条交互';
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays == 1) return '昨天';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return DateFormat('MM/dd').format(dt);
  }
}
