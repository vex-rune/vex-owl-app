import 'package:flutter/material.dart';

import '../../core/model/turn.dart';
import '../theme/app_theme.dart';
import 'message_bubble.dart';

/// 一次助手回合的容器气泡。
///
/// **v2 简化**:整轮 assistant 回复 = 1 条 Message(text 类型,content 是带自定义块的 Markdown)。
/// 本组件只负责:取出回合中所有 Message,渲染为单列。
///
/// 后续如需解析 `<think>...</think>`、`:::tool_call` 等自定义块,
/// 应在 [MessageBubble] 的 assistant 分支内识别 + 分段渲染。
class AssistantTurnBubble extends StatelessWidget {
  const AssistantTurnBubble({super.key, required this.turn});

  final AssistantTurn turn;

  @override
  Widget build(BuildContext context) {
    if (turn.events.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.space1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final m in turn.events) MessageBubble(message: m),
        ],
      ),
    );
  }
}