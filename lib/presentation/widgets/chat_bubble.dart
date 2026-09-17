import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/model/llm_tool_call.dart';
import '../../design_system/design_system.dart';

/// 对话消息气泡
///
/// 用户消息居右蓝色气泡，AI 消息居左暗色气泡。
/// AI 消息使用内置简易 Markdown 渲染（标题、列表、粗体、行内代码、代码块、引用），
/// 不依赖任何第三方 Markdown 库。
/// 支持流式打字效果指示、Wiki 引用标签、长按操作。
enum ChatBubbleRole { user, assistant }

class ChatBubble extends StatefulWidget {
  const ChatBubble({
    super.key,
    required this.role,
    required this.content,
    this.wikiRefs,
    this.isStreaming = false,
    this.onWikiRefTap,
    this.onLongPress,
    this.reasoning,
    this.toolCalls = const [],
  });

  final ChatBubbleRole role;
  final String content;
  final List<String>? wikiRefs;
  final bool isStreaming;
  final ValueChanged<String>? onWikiRefTap;
  final VoidCallback? onLongPress;

  /// 思考过程内容（仅 assistant 角色有意义）
  final String? reasoning;

  /// 本轮 assistant 请求的工具调用列表（仅 assistant 角色有意义）
  final List<LlmToolCall> toolCalls;

  bool get _isUser => role == ChatBubbleRole.user;

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  bool _reasoningExpanded = false;
  bool _toolCallsExpanded = false;

  bool get _isUser => widget.role == ChatBubbleRole.user;

  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    return GestureDetector(
      onLongPress: widget.onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.messagePadding + 8,
          vertical: AppSpacing.sm / 2,
        ),
        child: Row(
          mainAxisAlignment:
              _isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: _isUser
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (!_isUser &&
                      widget.reasoning != null &&
                      widget.reasoning!.trim().isNotEmpty) ...[
                    _buildReasoningBlock(widget.reasoning!, c),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                  if (!_isUser && widget.toolCalls.isNotEmpty) ...[
                    _buildToolCallsBlock(c),
                    if (widget.content.isNotEmpty)
                      const SizedBox(height: AppSpacing.xs),
                  ],
                  if (widget.content.isNotEmpty) _buildBubble(c),
                  if (widget.wikiRefs != null && widget.wikiRefs!.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    _buildWikiRefs(c),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBubble(AppSemanticColors c) {
    // 自适应宽度：取可用空间 78%，作为气泡最大宽度上下限
    final screenWidth = MediaQuery.of(context).size.width;
    final maxBubbleWidth = (screenWidth * 0.78).clamp(240.0, 560.0);

    return Container(
      constraints: BoxConstraints(maxWidth: maxBubbleWidth),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        // 用户气泡：主题感知的渐变
        // AI 气泡：主题感知的次级面板色
        gradient: _isUser ? c.userBubbleGradient : null,
        color: _isUser ? null : c.aiBubble,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(AppSpacing.radiusLg),
          topRight: const Radius.circular(AppSpacing.radiusLg),
          bottomLeft:
              Radius.circular(_isUser ? AppSpacing.radiusLg : AppSpacing.xs),
          bottomRight:
              Radius.circular(_isUser ? AppSpacing.xs : AppSpacing.radiusLg),
        ),
        border: Border.all(
          color: _isUser
              ? c.primary.withValues(alpha: 0.4)
              : c.border,
          width: _isUser ? 1 : 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isUser)
            Text(
              widget.content,
              style: AppTypography.chatMessage.copyWith(
                color: c.onPrimary,
              ),
            )
          else
            SimpleMarkdownText(
              content: widget.content.isEmpty ? ' ' : widget.content,
              color: c.textPrimary,
            ),
          if (widget.isStreaming && widget.content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: _buildStreamingCursor(c),
            ),
        ],
      ),
    );
  }

