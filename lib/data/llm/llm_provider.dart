import 'dart:async';

import '../../core/model/api_config.dart';
import '../../core/model/llm_tool_call.dart';
import '../../core/model/message.dart';

// 重新导出便于外部使用
export '../../core/model/llm_tool_call.dart' show LlmToolCall, LlmToolDefinition;

/// Provider 能力标签（用于 UI 徽章 / 选型判断）
class ProviderCapabilities {
  const ProviderCapabilities({
    this.streaming = true,
    this.toolCalls = false,
    this.images = false,
    this.vision = false,
    this.thinking = false,
    this.systemPrompt = true,
  });
  final bool streaming;
  final bool toolCalls;
  final bool images;
  final bool vision;
  final bool thinking;
  final bool systemPrompt;
}

/// Provider 配置表单模式（控制 UI 显示哪些输入字段）
///
/// 由 [LlmProvider.configSchema] 返回，供"添加/编辑配置"对话框读取，
/// 决定是否显示 Endpoint / Model 输入框、是否锁定、以及默认值。
class ProviderConfigSchema {
  const ProviderConfigSchema({
    this.showEndpoint = true,
    this.showModel = true,
    this.endpointFixed = false,
    this.modelFixed = false,
    this.endpointEditable = true,
    this.requiresApiKey = true,
    this.endpointDefault = '',
    this.modelDefault = '',
  });

  /// 是否在表单中显示 API 端点字段
  final bool showEndpoint;

  /// 是否在表单中显示模型字段
  final bool showModel;

  /// 端点是否锁定（仅展示不可修改）。常用于官方接入的 Provider
  final bool endpointFixed;

  /// 模型是否锁定（仅展示不可修改）
  final bool modelFixed;

  /// 端点是否可由用户编辑。false 时显示为只读标签
  final bool endpointEditable;

  /// 是否必须填写 API Key
  final bool requiresApiKey;

  /// 端点默认值（如官方地址）
  final String endpointDefault;

  /// 模型默认值（如官方主推模型）
  final String modelDefault;
}

/// 单次 LLM 调用结果（流式）
///
/// 支持三种事件类型：
/// - [LlmStreamEvent.delta]：增量文本（拼到当前 assistant 消息）
/// - [LlmStreamEvent.reasoning]：增量思考内容（reasoning_split=true 时）
/// - [LlmStreamEvent.toolCalls]：LLM 触发的工具调用（OpenAI tool_calls 协议）
/// - [LlmStreamEvent.done]：调用结束（可带 usage）
/// - [LlmStreamEvent.error]：错误
class LlmStreamEvent {
  const LlmStreamEvent._({
    this.delta,
    this.reasoning,
    this.done = false,
    this.error,
    this.usage,
    this.toolCalls,
  });

  final String? delta;

  /// 增量思考内容（reasoning_split 启用时由 Provider 拆分下发）
  final String? reasoning;

  final bool done;
  final String? error;
  final LlmUsage? usage;

  /// LLM 请求调用的工具列表（每个 tool_call 携带独立 id 与 JSON 参数）
  final List<LlmToolCall>? toolCalls;

  factory LlmStreamEvent.delta(String text) =>
      LlmStreamEvent._(delta: text);

  /// 思考内容增量（reasoning_split 启用时）
  factory LlmStreamEvent.reasoningText(String text) =>
      LlmStreamEvent._(reasoning: text);

  factory LlmStreamEvent.toolCalls(List<LlmToolCall> calls) =>
      LlmStreamEvent._(toolCalls: calls);

  factory LlmStreamEvent.done(LlmUsage usage) =>
      LlmStreamEvent._(done: true, usage: usage);

  factory LlmStreamEvent.error(String msg) =>
      LlmStreamEvent._(error: msg);
}

/// 单次 LLM 工具调用
///
/// OpenAI 协议：每个 tool_call 有唯一 id，对应一个函数调用。
/// Provider 把流式 chunk 聚合后 yield 完整对象。
///
/// (LlmToolCall / LlmToolDefinition 已下沉到 core/model/llm_tool_call.dart)

class LlmUsage {
  const LlmUsage({this.inputTokens = 0, this.outputTokens = 0});
  final int inputTokens;
  final int outputTokens;
  int get total => inputTokens + outputTokens;
}

/// LLM Provider 抽象接口
///
/// 每个具体供应商（MINIMAX / OpenAI / Anthropic / 自部署）实现此接口。
/// 设计原则：
/// 1. 协议无关：上层 ChatController 不感知协议差异
/// 2. 流式优先：所有调用必须返回 Stream，便于打字机效果
/// 3. 配置驱动：通过 [ApiConfig] 注入参数，无需子类化
abstract class LlmProvider {
  /// Provider 唯一标识（如 'minimax', 'openai', 'anthropic'）
  String get id;

  /// Provider 显示名称（用于 UI）
  String get displayName;

  /// 支持的模型列表（用于 UI 选择器）
  List<ProviderModelPreset> get supportedModels;

  /// Provider 能力标签
  ProviderCapabilities get capabilities;

