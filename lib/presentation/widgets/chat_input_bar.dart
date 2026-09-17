import 'package:flutter/material.dart';
import '../../design_system/design_system.dart';

/// 对话输入栏
///
/// 底部固定多行输入框 + 附件按钮 + 发送按钮，
/// 参考设计稿中深色圆角输入框 + 青色发送按钮的布局。
class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    this.onSend,
    this.onAttach,
    this.tokenCount,
    this.isStreaming = false,
    this.onStop,
    this.providerName,
    this.modelName,
  });

  final ValueChanged<String>? onSend;
  final VoidCallback? onAttach;
  final int? tokenCount;
  final bool isStreaming;
  final VoidCallback? onStop;
  final String? providerName;
  final String? modelName;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) {
        setState(() => _hasText = hasText);
      }
    });
    _focusNode.addListener(() {
      if (_focusNode.hasFocus != _isFocused) {
        setState(() => _isFocused = _focusNode.hasFocus);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend?.call(text);
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    final canSend = _hasText || widget.isStreaming;
    return Container(
      padding: EdgeInsets.only(
        left: AppSpacing.base,
        right: AppSpacing.sm,
        top: AppSpacing.sm,
        bottom: MediaQuery.of(context).padding.bottom + AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(
          top: BorderSide(color: c.divider, width: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 状态行：左侧 Provider/Model，右侧 Token 计数
          if ((widget.providerName != null && widget.modelName != null) ||
              widget.tokenCount != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: [
                  if (widget.providerName != null && widget.modelName != null) ...[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.success,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${widget.providerName} · ${widget.modelName}',
                        style: AppTypography.bodySmall
                            .copyWith(color: c.textTertiary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (widget.tokenCount != null)
                    Text(
                      '≈ ${widget.tokenCount} tokens',
                      style: AppTypography.bodySmall.copyWith(
                        color: c.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
          // 输入行
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 附件按钮
              _IconButton(
                icon: Icons.add_circle_outline,
                onTap: widget.onAttach,
                tooltip: '附件',
              ),
              const SizedBox(width: AppSpacing.sm),
              // 输入框
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: AppSpacing.durationFast),
                  constraints: const BoxConstraints(minHeight: 44),
                  decoration: BoxDecoration(
                    color: c.surfaceVariant,
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusMd),
                    border: Border.all(
                      color: _isFocused
                          ? c.borderFocus
                          : c.border,
                      width: _isFocused ? 1.2 : 0.5,
                    ),
                    boxShadow: _isFocused ? AppShadows.inputFocus(context) : null,
                  ),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    maxLines: 5,
                    minLines: 1,
                    textInputAction: TextInputAction.newline,
                    style: AppTypography.bodyLarge.copyWith(
                      color: c.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: '输入消息...',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.base,
                        vertical: 10,
                      ),
                      hintStyle: AppTypography.bodyLarge.copyWith(
                        color: c.textTertiary,
                      ),
                    ),
                    onSubmitted: widget.isStreaming
                        ? null
                        : (_) => _handleSend(),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // 发送/停止按钮
              _SendButton(
                isStreaming: widget.isStreaming,
                enabled: canSend,
                onTap: widget.isStreaming
                    ? widget.onStop
                    : (_hasText ? _handleSend : null),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 圆形小图标按钮（带按压反馈）
class _IconButton extends StatefulWidget {
  const _IconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  State<_IconButton> createState() => _IconButtonState();
}

class _IconButtonState extends State<_IconButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 80),
    lowerBound: 0.0,
    upperBound: 0.08,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    final btn = GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) => _ctrl.reverse(),
      onTapCancel: () => _ctrl.reverse(),
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          return Transform.scale(
            scale: 1 - _ctrl.value,
            child: child,
          );
        },
        child: Container(
          width: 40,
          height: 40,
          margin: const EdgeInsets.only(bottom: 2),
          decoration: BoxDecoration(
            color: c.surfaceVariant,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: Border.all(color: c.border, width: 0.5),
          ),
          child: Icon(
            widget.icon,
            color: c.textSecondary,
            size: 22,
          ),
        ),
      ),
    );
    if (widget.tooltip != null) {
      return Tooltip(message: widget.tooltip!, child: btn);
    }
    return btn;
  }
}

/// 发送/停止按钮，带渐变和发光
class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.isStreaming,
    required this.enabled,
    required this.onTap,
  });

  final bool isStreaming;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: AppSpacing.durationFast),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          gradient: enabled ? c.primaryGradient : null,
          color: enabled ? null : c.surfaceVariant,
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          boxShadow: enabled ? AppShadows.glowPrimary(context) : null,
          border: Border.all(
            color: enabled
                ? c.primary.withValues(alpha: 0.4)
                : c.border,
            width: 0.5,
          ),
        ),
        child: Icon(
          isStreaming ? Icons.stop_rounded : Icons.arrow_upward_rounded,
          color: enabled ? c.onPrimary : c.textTertiary,
          size: 22,
        ),
      ),
    );
  }
}
