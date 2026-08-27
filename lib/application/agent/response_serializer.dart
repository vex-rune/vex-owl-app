import 'dart:convert';

import '../../core/model/agent_response.dart';

/// AgentResponse → Markdown 序列化器(纯函数,无副作用)。
///
/// 翻译规则:
/// * [AgentThinking] → `<think>content</think>`
/// * [AgentText]      → 原文 content(由 LangChain 累积好的流式片段)
/// * [AgentToolCall]  → `:::tool_call id="..." name="..."\n```json\n...\n```\n:::`
/// * [AgentToolResult]→ `:::tool_result id="..."\noutput\n:::`
/// * [AgentFinish]    → 空字符串(由 `doOnComplete` 收尾,不在流式过程产生 delta)
///
/// 整回合的 assistant 回复是一条 Message,content 是这些片段按发生顺序
/// 串成的 Markdown。下游渲染层(message_bubble)负责把自定义块还原成 UI。
class AgentResponseSerializer {
  const AgentResponseSerializer._();

  /// 把一条 [AgentResponse] 翻译成可追加的 Markdown delta。
  ///
  /// 返回空字符串表示"无需落库"(例如 [AgentThinking] 内容为空,
  /// 或终态信号 [AgentFinish])。
  static String serialize(AgentResponse response) {
    switch (response) {
      case AgentThinking(:final content):
        if (content.isEmpty) return '';
        return '\n<think>$content</think>\n';
      case AgentText(:final content):
        return content;
      case AgentToolCall(:final name, :final args, :final callId):
        final argsJson = jsonEncode(args);
        return '\n\n:::tool_call id="$callId" name="$name"\n```json\n$argsJson\n```\n:::\n\n';
      case AgentToolResult(:final callId, :final output):
        return '\n:::tool_result id="$callId"\n$output\n:::\n\n';
      case AgentFinish():
        return '';
    }
  }
}