  Widget _buildStreamingCursor(AppSemanticColors c) {
    return SizedBox(
      width: 8,
      height: 16,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.primary,
          borderRadius: const BorderRadius.all(Radius.circular(1)),
        ),
      ),
    );
  }

  /// 折叠展示「思考过程」：默认收起，点击展开。
  Widget _buildReasoningBlock(String text, AppSemanticColors c) {
    final isStreaming = widget.isStreaming;
    final label = isStreaming
        ? '正在思考…（${text.length} 字）'
        : '思考过程（${text.length} 字）';

    return InkWell(
      onTap: () => setState(() => _reasoningExpanded = !_reasoningExpanded),
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: c.surfaceVariant.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(
            color: c.border.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isStreaming)
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: c.primary,
                    ),
                  )
                else
                  Icon(
                    Icons.psychology_outlined,
                    size: 12,
                    color: c.textTertiary,
                  ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: AppTypography.bodySmall.copyWith(
                      color: c.textTertiary,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  _reasoningExpanded
                      ? Icons.expand_less
                      : Icons.expand_more,
                  size: 14,
                  color: c.textTertiary,
                ),
              ],
            ),
            if (_reasoningExpanded)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: SelectableText(
                    text,
                    style: AppTypography.bodySmall.copyWith(
                      color: c.textSecondary,
                      fontStyle: FontStyle.italic,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 折叠展示「工具调用」
  Widget _buildToolCallsBlock(AppSemanticColors c) {
    final calls = widget.toolCalls;
    final names = calls.map((cc) => cc.name).join(' · ');

    return InkWell(
      onTap: () => setState(() => _toolCallsExpanded = !_toolCallsExpanded),
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: c.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(
            color: c.primary.withValues(alpha: 0.25),
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.handyman_outlined,
                  size: 12,
                  color: c.primary.withValues(alpha: 0.8),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '工具调用 · $names',
                    style: AppTypography.bodySmall
                        .copyWith(color: c.textTertiary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  _toolCallsExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 14,
                  color: c.textTertiary,
                ),
              ],
            ),
            if (_toolCallsExpanded)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < calls.length; i++) ...[
                      if (i > 0) const SizedBox(height: AppSpacing.sm),
                      Text(
                        calls[i].name,
                        style: AppTypography.bodySmall.copyWith(
                          color: c.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (calls[i].arguments.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: c.surface,
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusSm),
                          ),
                          child: SelectableText(
                            _prettyJson(calls[i].arguments),
                            style: AppTypography.code.copyWith(
                              fontSize: 11,
                              color: c.textSecondary,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 尝试将 JSON 字符串格式化缩进；失败时原样返回。
  String _prettyJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return raw;
    }
  }

  Widget _buildWikiRefs(AppSemanticColors c) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: widget.wikiRefs!.map((ref) {
        return GestureDetector(
          onTap: widget.onWikiRefTap != null
              ? () => widget.onWikiRefTap!(ref)
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: c.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              border: Border.all(
                color: c.primary.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.article_outlined,
                  size: 12,
                  color: c.primary.withValues(alpha: 0.8),
                ),
                const SizedBox(width: 4),
                Text(
                  ref,
                  style: AppTypography.bodySmall.copyWith(
                    color: c.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  简易 Markdown 渲染（不依赖任何第三方包）
// ═══════════════════════════════════════════════════════════

/// 简易 Markdown 文本渲染器
class SimpleMarkdownText extends StatelessWidget {
  const SimpleMarkdownText({
    super.key,
    required this.content,
    this.selectable = true,
    this.color,
  });

  final String content;
  final bool selectable;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    final blocks = _parseBlocks(content, c);
    return SelectableText.rich(
      TextSpan(
        children: blocks.expand((b) => b.toSpans()).toList(),
        style: AppTypography.chatMessage.copyWith(
          color: color ?? c.textPrimary,
        ),
      ),
    );
  }

  List<_MarkdownBlock> _parseBlocks(String text, AppSemanticColors c) {
    final blocks = <_MarkdownBlock>[];
    final lines = text.split('\n');
    var i = 0;

    while (i < lines.length) {
      final line = lines[i];

      // 代码块
      if (line.trimLeft().startsWith('```')) {
        final code = StringBuffer();
        i++;
        while (i < lines.length && !lines[i].trimLeft().startsWith('```')) {
          code.writeln(lines[i]);
          i++;
        }
        if (i < lines.length) i++; // 跳过结束 ```
        blocks.add(_CodeBlock(code.toString().trimRight(), c));
        continue;
      }

      // 标题
      final headingMatch = RegExp(r'^(#{1,3})\s+(.*)$').firstMatch(line);
      if (headingMatch != null) {
        final level = headingMatch.group(1)!.length;
        blocks.add(_HeadingBlock(headingMatch.group(2)!, level, c));
        i++;
        continue;
      }

      // 引用
      if (line.trimLeft().startsWith('> ')) {
        final quote = StringBuffer();
        while (i < lines.length && lines[i].trimLeft().startsWith('> ')) {
          quote.writeln(lines[i].trimLeft().substring(2));
          i++;
        }
        blocks.add(_QuoteBlock(quote.toString().trimRight(), c));
        continue;
      }

      // 分隔线
      if (line.trim() == '---' || line.trim() == '***') {
        blocks.add(_DividerBlock(c));
        i++;
        continue;
      }

      // 列表
      if (RegExp(r'^\s*[-*]\s+').hasMatch(line)) {
        final items = <String>[];
        while (i < lines.length &&
            RegExp(r'^\s*[-*]\s+').hasMatch(lines[i])) {
          items.add(
            lines[i].replaceFirst(RegExp(r'^\s*[-*]\s+'), ''),
          );
          i++;
        }
        blocks.add(_ListBlock(items, c));
        continue;
      }

      // 空行
      if (line.trim().isEmpty) {
        i++;
        continue;
      }

      // 默认段落
      final paragraph = StringBuffer(line);
      i++;
      while (i < lines.length &&
          lines[i].trim().isNotEmpty &&
          !RegExp(r'^(#{1,3})\s+').hasMatch(lines[i]) &&
          !RegExp(r'^\s*[-*]\s+').hasMatch(lines[i]) &&
          !lines[i].trimLeft().startsWith('```') &&
          !lines[i].trimLeft().startsWith('> ')) {
        paragraph.writeln();
        paragraph.write(lines[i]);
        i++;
      }
      blocks.add(_ParagraphBlock(paragraph.toString(), c));
    }

    return blocks;
  }
}

/// 块级 Markdown 元素基类
sealed class _MarkdownBlock {
  const _MarkdownBlock();
  List<InlineSpan> toSpans();
}

/// 段落
class _ParagraphBlock extends _MarkdownBlock {
  const _ParagraphBlock(this.text, this.c);
  final String text;
  final AppSemanticColors c;

  @override
  List<InlineSpan> toSpans() => _buildInlineSpans(text, c);
}

/// 标题
class _HeadingBlock extends _MarkdownBlock {
  const _HeadingBlock(this.text, this.level, this.c);
  final String text;
  final int level;
  final AppSemanticColors c;

  @override
  List<InlineSpan> toSpans() {
    final baseStyle = switch (level) {
      1 => AppTypography.titleLarge.copyWith(color: c.textPrimary),
      2 => AppTypography.titleMedium.copyWith(color: c.textPrimary),
      _ => AppTypography.bodyLarge.copyWith(
          color: c.textPrimary,
          fontWeight: FontWeight.w600,
        ),
    };
    return [
      TextSpan(text: '$text\n', style: baseStyle),
    ];
  }
}

/// 列表
class _ListBlock extends _MarkdownBlock {
  const _ListBlock(this.items, this.c);
  final List<String> items;
  final AppSemanticColors c;

  @override
  List<InlineSpan> toSpans() {
    final spans = <InlineSpan>[];
    for (final item in items) {
      spans.addAll(_buildInlineSpans('• $item', c));
      spans.add(const TextSpan(text: '\n'));
    }
    return spans;
  }
}

/// 代码块
class _CodeBlock extends _MarkdownBlock {
  const _CodeBlock(this.code, this.c);
  final String code;
  final AppSemanticColors c;

  @override
  List<InlineSpan> toSpans() {
    final lines = code.split('\n');
    final spans = <InlineSpan>[
      const TextSpan(text: '\n'),
      for (final line in lines) ...[
        TextSpan(
          text: line.isEmpty ? ' ' : line,
          style: AppTypography.code.copyWith(
            color: c.primary,
            backgroundColor: c.codeBackground,
          ),
        ),
        const TextSpan(text: '\n'),
      ],
      const TextSpan(text: '\n'),
    ];
    return spans;
  }
}

/// 引用块
class _QuoteBlock extends _MarkdownBlock {
  const _QuoteBlock(this.text, this.c);
  final String text;
  final AppSemanticColors c;

  @override
  List<InlineSpan> toSpans() {
    final style = AppTypography.bodyLarge.copyWith(
      color: c.textTertiary,
      fontStyle: FontStyle.italic,
    );
    return _buildInlineSpans('│ $text', c, baseStyle: style)
      ..add(const TextSpan(text: '\n'));
  }
}

/// 分隔线
class _DividerBlock extends _MarkdownBlock {
  const _DividerBlock(this.c);
  final AppSemanticColors c;

  @override
  List<InlineSpan> toSpans() => const [
        TextSpan(text: '────────────────\n'),
      ];
}

/// 解析行内 Markdown 语法
List<InlineSpan> _buildInlineSpans(
  String text,
  AppSemanticColors c, {
  TextStyle? baseStyle,
}) {
  final spans = <InlineSpan>[];
  final pattern = RegExp(
    r'(\*\*([^*]+)\*\*)|'
    r'(\*([^*]+)\*)|'
    r'(`([^`]+)`)|'
    r'(\[([^\]]+)\]\(([^)]+)\))',
  );

  int lastEnd = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > lastEnd) {
      spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
    }

    final matchedText = match.group(0)!;

    if (match.group(1) != null) {
      spans.add(
        TextSpan(
          text: match.group(2),
          style: baseStyle?.copyWith(fontWeight: FontWeight.w700) ??
              const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
    } else if (match.group(3) != null) {
      spans.add(
        TextSpan(
          text: match.group(4),
          style: baseStyle?.copyWith(fontStyle: FontStyle.italic) ??
              const TextStyle(fontStyle: FontStyle.italic),
        ),
      );
    } else if (match.group(5) != null) {
      spans.add(
        TextSpan(
          text: match.group(6),
          style: AppTypography.code.copyWith(
            color: c.primary,
            backgroundColor: c.codeBackground,
          ),
        ),
      );
    } else if (match.group(7) != null) {
      spans.add(
        TextSpan(
          text: match.group(8),
          style: AppTypography.chatLink.copyWith(color: c.primary),
        ),
      );
    } else {
      spans.add(TextSpan(text: matchedText));
    }

    lastEnd = match.end;
  }

  if (lastEnd < text.length) {
    spans.add(TextSpan(text: text.substring(lastEnd)));
  }

  return spans;
}