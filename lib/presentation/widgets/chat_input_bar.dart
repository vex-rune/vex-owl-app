import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 聊天输入区:多行输入框 + 发送按钮。
///
/// docs/UI设计.md § 3.3 描述:多行 TextField,minLines: 1 / maxLines: 6,
/// 自动扩展;发送按钮在空文本时禁用。
class ChatInputBar extends StatefulWidget {
  final Future<void> Function(String text) onSend;
  final bool enabled;

  const ChatInputBar({
    super.key,
    required this.onSend,
    this.enabled = true,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    await widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSend = _hasText && widget.enabled;

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppTheme.space3,
        AppTheme.space2,
        AppTheme.space3,
        AppTheme.space3 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              enabled: widget.enabled,
              minLines: 1,
              maxLines: 6,
              textInputAction: TextInputAction.newline,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                hintText: '输入消息...',
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: AppTheme.space2),
          Material(
            color: canSend
                ? theme.colorScheme.primary
                : theme.colorScheme.surfaceContainerHighest,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: canSend ? _send : null,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  Icons.arrow_upward_rounded,
                  color: canSend
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurfaceVariant,
                  size: 22,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}