  /// Provider 配置表单 schema（控制 UI 显示哪些字段、是否锁定）
  ProviderConfigSchema get configSchema;

  /// 解析配置（由 Provider 自定义逻辑，应用默认值、校验等）
  ///
  /// 例如 MINIMAX 强制使用官方 endpoint，无需用户配置。
  /// 默认实现：若 schema.endpointEditable == false 且有默认值，则用默认值覆盖。
  ApiConfig resolveConfig(ApiConfig config) {
    if (!configSchema.endpointEditable && configSchema.endpointDefault.isNotEmpty) {
      return config.copyWith(apiEndpoint: configSchema.endpointDefault);
    }
    return config;
  }

  /// 是否支持指定的 [ApiConfig]（根据 apiEndpoint / modelName 特征）
  bool supports(ApiConfig config);

  /// 流式调用 LLM
  ///
  /// [messages] 完整对话历史（不含 system prompt）
  /// [systemPrompt] 系统提示词（可选，由 capabilities.systemPrompt 控制）
  /// [tools] 可用工具定义列表（OpenAI 协议），不传则不启用 function calling
  Stream<LlmStreamEvent> chatStream(
    ApiConfig config, {
    required List<Message> messages,
    String? systemPrompt,
    List<LlmToolDefinition>? tools,
  });

  /// 非流式调用（用于会话命名等短任务）
  ///
  /// [tools] 可用工具定义列表，传参后 Provider 同样会处理 tool_calls。
  Future<String> chatComplete(
    ApiConfig config, {
    required List<Message> messages,
    String? systemPrompt,
    List<LlmToolDefinition>? tools,
  });

  /// 测试连接连通性（不消耗 token）
  Future<bool> testConnection(ApiConfig config);

  /// 把 Message 列表序列化为 OpenAI 兼容的 messages 数组
  /// 默认实现：基于 hasImage 判定 → 数组格式 vs 字符串格式
  /// Provider 可在自身中实现自定义逻辑（如需定制 system 字段结构）
  ///
  /// 工具调用相关：
  /// - assistant 消息携带 toolCalls → 输出 `tool_calls` 字段
  /// - tool 消息带 toolCallId → 输出 `tool_call_id` 字段
  static List<Map<String, dynamic>> serializeMessages(
    List<Message> messages, {
    String? systemPrompt,
  }) {
    final list = <Map<String, dynamic>>[];
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      list.add({'role': 'system', 'content': systemPrompt});
    }
    for (final m in messages) {
      // assistant 携带工具调用：必须输出 tool_calls，content 可为 null
      if (m.role == MessageRole.assistant && m.toolCalls.isNotEmpty) {
        list.add({
          'role': 'assistant',
          'content': m.content.isEmpty ? null : m.content,
          'tool_calls': m.toolCalls
              .map((c) => {
                    'id': c.id,
                    'type': 'function',
                    'function': {
                      'name': c.name,
                      'arguments': c.arguments,
                    },
                  })
              .toList(),
        });
        continue;
      }

      // tool 消息：必须带 tool_call_id
      if (m.role == MessageRole.tool) {
        list.add({
          'role': 'tool',
          'tool_call_id': m.toolCallId,
          'content': m.content,
        });
        continue;
      }

      if (m.hasImage) {
        // Multi-modal content array
        final contentParts = m.parts.map((p) {
          if (p is TextPart) return {'type': 'text', 'text': p.text};
          if (p is ImageUrlPart) {
            return {
              'type': 'image_url',
              'image_url': {'url': p.url, 'detail': p.detail},
            };
          }
          return {'type': 'text', 'text': ''};
        }).toList();
        list.add({'role': m.role.name, 'content': contentParts});
      } else {
        // Plain text
        list.add({'role': m.role.name, 'content': m.content});
      }
    }
    return list;
  }

  /// 把 ApiConfig 转换为请求 body 的额外参数（默认实现）
  /// Provider 可在自身中重写以注入特有参数（如 thinking、max_completion_tokens）
  static Map<String, dynamic> buildRequestExtras(ApiConfig config) {
    return {
      'temperature': config.temperature,
      'top_p': config.topP,
      'max_tokens': config.maxTokens,
    };
  }

  /// 把工具定义列表序列化为 OpenAI 兼容的 tools JSON
  ///
  /// 形如：
  /// ```json
  /// [
  ///   {"type": "function", "function": {"name": "...", "description": "...", "parameters": {...}}}
  /// ]
  /// ```
  static List<Map<String, dynamic>> serializeTools(
    List<LlmToolDefinition>? tools,
  ) {
    if (tools == null || tools.isEmpty) return const [];
    return tools.map((t) {
      return {
        'type': 'function',
        'function': {
          'name': t.name,
          'description': t.description,
          'parameters': t.parameters,
        },
      };
    }).toList();
  }
}

class ProviderModelPreset {
  const ProviderModelPreset({
    required this.id,
    required this.displayName,
    this.contextWindow = 8192,
    this.maxOutputTokens = 4096,
    this.description,
  });
  final String id;
  final String displayName;
  final int contextWindow;
  final int maxOutputTokens;
  final String? description;
}
