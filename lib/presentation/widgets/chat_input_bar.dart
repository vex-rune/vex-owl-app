import 'package:flutter/material.dart';
import '../../design_system/design_system.dart';

/// 对话输入栏
///
/// 底部固定多行输入框 + 附件按钮 + 发送按钮，
/// 与首页底部输入条保持一致风格：圆角胶囊 + 紫色圆形发送按钮。
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
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) {
        setState(() => _hasText = hasText);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend?.call(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    final canSend = _hasText || widget.isStreaming;
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: c.background,
        border: Border(
          top: BorderSide(color: c.divider, width: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部模式 chips：模型 / 快速 / 深度分析（与首页保持一致）
          Row(
            children: [
              _buildPill(c, widget.modelName ?? '请配置模型',
                  Icons.auto_awesome_outlined,
                  hasDropdown: true),
              // const SizedBox(width: 8),
              // _buildPill(c, '快速', Icons.flash_on_outlined),
              // const SizedBox(width: 8),
              // _buildPill(c, '深度分析', Icons.psychology_outlined),
              const Spacer(),
              if (widget.tokenCount != null)
                Text(
                  '≈ ${widget.tokenCount}',
                  style:
                      TextStyle(fontSize: 11, color: c.textTertiary),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // 输入行
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(Icons.add, size: 24, color: c.textSecondary),
                onPressed: widget.onAttach,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: c.surfaceVariant,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: c.border, width: 0.5),
                  ),
                  child: TextField(
                    controller: _controller,
                    maxLines: 5,
                    minLines: 1,
                    textInputAction: TextInputAction.newline,
                    style: TextStyle(fontSize: 14, color: c.textPrimary),
                    decoration: InputDecoration(
                      hintText: '输入消息...',
                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: c.textTertiary,
                      ),
                      border: InputBorder.none,
                      isCollapsed: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onSubmitted:
                        widget.isStreaming ? null : (_) => _handleSend(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildSendButton(c, canSend),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPill(
    AppSemanticColors c,
    String label,
    IconData icon, {
    bool hasDropdown = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasDropdown) ...[
            Icon(icon, size: 12, color: c.primary),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: c.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (hasDropdown) ...[
            const SizedBox(width: 2),
            Icon(Icons.keyboard_arrow_down,
                size: 14, color: c.primary),
          ],
        ],
      ),
    );
  }

  Widget _buildSendButton(AppSemanticColors c, bool canSend) {
    return InkWell(
      onTap: canSend
          ? () {
              if (widget.isStreaming) {
                widget.onStop?.call();
              } else {
                _handleSend();
              }
            }
          : null,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: canSend ? c.primary : c.surfaceVariant,
          shape: BoxShape.circle,
          border: Border.all(
            color: canSend ? c.primary : c.border,
            width: 0.5,
          ),
        ),
        child: Icon(
          widget.isStreaming ? Icons.stop_rounded : Icons.send_rounded,
          size: 18,
          color: canSend ? c.onPrimary : c.textTertiary,
        ),
      ),
    );
  }
}