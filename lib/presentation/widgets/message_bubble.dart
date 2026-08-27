import 'package:flutter/material.dart';

import '../../core/model/message.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// 单条消息气泡。
///
/// 根据 [Message.type] 分发到对应的渲染实现:
/// * [MessageType.text] → 文本气泡(左/右按 [MessageRole] 分)
/// * [MessageType.system] → 系统提示(居中、弱化样式)
/// * [MessageType.thinking] → 思考块(可折叠)
/// * [MessageType.toolCall] → 工具调用列表
/// * [MessageType.plan] → 计划清单
/// * [MessageType.error] → 错误提示(警示色、错误图标、可展开详情)
class MessageBubble extends StatelessWidget {
  final Message message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    // 使用 effectiveType: 旧实例(热重载、跨版本)可能没设置 type,回落为 text。
    return switch (message.effectiveType) {
      MessageType.system => _SystemMessageBubble(message: message),
      MessageType.thinking => _ThinkingMessageBubble(message: message),
      MessageType.toolCall => _ToolCallMessageBubble(message: message),
      MessageType.plan => _PlanMessageBubble(message: message),
      MessageType.error => _ErrorMessageBubble(message: message),
      MessageType.text => switch (message.role) {
        MessageRole.user => _UserMessageBubble(message: message),
        _ => _AssistantMessageBubble(message: message),
      },
    };
  }
}

// ============================================================================
// 文本气泡 (text)
// ============================================================================

const _userBubbleBorderRadius = BorderRadius.only(
  topLeft: Radius.circular(AppTheme.radiusBubble),
  topRight: Radius.circular(AppTheme.radiusBubble),
  bottomLeft: Radius.circular(AppTheme.radiusBubble),
  bottomRight: Radius.circular(AppTheme.radiusBubbleCorner),
);

const _assistantBubbleBorderRadius = BorderRadius.only(
  topLeft: Radius.circular(AppTheme.radiusBubble),
  topRight: Radius.circular(AppTheme.radiusBubble),
  bottomLeft: Radius.circular(AppTheme.radiusBubbleCorner),
  bottomRight: Radius.circular(AppTheme.radiusBubble),
);

Color _userBubbleColor(ThemeData theme) => switch (theme.brightness) {
  Brightness.dark => AppColors.darkUserBubble,
  _ => AppColors.lightUserBubble,
};

Color _userForegroundColor(ThemeData theme) => switch (theme.brightness) {
  Brightness.dark => AppColors.darkOnBubbleUser,
  _ => AppColors.lightOnBubbleUser,
};

Color _assistantBubbleColor(ThemeData theme) => switch (theme.brightness) {
  Brightness.dark => AppColors.darkAiBubble,
  _ => AppColors.lightAiBubble,
};

Color _assistantForegroundColor(ThemeData theme) => switch (theme.brightness) {
  Brightness.dark => AppColors.darkOnBubbleAi,
  _ => AppColors.lightOnBubbleAi,
};

/// 消息气泡在当前主题下使用的视觉参数。
class _MessageBubbleStyle {
  const _MessageBubbleStyle({
    required this.backgroundColor,
    required this.foregroundColor,
    required this.borderRadius,
    required this.horizontalGroupAlignment,
    required this.contentAlignment,
    required this.maxWidth,
  });

  factory _MessageBubbleStyle.user(BuildContext context) {
    final theme = Theme.of(context);
    return _MessageBubbleStyle(
      backgroundColor: _userBubbleColor(theme),
      foregroundColor: _userForegroundColor(theme),
      borderRadius: _userBubbleBorderRadius,
      horizontalGroupAlignment: MainAxisAlignment.end,
      contentAlignment: CrossAxisAlignment.end,
      maxWidth: MediaQuery.sizeOf(context).width * 0.75,
    );
  }

