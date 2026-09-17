/// LLM 工具调用相关数据模型。
///
/// 抽取到 core/model 层以避免 message.dart → llm_provider.dart → message.dart
/// 的循环依赖。
///
/// LlmToolCall 在两处使用：
/// - Provider → ChatController：流式响应中聚合后的工具调用
/// - ChatController → Provider：assistant 消息携带的工具调用（OpenAI 协议）
library;

import 'dart:convert';

/// 单次 LLM 工具调用
///
/// OpenAI 协议：每个 tool_call 有唯一 id，对应一个函数调用。
class LlmToolCall {
  const LlmToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  /// 工具调用唯一 ID（用于把 tool 消息回传给 LLM）
  final String id;

  /// 工具名称
  final String name;

  /// 参数 JSON 字符串（未解析的原文，由 ChatController 解析）
  final String arguments;

  /// 解析后的参数 Map（解析失败返回空 Map）
  Map<String, dynamic> get parsedArgs {
    if (arguments.trim().isEmpty) return {};
    try {
      final trimmed = arguments.trim();
      if (!trimmed.startsWith('{')) return {};
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return {};
    } catch (_) {
      return {};
    }
  }

  @override
  String toString() =>
      'LlmToolCall(id: $id, name: $name, args: $arguments)';
}

/// 工具定义（ChatController → Provider 方向）
///
/// 字段遵循 OpenAI tools 协议，由 Provider 序列化为 JSON。
class LlmToolDefinition {
  const LlmToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
  });

  /// 工具函数名
  final String name;

  /// 工具描述（LLM 读这个决定何时调用）
  final String description;

  /// JSON Schema 形式参数定义
  /// ```dart
  /// {
  ///   'type': 'object',
  ///   'properties': {'path': {'type': 'string', 'description': '...'}},
  ///   'required': ['path'],
  /// }
  /// ```
  final Map<String, dynamic> parameters;
}