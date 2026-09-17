import 'dart:convert';

import '../../../core/core.dart';

/// MiMo（小米）Chat Completions 请求体
///
/// MiMo 模型通过 vLLM / SGLang 等推理引擎自部署，
/// API 完全兼容 OpenAI 格式。
///
/// 支持模型：mimo-v2.5-pro, mimo-v2.5
class MimoRequest {
  const MimoRequest({
    required this.model,
    required this.messages,
    this.stream = true,
    this.maxTokens = 4096,
    this.temperature = 0.6,
    this.topP = 1.0,
    this.tools,
    this.toolChoice,
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
  final double? frequencyPenalty;
  final double? presencePenalty;
  final List<String>? stop;

  /// 转为 JSON（标准 OpenAI 兼容格式）
  Map<String, dynamic> toJson() {
    final body = <String, dynamic>{
      'model': model,
      'messages': _serializeMessages(),
      'stream': stream,
      'max_tokens': maxTokens,
      'temperature': temperature,
      'top_p': topP,
    };
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
//  SSE 流式响应模型（标准 OpenAI 格式）
// ────────────────────────────────────────────

/// MiMo 流式 SSE 响应 chunk（标准 OpenAI 格式）
class MimoSSEChunk {
  const MimoSSEChunk({
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
  final List<MimoStreamChoice>? choices;
  final MimoUsage? usage;

  factory MimoSSEChunk.fromJson(Map<String, dynamic> json) {
    return MimoSSEChunk(
      id: json['id'] as String?,
      object: json['object'] as String?,
      created: json['created'] as int?,
      model: json['model'] as String?,
      choices: (json['choices'] as List?)
          ?.map((c) =>
              MimoStreamChoice.fromJson(c as Map<String, dynamic>))
          .toList(),
      usage: json['usage'] != null
          ? MimoUsage.fromJson(json['usage'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// MiMo 流式选择
class MimoStreamChoice {
  const MimoStreamChoice({this.index, this.delta, this.finishReason});

  final int? index;
  final MimoStreamDelta? delta;
  final String? finishReason;

  factory MimoStreamChoice.fromJson(Map<String, dynamic> json) {
    return MimoStreamChoice(
      index: json['index'] as int?,
      delta: json['delta'] != null
          ? MimoStreamDelta.fromJson(json['delta'] as Map<String, dynamic>)
          : null,
      finishReason: json['finish_reason'] as String?,
    );
  }
}

/// MiMo 流式增量内容（标准 OpenAI delta）
class MimoStreamDelta {
  const MimoStreamDelta({this.role, this.content, this.toolCalls});

  final String? role;
  final String? content;
  final List<MimoDeltaToolCall>? toolCalls;

  factory MimoStreamDelta.fromJson(Map<String, dynamic> json) {
    return MimoStreamDelta(
      role: json['role'] as String?,
      content: json['content'] as String?,
      toolCalls: (json['tool_calls'] as List?)
          ?.map((c) =>
              MimoDeltaToolCall.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// MiMo 流式工具调用片段
class MimoDeltaToolCall {
  const MimoDeltaToolCall({this.index, this.id, this.type, this.function});

  final int? index;
  final String? id;
  final String? type;
  final MimoFunctionCall? function;

  factory MimoDeltaToolCall.fromJson(Map<String, dynamic> json) {
    return MimoDeltaToolCall(
      index: json['index'] as int?,
      id: json['id'] as String?,
      type: json['type'] as String?,
      function: json['function'] != null
          ? MimoFunctionCall.fromJson(
              json['function'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// MiMo 函数调用片段
class MimoFunctionCall {
  const MimoFunctionCall({this.name, this.arguments});

  final String? name;
  final String? arguments;

  factory MimoFunctionCall.fromJson(Map<String, dynamic> json) {
    return MimoFunctionCall(
      name: json['name'] as String?,
      arguments: json['arguments'] as String?,
    );
  }
}

/// MiMo Token 用量
class MimoUsage {
  const MimoUsage({this.promptTokens, this.completionTokens, this.totalTokens});

  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;

  factory MimoUsage.fromJson(Map<String, dynamic> json) {
    return MimoUsage(
      promptTokens: json['prompt_tokens'] as int?,
      completionTokens: json['completion_tokens'] as int?,
      totalTokens: json['total_tokens'] as int?,
    );
  }
}
