import 'dart:convert';

import '../../../core/core.dart';

/// MINIMAX Chat Completions 请求体
///
/// 文档：https://platform.minimax.cn/docs/api-reference/text-chat-openai
///
/// 支持模型：MiniMax-M3, MiniMax-M2.7, MiniMax-M2.5 等
class MinimaxRequest {
  const MinimaxRequest({
    required this.model,
    required this.messages,
    this.stream = true,
    this.maxCompletionTokens = 8192,
    this.temperature = 1.0,
    this.topP = 0.95,
    this.serviceTier,
    this.timeout = 60,
    this.thinking = const {
      'type': 'disabled',
    },
    this.tools,
    this.toolChoice,
    this.reasoningSplit = false,
  });

  final String model;
  final List<Message> messages;
  final bool stream;
  final int maxCompletionTokens;
  final double temperature;
  final double topP;
  final String? serviceTier; // 'standard' | 'priority'
  final int timeout; // 秒
  final Map<String, dynamic> thinking;

  /// 可用工具列表（OpenAI 协议）
  final List<Map<String, dynamic>>? tools;

  /// 工具选择策略（'auto' | 'none' | 'required' | {type:'function', function:{name:'xxx'}}）
  /// 传 null 表示不限制（让模型自行决定）
  final Object? toolChoice;

  /// 是否启用 reasoning_split：
  /// - true：思考内容拆分到 `reasoning_content` / `reasoning_details` 字段
  /// - 不开启/关闭 thinking，仅控制输出格式
  ///
  /// 仅在 `thinking.type` 不为 'disabled' 时有效。
  final bool reasoningSplit;

  /// 转为 JSON（用于 HTTP 请求）
  Map<String, dynamic> toJson() {
    final body = <String, dynamic>{
      'model': model,
      'messages': _serializeMessages(),
      'stream': stream,
      'max_completion_tokens': maxCompletionTokens,
      'temperature': temperature,
      'top_p': topP,
      'thinking': thinking,
    };
    if (serviceTier != null) {
      body['service_tier'] = serviceTier;
    }
    if (tools != null && tools!.isNotEmpty) {
      body['tools'] = tools;
      if (toolChoice != null) body['tool_choice'] = toolChoice;
    }
    if (reasoningSplit) {
      body['reasoning_split'] = true;
    }
    return body;
  }

  /// 序列化为 MINIMAX messages 格式
  ///
  /// 兼容 4 种角色：
  /// - user / assistant / system：普通文本消息
  /// - assistant 含 tool_calls：携带 tool_calls 字段
  /// - tool：工具执行结果，带 tool_call_id
  List<Map<String, dynamic>> _serializeMessages() {
    return messages.map((msg) {
      final base = <String, dynamic>{
        'role': msg.role.name,
      };

      // assistant 携带工具调用时：
      // - content 必须存在（可为 null）
      // - 必须输出 tool_calls 数组
      // - tool_calls 与后续 tool 消息的 tool_call_id 一一对应
      if (msg.role == MessageRole.assistant && msg.toolCalls.isNotEmpty) {
        base['content'] = msg.content.isEmpty ? null : msg.content;
        base['tool_calls'] = msg.toolCalls
            .map((c) => {
                  'id': c.id,
                  'type': 'function',
                  'function': {
                    'name': c.name,
                    'arguments': c.arguments,
                  },
                })
            .toList();
        return base;
      }

      base['content'] = msg.content;

      if (msg.role == MessageRole.tool) {
        // OpenAI 协议：tool 消息必须带 tool_call_id 与 content
        if (msg.toolCallId != null) {
          base['tool_call_id'] = msg.toolCallId;
        }
      }
      return base;
    }).toList();
  }

  /// 完整 JSON 字符串（用于日志打印）
  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());
}

/// MINIMAX 流式响应 chunk
class MinimaxChunk {
  const MinimaxChunk({
    required this.id,
    required this.choices,
    required this.created,
    required this.model,
    required this.object,
    this.usage,
    this.inputSensitive = false,
    this.outputSensitive = false,
  });

  final String id;
  final List<MinimaxChoice> choices;
  final int created;
  final String model;
  final String object; // "chat.completion.chunk"
  final MinimaxUsage? usage;
  final bool inputSensitive;
  final bool outputSensitive;

  factory MinimaxChunk.fromJson(Map<String, dynamic> json) {
    return MinimaxChunk(
      id: json['id'] as String? ?? '',
      choices: (json['choices'] as List?)
              ?.map((c) => MinimaxChoice.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      created: json['created'] as int? ?? 0,
      model: json['model'] as String? ?? '',
      object: json['object'] as String? ?? '',
      usage: json['usage'] != null
          ? MinimaxUsage.fromJson(json['usage'] as Map<String, dynamic>)
          : null,
      inputSensitive: json['input_sensitive'] as bool? ?? false,
      outputSensitive: json['output_sensitive'] as bool? ?? false,
    );
  }

  /// 是否为流结束 chunk
  bool get isFinished =>
      choices.isNotEmpty && choices.first.finishReason != null;
}

/// 流式 choice
class MinimaxChoice {
  const MinimaxChoice({
    required this.index,
    required this.delta,
    this.finishReason,
  });

  final int index;
  final MinimaxDelta delta;
  final String? finishReason; // "stop", "length", null

