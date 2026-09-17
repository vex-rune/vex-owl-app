import 'dart:convert';

import '../../../core/core.dart';

/// DeepSeek Chat Completions 请求体
///
/// 文档：https://platform.deepseek.com/api-docs/zh-cn/posix/chat/create
///
/// DeepSeek API 兼容 OpenAI 格式，同时扩展了思考模式相关字段：
/// - `thinking`：控制是否启用深度思考
/// - `reasoning_effort`：控制思考力度（low / medium / high）
///
/// 支持模型：deepseek-chat, deepseek-reasoner, deepseek-flash, deepseek-v4-pro
class DeepSeekRequest {
  const DeepSeekRequest({
    required this.model,
    required this.messages,
    this.stream = true,
    this.maxTokens = 4096,
    this.temperature = 1.0,
    this.topP = 0.95,
    this.tools,
    this.toolChoice,
    this.thinking,
    this.reasoningEffort,
    this.frequencyPenalty,
    this.presencePenalty,
    this.stop,
  });

  final String model;
  final List<Message> messages;
  final bool stream;
  final int maxTokens;
  final double temperature;
  final double topP;
  final List<Map<String, dynamic>>? tools;
  final Object? toolChoice;

  /// 思考模式：{'type': 'enabled'} / {'type': 'disabled'} / null
  final Map<String, dynamic>? thinking;

  /// 思考力度：'low' / 'medium' / 'high'
  final String? reasoningEffort;
  final double? frequencyPenalty;
  final double? presencePenalty;
  final List<String>? stop;

  Map<String, dynamic> toJson() {
    final body = <String, dynamic>{
      'model': model,
      'messages': _serializeMessages(),
      'stream': stream,
      'max_tokens': maxTokens,
      'temperature': temperature,
      'top_p': topP,
    };
    if (thinking != null) body['thinking'] = thinking;
    if (reasoningEffort != null) body['reasoning_effort'] = reasoningEffort;
    if (tools != null && tools!.isNotEmpty) {
      body['tools'] = tools;
      if (toolChoice != null) body['tool_choice'] = toolChoice;
    }
    if (frequencyPenalty != null) {
      body['frequency_penalty'] = frequencyPenalty;
    }
    if (presencePenalty != null) {
      body['presence_penalty'] = presencePenalty;
    }
    if (stop != null) body['stop'] = stop;
    return body;
  }

  /// 序列化 messages（OpenAI 兼容格式）
  List<Map<String, dynamic>> _serializeMessages() {
    return messages.map((msg) {
      final base = <String, dynamic>{'role': msg.role.name};
      if (msg.role == MessageRole.assistant && msg.toolCalls.isNotEmpty) {
        base['content'] = msg.content.isEmpty ? null : msg.content;
        base['tool_calls'] = msg.toolCalls
            .map((c) => {
                  'id': c.id,
                  'type': 'function',
                  'function': {'name': c.name, 'arguments': c.arguments},
                })
            .toList();
        return base;
      }
      base['content'] = msg.content;
      if (msg.role == MessageRole.tool && msg.toolCallId != null) {
        base['tool_call_id'] = msg.toolCallId;
      }
      return base;
    }).toList();
  }

  String toJsonString() =>
      const JsonEncoder.withIndent('  ').convert(toJson());
}

// ────────────────────────────────────────────
//  SSE 流式响应模型
// ────────────────────────────────────────────

/// DeepSeek 流式 SSE 响应 chunk
///
/// 标准 OpenAI SSE 格式 + DeepSeek 自定义字段：
/// - delta.reasoning_content：思考内容增量（thinking 启用时）
class DeepSeekSSEChunk {
  const DeepSeekSSEChunk({
    this.id,
    this.object,
    this.created,
    this.model,
    this.choices,
    this.usage,
  });

  final String? id;
  final String? object;
  final int? created;
  final String? model;
  final List<DeepSeekStreamChoice>? choices;
  final DeepSeekUsage? usage;

  factory DeepSeekSSEChunk.fromJson(Map<String, dynamic> json) {
    return DeepSeekSSEChunk(
      id: json['id'] as String?,
      object: json['object'] as String?,
      created: json['created'] as int?,
      model: json['model'] as String?,
      choices: (json['choices'] as List?)
          ?.map((c) =>
              DeepSeekStreamChoice.fromJson(c as Map<String, dynamic>))
          .toList(),
      usage: json['usage'] != null
          ? DeepSeekUsage.fromJson(json['usage'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// DeepSeek 流式选择
class DeepSeekStreamChoice {
  const DeepSeekStreamChoice({this.index, this.delta, this.finishReason});

  final int? index;
  final DeepSeekStreamDelta? delta;
  final String? finishReason;

  factory DeepSeekStreamChoice.fromJson(Map<String, dynamic> json) {
    return DeepSeekStreamChoice(
      index: json['index'] as int?,
      delta: json['delta'] != null
          ? DeepSeekStreamDelta.fromJson(json['delta'] as Map<String, dynamic>)
          : null,
      finishReason: json['finish_reason'] as String?,
    );
  }
}

/// DeepSeek 流式增量内容
///
/// 扩展标准 OpenAI delta，增加 `reasoning_content` 字段用于思考内容。
/// DeepSeek 思考模式下，模型先输出 reasoning_content（思考过程），
/// 思考结束后才开始输出 content（正式回答）。
class DeepSeekStreamDelta {
  const DeepSeekStreamDelta({
    this.role,
    this.content,
    this.reasoningContent,
    this.toolCalls,
  });

  final String? role;
  final String? content;

  /// 思考内容增量（thinking 启用时）
  final String? reasoningContent;

  /// 工具调用增量（OpenAI tool_calls 协议）
  final List<DeepSeekDeltaToolCall>? toolCalls;

  factory DeepSeekStreamDelta.fromJson(Map<String, dynamic> json) {
    return DeepSeekStreamDelta(
      role: json['role'] as String?,
      content: json['content'] as String?,
      reasoningContent: json['reasoning_content'] as String?,
      toolCalls: (json['tool_calls'] as List?)
          ?.map((c) =>
              DeepSeekDeltaToolCall.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// DeepSeek 流式工具调用片段
class DeepSeekDeltaToolCall {
  const DeepSeekDeltaToolCall({this.index, this.id, this.type, this.function});

  final int? index;
  final String? id;
  final String? type;
  final DeepSeekFunctionCall? function;

  factory DeepSeekDeltaToolCall.fromJson(Map<String, dynamic> json) {
    return DeepSeekDeltaToolCall(
      index: json['index'] as int?,
      id: json['id'] as String?,
      type: json['type'] as String?,
      function: json['function'] != null
          ? DeepSeekFunctionCall.fromJson(
              json['function'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// DeepSeek 函数调用片段
class DeepSeekFunctionCall {
  const DeepSeekFunctionCall({this.name, this.arguments});

  final String? name;
  final String? arguments;

  factory DeepSeekFunctionCall.fromJson(Map<String, dynamic> json) {
    return DeepSeekFunctionCall(
      name: json['name'] as String?,
      arguments: json['arguments'] as String?,
    );
  }
}

/// DeepSeek Token 用量
class DeepSeekUsage {
  const DeepSeekUsage({this.promptTokens, this.completionTokens, this.totalTokens});

  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;

  factory DeepSeekUsage.fromJson(Map<String, dynamic> json) {
    return DeepSeekUsage(
      promptTokens: json['prompt_tokens'] as int?,
      completionTokens: json['completion_tokens'] as int?,
      totalTokens: json['total_tokens'] as int?,
    );
  }
}
