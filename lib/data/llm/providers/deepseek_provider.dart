import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../core/core.dart';
import '../../../core/util/talker_service.dart';
import '../llm_provider.dart';
import '../models/deepseek_models.dart';

/// DeepSeek（深度求索）官方 API Provider
///
/// 走官方端点，用户只需输入 API Key 即可使用。
/// 支持思考模式（thinking），流式响应包含 reasoning_content 字段。
///
/// 文档：https://platform.deepseek.com/api-docs/zh-cn/posix/chat/create
class DeepSeekProvider implements LlmProvider {
  static const String _officialBaseUrl = 'https://api.deepseek.com';
  static const String _defaultModel = 'deepseek-flash';

  @override
  String get id => 'deepseek';

  @override
  String get displayName => 'DeepSeek';

  @override
  List<ProviderModelPreset> get supportedModels => const [
        ProviderModelPreset(
          id: 'deepseek-flash',
          displayName: 'DeepSeek Flash',
          contextWindow: 131072,
          maxOutputTokens: 8192,
          description: 'DeepSeek 快速模型，性价比高',
        ),
        ProviderModelPreset(
          id: 'deepseek-v4-pro',
          displayName: 'DeepSeek V4 Pro',
          contextWindow: 131072,
          maxOutputTokens: 8192,
          description: 'DeepSeek 旗舰模型，推理能力强',
        ),
      ];

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
        streaming: true,
        toolCalls: true,
        vision: false,
        thinking: true,
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
    if (config.providerId == 'deepseek') return true;
    final model = config.modelName.toLowerCase();
    return model.startsWith('deepseek');
  }

  @override
  Future<bool> testConnection(ApiConfig config) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_officialBaseUrl/chat/completions'),
            headers: _headers(config),
            body: jsonEncode({
              'model': _modelName(config),
              'messages': [
                {'role': 'user', 'content': 'hi'},
              ],
              'max_tokens': 1,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
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
    final thinkingEnabled = config.thinkingEnabled;

    final request = DeepSeekRequest(
      model: _modelName(config),
      messages: msgs,
      maxTokens: config.maxCompletionTokens,
      temperature: config.temperature,
      topP: config.topP,
      tools: LlmProvider.serializeTools(tools),
      toolChoice: toolChoice,
      thinking: thinkingEnabled
          ? const {'type': 'enabled'}
          : const {'type': 'disabled'},
      reasoningEffort: thinkingEnabled ? 'high' : null,
    );

    final bodyJson = jsonEncode(request.toJson());
    TalkerService.instance.llmReq(
      'POST $_officialBaseUrl/chat/completions\n'
      'Headers: {\n'
      '  Content-Type: application/json\n'
      '  Authorization: Bearer ${_maskKey(config.apiKey)}\n'
      '}\n'
      'Body: $bodyJson',
    );

    final httpRequest = http.Request(
      'POST',
      Uri.parse('$_officialBaseUrl/chat/completions'),
    );
    httpRequest.headers.addAll(_headers(config));
    httpRequest.body = bodyJson;

    http.StreamedResponse response;
    try {
      response = await httpRequest.send().timeout(const Duration(seconds: 60));
    } catch (e) {
      TalkerService.instance.llmError('网络异常: $e');
      yield LlmStreamEvent.error('网络异常：$e');
      return;
    }

    TalkerService.instance.llm('HTTP ${response.statusCode}');

    if (response.statusCode < 200 || response.statusCode >= 300) {
      TalkerService.instance.llmError('API 返回 ${response.statusCode}');
      yield LlmStreamEvent.error('API 返回 ${response.statusCode}');
      return;
    }

    String buf = '';
    int tokenCount = 0;
    bool streamEnded = false;

    // 工具调用聚合缓冲
    final toolIdByIndex = <int, String>{};
    final toolNameByIndex = <int, String>{};
    final toolArgsByIndex = <int, String>{};

    await for (final dataChunk in response.stream.transform(utf8.decoder)) {
      buf += dataChunk;

      while (!streamEnded) {
        final lineEnd = buf.indexOf('\n');
        if (lineEnd < 0) break;

        final raw = buf.substring(0, lineEnd).trim();
        buf = buf.substring(lineEnd + 1);

        if (raw.isEmpty) continue;
        if (!raw.startsWith('data:')) continue;

        final data = raw.substring(5).trim();
        if (data == '[DONE]') {
          streamEnded = true;
          TalkerService.instance.llmResp('[DONE] tokens=$tokenCount');
          break;
        }

        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final chunk = DeepSeekSSEChunk.fromJson(json);
          final choice = chunk.choices?.first;
          if (choice == null) continue;

          final delta = choice.delta;
          if (delta == null) continue;

          // 思考内容增量（DeepSeek 特有：reasoning_content）
          if (delta.reasoningContent != null &&
              delta.reasoningContent!.isNotEmpty) {
            yield LlmStreamEvent.reasoningText(delta.reasoningContent!);
          }

          // 正文内容增量
          final text = delta.content;
          if (text != null && text.isNotEmpty) {
            tokenCount += text.length;
            yield LlmStreamEvent.delta(text);
          }

          // 聚合工具调用
          final rawCalls = delta.toolCalls;
          if (rawCalls != null) {
            for (final tc in rawCalls) {
              final tIdx = tc.index ?? 0;
              if (tc.id != null) toolIdByIndex[tIdx] = tc.id!;
              final fn = tc.function;
              if (fn != null) {
                if (fn.name != null) toolNameByIndex[tIdx] = fn.name!;
                if (fn.arguments != null) {
                  toolArgsByIndex[tIdx] =
                      (toolArgsByIndex[tIdx] ?? '') + fn.arguments!;
                }
              }
            }
          }

          // 流结束
          if (choice.finishReason != null) {
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
              yield LlmStreamEvent.toolCalls(calls);
            }
            break;
          }
        } catch (_) {}
      }
      if (streamEnded) break;
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

    TalkerService.instance.llm('STREAM END (buffer exhausted)');
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

    final request = DeepSeekRequest(
      model: _modelName(config),
      messages: msgs,
      stream: false,
      maxTokens: config.maxCompletionTokens,
      temperature: config.temperature,
      topP: config.topP,
      tools: LlmProvider.serializeTools(tools),
      toolChoice: toolChoice,
      thinking: thinkingEnabled
          ? const {'type': 'enabled'}
          : const {'type': 'disabled'},
      reasoningEffort: thinkingEnabled ? 'high' : null,
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