  factory MinimaxChoice.fromJson(Map<String, dynamic> json) {
    return MinimaxChoice(
      index: json['index'] as int? ?? 0,
      delta: MinimaxDelta.fromJson(
          json['delta'] as Map<String, dynamic>? ?? {}),
      finishReason: json['finish_reason'] as String?,
    );
  }
}

/// 流式 delta
///
/// 部分 Provider（如 MINIMAX）支持原生 function calling，
/// 此时 delta 会携带 [toolCalls] 字段（每条 toolCall 也按流式增量下传）。
///
/// 启用 reasoning_split=true 后，思考过程会拆分到 [reasoningContent] / [reasoningDetails] 字段，
/// [content] 字段只包含最终回复。
class MinimaxDelta {
  const MinimaxDelta({
    this.content,
    this.reasoningContent,
    this.reasoningDetails,
    this.role,
    this.name,
    this.audioContent,
    this.toolCalls,
  });

  /// 回复文本（不含思考内容）
  final String? content;

  /// reasoning_split=true 时，思考过程拆分到此字段
  final String? reasoningContent;

  /// reasoning_split=true 时，思考结构化明细（可选，标准推理格式）
  final List<MinimaxReasoningDetail>? reasoningDetails;

  final String? role; // "assistant"
  final String? name; // "MiniMax AI"
  final String? audioContent; // 语音内容（空字符串表示无）

  /// 工具调用增量（流式累计）
  final List<MinimaxDeltaToolCall>? toolCalls;

  factory MinimaxDelta.fromJson(Map<String, dynamic> json) {
    return MinimaxDelta(
      content: json['content'] as String?,
      reasoningContent: json['reasoning_content'] as String?,
      reasoningDetails: (json['reasoning_details'] as List?)
              ?.map((d) =>
                  MinimaxReasoningDetail.fromJson(d as Map<String, dynamic>))
              .toList(),
      role: json['role'] as String?,
      name: json['name'] as String?,
      audioContent: json['audio_content'] as String?,
      toolCalls: (json['tool_calls'] as List?)
              ?.map((c) => MinimaxDeltaToolCall.fromJson(
                  c as Map<String, dynamic>))
              .toList(),
    );
  }
}

/// 思考过程结构化明细
///
/// MINIMAX 协议：每个 detail 项包含 type / id / format / index / text。
/// `type='reasoning.text'` 表示纯文本推理步骤。
class MinimaxReasoningDetail {
  const MinimaxReasoningDetail({
    this.type,
    this.id,
    this.format,
    this.index,
    this.text,
  });

  /// 类型（如 'reasoning.text'）
  final String? type;

  /// 唯一 ID（增量时会重复同 id 用于累积）
  final String? id;

  /// 格式标识（如 'MiniMax-response-v1'）
  final String? format;

  /// 同一回复内 detail 顺序
  final int? index;

  /// 文本内容
  final String? text;

  factory MinimaxReasoningDetail.fromJson(Map<String, dynamic> json) {
    return MinimaxReasoningDetail(
      type: json['type'] as String?,
      id: json['id'] as String?,
      format: json['format'] as String?,
      index: json['index'] as int?,
      text: json['text'] as String?,
    );
  }
}

/// 流式 delta 中的工具调用片段
///
/// 一个完整的 tool_call 可能跨多个 chunk 下传，由 ChatController
/// 或 Provider 按 [index] 聚合后产出完整的 [LlmToolCall]。
class MinimaxDeltaToolCall {
  const MinimaxDeltaToolCall({
    this.index,
    this.id,
    this.type,
    this.function,
  });

  /// 同一个 assistant message 中 tool_call 的顺序（0..N）
  final int? index;

  /// 工具调用 ID（首次下传时给出，后续 chunk 沿用）
  final String? id;

  /// 类型（通常是 'function'）
  final String? type;

  /// 函数调用片段
  final MinimaxFunctionCall? function;

  factory MinimaxDeltaToolCall.fromJson(Map<String, dynamic> json) {
    return MinimaxDeltaToolCall(
      index: json['index'] as int?,
      id: json['id'] as String?,
      type: json['type'] as String?,
      function: json['function'] != null
          ? MinimaxFunctionCall.fromJson(
              json['function'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// 函数调用片段
class MinimaxFunctionCall {
  const MinimaxFunctionCall({
    this.name,
    this.arguments,
  });

  /// 函数名（首次给出，后续为 null）
  final String? name;

  /// 参数 JSON 字符串片段（按增量拼接到一起）
  final String? arguments;

  factory MinimaxFunctionCall.fromJson(Map<String, dynamic> json) {
    return MinimaxFunctionCall(
      name: json['name'] as String?,
      arguments: json['arguments'] as String?,
    );
  }
}

/// Token 用量
class MinimaxUsage {
  const MinimaxUsage({
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
    this.cachedTokens,
  });

  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;
  final int? cachedTokens; // prompt_tokens_details.cached_tokens

  factory MinimaxUsage.fromJson(Map<String, dynamic> json) {
    final details = json['prompt_tokens_details'] as Map<String, dynamic>?;
    return MinimaxUsage(
      promptTokens: json['prompt_tokens'] as int?,
      completionTokens: json['completion_tokens'] as int?,
      totalTokens: json['total_tokens'] as int?,
      cachedTokens: details?['cached_tokens'] as int?,
    );
  }
}
