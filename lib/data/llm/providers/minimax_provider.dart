import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../core/core.dart';
import '../llm_provider.dart';
import '../models/minimax_models.dart';

/// MINIMAX（MiniMax）官方 API Provider
///
/// 走官方端点，不允许用户自定义 URL。用户只需输入 API Key 即可使用。
///
/// 文档：https://platform.minimax.cn/docs/api-reference/text-chat-openai
class MinimaxProvider implements LlmProvider {
  static const String _officialBaseUrl = 'https://api.minimax.cn/v1';
  static const String _defaultModel = 'MiniMax-M3';

  @override
  String get id => 'minimax';

  @override
  String get displayName => 'MINIMAX';

  @override
  List<ProviderModelPreset> get supportedModels => const [
    ProviderModelPreset(
      id: 'MiniMax-M3',
      displayName: 'MiniMax-M3',
      contextWindow: 128000,
      maxOutputTokens: 8192,
      description: 'MINIMAX 主力对话模型',
    ),
    ProviderModelPreset(
      id: 'MiniMax M2.7',
      displayName: 'MiniMax M2.7',
      contextWindow: 128000,
      maxOutputTokens: 8192,
      description: 'MINIMAX 高性价比模型',
    ),
  ];

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
    streaming: true,
    toolCalls: true,
    images: false,
    vision: true,
    systemPrompt: true,
  );

  @override
  ProviderConfigSchema get configSchema => const ProviderConfigSchema(
    showEndpoint: false,
    showModel: true,
    endpointFixed: true,
    modelFixed: false,
    endpointEditable: false,
    endpointDefault: _officialBaseUrl,
    modelDefault: _defaultModel,
    requiresApiKey: true,
  );

  @override
  ApiConfig resolveConfig(ApiConfig config) {
    return config.copyWith(
      apiEndpoint: _officialBaseUrl,
      modelName: config.modelName.isNotEmpty ? config.modelName : _defaultModel,
    );
  }

  @override
  bool supports(ApiConfig config) {
    if (config.providerId == 'minimax') return true;
    final model = config.modelName.toLowerCase();
    return model.startsWith('minimax') || model.startsWith('abab');
  }

  @override
  Future<bool> testConnection(ApiConfig config) async {
    // 检查 API Key 是否为空
    if (config.apiKey.isEmpty) {
      log.error('API Key 为空');
      return false;
    }

    try {
      final response = await http
          .post(
            Uri.parse('$_officialBaseUrl/chat/completions'),
            headers: {
              ..._headers(config),
              // MINIMAX 可能需要此 header
              'Stream': 'false',
            },
            body: jsonEncode({
              'model': _modelName(config),
              'messages': [
                {'role': 'user', 'content': 'hi'},
              ],
              'stream': false,
              'max_completion_tokens': 1,
              'temperature': 1.0,
            }),
          )
          .timeout(const Duration(seconds: 10));

      // 检查响应体中是否有错误（MINIMAX 可能有不同的错误格式）
      if (response.statusCode >= 400) {
        try {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          // MINIMAX 可能的错误格式
          final error = body['error']?['message'] ??
              body['message'] ??
              body['msg'] ??
              body.toString();
          log.error('API 错误: $error');
        } catch (_) {
          log.error('API 返回 ${response.statusCode}');
        }
        return false;
      }
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e, st) {
      log.error('连接异常: $e', st);
      return false;
    }
  }

  @override
  Stream<LlmStreamEvent> chatStream(
    ApiConfig config, {
    required List<Message> messages,
    String? systemPrompt,
    List<LlmToolDefinition>? tools,
  }) async* {
    final msgs = <Message>[];
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      msgs.add(Message.system(sessionId: '', content: systemPrompt));
    }
    msgs.addAll(messages);

    final toolChoice = (tools != null && tools.isNotEmpty) ? 'auto' : null;
    // 是否启用思考功能：
    // - 由 ApiConfig.thinkingEnabled 控制（用户在 API 配置中开关）
    // - 启用时必须同时 reasoningSplit=true，否则思考内容会嵌入到 content
    final thinkingEnabled = config.thinkingEnabled;
    final request = MinimaxRequest(
      model: _modelName(config),
      messages: msgs,
      maxCompletionTokens: config.maxCompletionTokens,
      temperature: config.temperature,
      topP: config.topP,
      tools: LlmProvider.serializeTools(tools),
      toolChoice: toolChoice,
      thinking: thinkingEnabled
          ? const {'type': 'adaptive'}
          : const {'type': 'disabled'},
      reasoningSplit: thinkingEnabled,
    );

    final bodyJson = jsonEncode(request.toJson());
    log.debug(
      'POST $_officialBaseUrl/chat/completions\n'
      'Headers: {\n'
      '  Content-Type: application/json\n'
      '  Authorization: Bearer ${_maskKey(config.apiKey)}\n'
      '}\n'
      'Body: <contains_messages>',
    );

    final httpRequest = http.Request(
      'POST',
      Uri.parse('$_officialBaseUrl/chat/completions'),
    );
    httpRequest.headers.addAll(_headers(config));
    httpRequest.body = bodyJson;

    http.StreamedResponse response;
    try {
      response = await httpRequest.send().timeout(
        Duration(seconds: request.timeout),
      );
    } catch (e) {
      log.error('网络异常: $e');
      yield LlmStreamEvent.error('网络异常：$e');
      return;
    }

    log.debug('HTTP ${response.statusCode}');

    if (response.statusCode < 200 || response.statusCode >= 300) {
      log.error('API 返回 ${response.statusCode}');
      yield LlmStreamEvent.error('API 返回 ${response.statusCode}');
      return;
    }

    String buf = '';
    int tokenCount = 0;
    bool streamEnded = false;

    // 工具调用聚合缓冲：按 index 累积参数 JSON
    // 每个 tool_call 的 id/name 在首个 chunk 出现，后续 chunk 续传 arguments
    final toolIdByIndex = <int, String>{};
    final toolNameByIndex = <int, String>{};
    final toolArgsByIndex = <int, String>{};

    await for (final dataChunk in response.stream.transform(utf8.decoder)) {
      buf += dataChunk;

      // 提取并处理所有完整的行
      while (!streamEnded) {
        final lineEnd = buf.indexOf('\n');
        if (lineEnd < 0) break; // 还没收到完整一行

        final raw = buf.substring(0, lineEnd).trim();
        buf = buf.substring(lineEnd + 1);

        if (raw.isEmpty) continue;
        if (!raw.startsWith('data:')) continue;

        final data = raw.substring(5).trim();
        if (data == '[DONE]') {
          // [DONE] 仅作兼容性兜底，实际以 finish_reason 为准
          streamEnded = true;
          log.info('[DONE] tokens=$tokenCount');
          break;
        }

        final Map<String, dynamic> json;
        try {
          json = jsonDecode(data) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }

        final chunk = MinimaxChunk.fromJson(json);
        final choice = chunk.choices.isNotEmpty ? chunk.choices.first : null;
        final delta = choice?.delta;
        final text = delta?.content;
        final reasoningText = delta?.reasoningContent;

        // 打印每个 chunk（不裁剪）
        log.debug(
          'CHUNK[${chunk.id}] '
          '${text ?? ""} '
          '${reasoningText != null ? "💭[${reasoningText}]" : ""} '
          '${choice?.finishReason != null ? "[${choice!.finishReason}]" : ""}',
        );

        // 增量思考内容（reasoning_split 启用时，单独 yield 一个事件）
        if (reasoningText != null && reasoningText.isNotEmpty) {
          yield LlmStreamEvent.reasoningText(reasoningText);
        }

        // 聚合工具调用 delta
        if (delta?.toolCalls != null) {
          for (final tc in delta!.toolCalls!) {
            final idx = tc.index ?? 0;
            if (tc.id != null) toolIdByIndex[idx] = tc.id!;
            if (tc.function?.name != null) {
              toolNameByIndex[idx] = tc.function!.name!;
            }
            if (tc.function?.arguments != null) {
              toolArgsByIndex[idx] =
                  (toolArgsByIndex[idx] ?? '') + tc.function!.arguments!;
            }
          }
        }

        // 流结束：finish_reason 为 stop / tool_calls / length
        if (choice != null && choice.finishReason != null) {
          streamEnded = true;
          log.info(
            '[${choice.finishReason}] tokens=$tokenCount',
          );
          // 该 chunk 可能同时含 content
          if (text != null && text.isNotEmpty) {
            tokenCount += text.length;
            yield LlmStreamEvent.delta(text);
          }

          // 如果 finish_reason 是 tool_calls，yield 聚合后的工具调用
          if (choice.finishReason == 'tool_calls' &&
              toolIdByIndex.isNotEmpty) {
            final calls = <LlmToolCall>[];
            for (final entry in toolIdByIndex.entries) {
              calls.add(LlmToolCall(
                id: entry.value,
                name: toolNameByIndex[entry.key] ?? '',
                arguments: toolArgsByIndex[entry.key] ?? '',
              ));
            }
            log.info(
              '🔧 工具调用 ${calls.length} 个：${calls.map((c) => c.name).join(', ')}',
            );
            yield LlmStreamEvent.toolCalls(calls);
          }
          break;
        }

        // 增量文本
        if (text != null && text.isNotEmpty) {
          tokenCount += text.length;
          yield LlmStreamEvent.delta(text);
        }
      }
    }

    // 兜底：流意外断开但已聚合到工具调用
    if (!streamEnded && toolIdByIndex.isNotEmpty) {
      final calls = <LlmToolCall>[];
      for (final entry in toolIdByIndex.entries) {
        calls.add(LlmToolCall(
          id: entry.value,
          name: toolNameByIndex[entry.key] ?? '',
          arguments: toolArgsByIndex[entry.key] ?? '',
        ));
      }
      yield LlmStreamEvent.toolCalls(calls);
    }

    log.debug('STREAM END (buffer exhausted)');
    yield LlmStreamEvent.done(const LlmUsage());
  }

  @override
  Future<String> chatComplete(
    ApiConfig config, {
    required List<Message> messages,
    String? systemPrompt,
    List<LlmToolDefinition>? tools,
  }) async {
    final msgs = <Message>[];
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      msgs.add(Message.system(sessionId: '', content: systemPrompt));
    }
    msgs.addAll(messages);

    final toolChoice = (tools != null && tools.isNotEmpty) ? 'auto' : null;
    final thinkingEnabled = config.thinkingEnabled;
    final request = MinimaxRequest(
      model: _modelName(config),
      messages: msgs,
      stream: false,
      maxCompletionTokens: config.maxCompletionTokens,
      temperature: config.temperature,
      topP: config.topP,
      tools: LlmProvider.serializeTools(tools),
      toolChoice: toolChoice,
      thinking: thinkingEnabled
          ? const {'type': 'adaptive'}
          : const {'type': 'disabled'},
      reasoningSplit: thinkingEnabled,
    );

    final response = await http
        .post(
          Uri.parse('$_officialBaseUrl/chat/completions'),
          headers: _headers(config),
          body: jsonEncode(request.toJson()),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('API 调用失败：${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = json['choices'] as List?;
    final msg = choices?.first?['message'] as Map<String, dynamic>?;
    if (msg == null) return '';
    // 非流式下若返回 tool_calls，抛出（由 ChatController 走流式流程）
    if (msg['tool_calls'] is List && (msg['tool_calls'] as List).isNotEmpty) {
      throw Exception('chatComplete 不支持 tool_calls，请改用 chatStream');
    }
    return msg['content'] as String? ?? '';
  }

  String _modelName(ApiConfig config) {
    return config.modelName.isNotEmpty ? config.modelName : _defaultModel;
  }

  Map<String, String> _headers(ApiConfig config) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ${config.apiKey}',
  };

  String _maskKey(String key) {
    if (key.length <= 8) return '****';
    return '${key.substring(0, 4)}...${key.substring(key.length - 4)}';
  }
}