  factory _MessageBubbleStyle.assistant(BuildContext context) {
    final theme = Theme.of(context);
    return _MessageBubbleStyle(
      backgroundColor: _assistantBubbleColor(theme),
      foregroundColor: _assistantForegroundColor(theme),
      borderRadius: _assistantBubbleBorderRadius,
      horizontalGroupAlignment: MainAxisAlignment.start,
      contentAlignment: CrossAxisAlignment.start,
      maxWidth: MediaQuery.sizeOf(context).width * 0.82,
    );
  }

  final Color backgroundColor;
  final Color foregroundColor;
  final BorderRadius borderRadius;
  final MainAxisAlignment horizontalGroupAlignment;
  final CrossAxisAlignment contentAlignment;
  final double maxWidth;
}

/// 用户消息气泡。
class _UserMessageBubble extends StatelessWidget {
  const _UserMessageBubble({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final style = _MessageBubbleStyle.user(context);
    return _TextBubbleLayout(
      style: style,
      children: [
        Flexible(
          child: _TextContent(message: message, style: style),
        ),
        const SizedBox(width: AppTheme.space2),
        const _UserAvatar(),
      ],
    );
  }
}

/// 助手消息气泡。
class _AssistantMessageBubble extends StatelessWidget {
  const _AssistantMessageBubble({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final style = _MessageBubbleStyle.assistant(context);
    return _TextBubbleLayout(
      style: style,
      children: [
        const _AssistantAvatar(),
        const SizedBox(width: AppTheme.space2),
        Flexible(
          child: _TextContent(message: message, style: style),
        ),
      ],
    );
  }
}

/// 文本气泡的公共布局。
class _TextBubbleLayout extends StatelessWidget {
  const _TextBubbleLayout({required this.style, required this.children});

  final _MessageBubbleStyle style;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space4,
        vertical: AppTheme.space1,
      ),
      child: Row(
        mainAxisAlignment: style.horizontalGroupAlignment,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: children,
      ),
    );
  }
}

/// 文本正文 + 工具调用记录(用于 text 类型)。
class _TextContent extends StatelessWidget {
  const _TextContent({required this.message, required this.style});

  final Message message;
  final _MessageBubbleStyle style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final toolCalls = message.toolCalls;

    return Column(
      crossAxisAlignment: style.contentAlignment,
      children: [
        Container(
          constraints: BoxConstraints(maxWidth: style.maxWidth),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.space4,
            vertical: AppTheme.space3,
          ),
          decoration: BoxDecoration(
            color: style.backgroundColor,
            borderRadius: style.borderRadius,
          ),
          child: Text(
            message.content.isEmpty ? ' ' : message.content,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: style.foregroundColor,
              height: 1.45,
            ),
          ),
        ),
        if (toolCalls != null && toolCalls.isNotEmpty)
          _InlineToolCallChips(toolCalls: toolCalls),
      ],
    );
  }
}

/// 文本气泡下方的工具调用标签(紧凑样式)。
class _InlineToolCallChips extends StatelessWidget {
  const _InlineToolCallChips({required this.toolCalls});

  final List<ToolCallRecord> toolCalls;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.space1),
      child: Wrap(
        spacing: AppTheme.space1,
        children: [
          for (final toolCall in toolCalls)
            Chip(
              label: Text(toolCall.name),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// 系统提示气泡 (system)
// ============================================================================

/// 系统级提示(居中、弱化样式,无头像)。
class _SystemMessageBubble extends StatelessWidget {
  const _SystemMessageBubble({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space4,
        vertical: AppTheme.space2,
      ),
      child: Center(
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.9,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.space3,
            vertical: AppTheme.space2,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppTheme.radiusBubble),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppTheme.space2),
              Flexible(
                child: Text(
                  message.content,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 思考块气泡 (thinking)
// ============================================================================

/// 思考 / 推理过程:可折叠展示。
class _ThinkingMessageBubble extends StatefulWidget {
  const _ThinkingMessageBubble({required this.message});

  final Message message;

  @override
  State<_ThinkingMessageBubble> createState() => _ThinkingMessageBubbleState();
}

class _ThinkingMessageBubbleState extends State<_ThinkingMessageBubble> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = widget.message.thinkingContent ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space4,
        vertical: AppTheme.space1,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AssistantAvatar(),
          const SizedBox(width: AppTheme.space2),
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.82,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppTheme.radiusBubble),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () => setState(() => _expanded = !_expanded),
                    borderRadius: BorderRadius.circular(AppTheme.radiusBubble),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.space3,
                        vertical: AppTheme.space2,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.psychology_outlined,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: AppTheme.space2),
                          Text(
                            '思考过程',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            _expanded ? Icons.expand_less : Icons.expand_more,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_expanded && content.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppTheme.space3,
                        0,
                        AppTheme.space3,
                        AppTheme.space3,
                      ),
                      child: Text(
                        content,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 工具调用气泡 (toolCall)
// ============================================================================

/// 工具调用列表(整条消息的主体即为工具调用轨迹)。
class _ToolCallMessageBubble extends StatelessWidget {
  const _ToolCallMessageBubble({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final toolCalls = message.toolCalls ?? const [];

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space4,
        vertical: AppTheme.space1,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AssistantAvatar(),
          const SizedBox(width: AppTheme.space2),
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.82,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppTheme.radiusBubble),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppTheme.space3,
                      AppTheme.space2,
                      AppTheme.space3,
                      AppTheme.space1,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.build_outlined,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: AppTheme.space2),
                        Text(
                          '工具调用',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${toolCalls.length}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (var i = 0; i < toolCalls.length; i++)
                    _ToolCallRow(
                      toolCall: toolCalls[i],
                      isLast: i == toolCalls.length - 1,
                    ),
                  if (toolCalls.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppTheme.space3,
                        0,
                        AppTheme.space3,
                        AppTheme.space3,
                      ),
                      child: Text(
                        '(无工具调用记录)',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolCallRow extends StatelessWidget {
  const _ToolCallRow({required this.toolCall, required this.isLast});

  final ToolCallRecord toolCall;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.4,
                  ),
                ),
              ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space3,
        vertical: AppTheme.space2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.arrow_forward,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppTheme.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  toolCall.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (toolCall.output.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      toolCall.output,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 计划清单气泡 (plan)
// ============================================================================

/// 计划列表:每项带状态图标与勾选样式。
class _PlanMessageBubble extends StatelessWidget {
  const _PlanMessageBubble({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = message.planItems ?? const [];

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space4,
        vertical: AppTheme.space1,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AssistantAvatar(),
          const SizedBox(width: AppTheme.space2),
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.82,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppTheme.radiusBubble),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppTheme.space3,
                      AppTheme.space2,
                      AppTheme.space3,
                      AppTheme.space1,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.checklist_outlined,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: AppTheme.space2),
                        Text(
                          '执行计划',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _summary(items),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppTheme.space3,
                        0,
                        AppTheme.space3,
                        AppTheme.space3,
                      ),
                      child: Text(
                        '(暂无计划)',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    )
                  else
                    for (var i = 0; i < items.length; i++)
                      _PlanItemRow(
                        item: items[i],
                        isLast: i == items.length - 1,
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _summary(List<PlanItem> items) {
    if (items.isEmpty) return '';
    final done = items.where((i) => i.status == PlanItemStatus.done).length;
    return '$done/${items.length}';
  }
}

class _PlanItemRow extends StatelessWidget {
  const _PlanItemRow({required this.item, required this.isLast});

  final PlanItem item;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finished =
        item.status == PlanItemStatus.done ||
        item.status == PlanItemStatus.skipped;
    final color = finished
        ? theme.colorScheme.outline
        : theme.colorScheme.onSurface;

    return Container(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.4,
                  ),
                ),
              ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space3,
        vertical: AppTheme.space2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            switch (item.status) {
              PlanItemStatus.done => Icons.check_circle,
              PlanItemStatus.inProgress => Icons.radio_button_checked,
              PlanItemStatus.skipped => Icons.remove_circle_outline,
              PlanItemStatus.pending => Icons.radio_button_unchecked,
            },
            size: 18,
            color: item.status == PlanItemStatus.inProgress
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppTheme.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: color,
                    decoration: finished ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (item.description != null && item.description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      item.description!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 错误提示气泡 (error)
// ============================================================================

/// 错误提示:承载对话失败 / 取消的错误描述。
///
/// 参考 [MessageType.system] 的居中弱化布局,但用 [AppColors.error] 警示色。
/// 点击可展开完整错误详情,便于自助排查。
class _ErrorMessageBubble extends StatefulWidget {
  const _ErrorMessageBubble({required this.message});

  final Message message;

  @override
  State<_ErrorMessageBubble> createState() => _ErrorMessageBubbleState();
}

class _ErrorMessageBubbleState extends State<_ErrorMessageBubble> {
  bool _expanded = false;

  /// 从错误文本中提取一段用户可读的短描述(去掉 "Exception:" 前缀、OpenAI/Dio 详细字段等)。
  String _shortMessage(String raw) {
    var text = raw.trim();
    // 去掉常见的异常后缀(如 `OpenAIClientException({...})` 样式)
    final paren = text.indexOf('({');
    if (paren > 0) {
      text = text.substring(0, paren).trim();
    }
    // 去掉已知的 client 类前缀
    for (final prefix in const [
      'OpenAIClientException: ',
      'ChatOpenAIException: ',
      'SocketException: ',
      'HttpException: ',
      'FormatException: ',
      'Exception: ',
      'Error: ',
    ]) {
      if (text.startsWith(prefix)) {
        text = text.substring(prefix.length).trim();
      }
    }
    if (text.length > 80) {
      text = '${text.substring(0, 80)}…';
    }
    return text.isEmpty ? '请求出错' : text;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final raw = widget.message.content;
    final short = _shortMessage(raw);

    final bg = isDark
        ? AppColors.error.withValues(alpha: 0.14)
        : AppColors.error.withValues(alpha: 0.08);
    final border = AppColors.error.withValues(alpha: isDark ? 0.45 : 0.30);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space4,
        vertical: AppTheme.space2,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.9,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppTheme.radiusBubble),
              border: Border.all(color: border),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                borderRadius: BorderRadius.circular(AppTheme.radiusBubble),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.space3,
                    vertical: AppTheme.space2,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 16,
                            color: AppColors.error,
                          ),
                          const SizedBox(width: AppTheme.space2),
                          Text(
                            '请求出错',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: AppColors.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: AppTheme.space2),
                          Flexible(
                            child: Text(
                              short,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppTheme.space2),
                          Icon(
                            _expanded ? Icons.expand_less : Icons.expand_more,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                      if (_expanded && raw.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: AppTheme.space2),
                          child: SelectableText(
                            raw,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontFamily: 'monospace',
                              height: 1.4,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 头像
// ============================================================================

/// 用户消息头像。
class _UserAvatar extends StatelessWidget {
  const _UserAvatar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CircleAvatar(
      radius: 16,
      backgroundColor: theme.colorScheme.primaryContainer,
      child: Icon(
        Icons.person_outline,
        size: 18,
        color: theme.colorScheme.onPrimaryContainer,
      ),
    );
  }
}

/// 助手消息头像。
class _AssistantAvatar extends StatelessWidget {
  const _AssistantAvatar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CircleAvatar(
      radius: 16,
      backgroundColor: theme.colorScheme.secondaryContainer,
      child: const Padding(
        padding: const EdgeInsets.all(0),
        child: Image(image: AssetImage('assets/logo/logo.png')),
      ),
    );
  }
}
