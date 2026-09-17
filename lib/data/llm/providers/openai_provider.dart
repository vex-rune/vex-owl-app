import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../core/core.dart';
import '../llm_provider.dart';

/// 通用 OpenAI 兼容 Provider
///
/// 作为任何未明确支持的 OpenAI 兼容 API 的回退实现。
class OpenAiProvider implements LlmProvider {
  @override
  String get id => 'openai';

  @override
  String get displayName => 'OpenAI 兼容';

  @override
  List<ProviderModelPreset> get supportedModels => const [];

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
    streaming: true,
    toolCalls: true,
    vision: true,
    systemPrompt: true,
  );

  /// OpenAI 兼容 Provider：完全可编辑
  @override
  ProviderConfigSchema get configSchema => const ProviderConfigSchema(
    showEndpoint: true,
    showModel: true,
    endpointFixed: false,
    modelFixed: false,
    endpointEditable: true,
    endpointDefault: 'https://api.openai.com/v1',
    modelDefault: 'gpt-4o',
    requiresApiKey: true,
  );

  /// OpenAI 兼容 Provider 不做强制覆盖，由用户完全控制
  @override
  ApiConfig resolveConfig(ApiConfig config) => config;

  @override
  bool supports(ApiConfig config) {
    if (config.apiEndpoint.isEmpty) return false;
    // 只要 endpoint 非空且没被其他 Provider 匹配，就用本实现
    return true;
  }

  @override
  Future<bool> testConnection(ApiConfig config) async {
    try {
      final response = await http
          .post(
            Uri.parse('${_base(config)}/chat/completions'),
            headers: _headers(config),
            body: jsonEncode({
              'model': config.modelName,
              'messages': [{'role': 'user', 'content': 'hi'}],
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
    final toolChoice = (tools != null && tools.isNotEmpty) ? 'auto' : null;
    final toolJson = LlmProvider.serializeTools(tools);
    final request = http.Request('POST', Uri.parse('${_base(config)}/chat/completions'));
    request.headers.addAll(_headers(config));
    final body = <String, dynamic>{
      'model': config.modelName,
      'messages': LlmProvider.serializeMessages(messages, systemPrompt: systemPrompt),
      'stream': true,
      ...LlmProvider.buildRequestExtras(config),
      if (toolJson.isNotEmpty) ...{
        'tools': toolJson,
        'tool_choice': toolChoice,
      },
    };
    request.body = jsonEncode(body);

    http.StreamedResponse response;
    try {
      response = await request.send().timeout(const Duration(seconds: 60));
    } catch (e) {
      yield LlmStreamEvent.error('网络异常：$e');
      return;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      yield LlmStreamEvent.error('HTTP ${response.statusCode}');
      return;
    }

    String buf = '';
    // 工具调用聚合缓冲
    final toolIdByIndex = <int, String>{};
    final toolNameByIndex = <int, String>{};
    final toolArgsByIndex = <int, String>{};

    await for (final chunk in response.stream.transform(utf8.decoder)) {
      buf += chunk;
      while (buf.contains('\n')) {
        final idx = buf.indexOf('\n');
        final raw = buf.substring(0, idx).trim();
        buf = buf.substring(idx + 1);
        if (!raw.startsWith('data:')) continue;
        final data = raw.substring(5).trim();
        if (data == '[DONE]') {
          yield LlmStreamEvent.done(const LlmUsage());
          return;
        }
        try {
          final json = jsonDecode(data);
          final choice = json['choices']?[0];
          final delta = choice?['delta'];
          final text = delta?['content'];
          if (text is String && text.isNotEmpty) {
            yield LlmStreamEvent.delta(text);
          }
          // 聚合工具调用
          final rawCalls = delta?['tool_calls'] as List?;
          if (rawCalls != null) {
            for (final tc in rawCalls) {
              final tcMap = tc as Map<String, dynamic>;
              final tIdx = tcMap['index'] as int? ?? 0;
              if (tcMap['id'] is String) {
                toolIdByIndex[tIdx] = tcMap['id'] as String;
              }
              final fn = tcMap['function'] as Map?;
              if (fn != null) {
                if (fn['name'] is String) {
                  toolNameByIndex[tIdx] = fn['name'] as String;
                }
                if (fn['arguments'] is String) {
                  toolArgsByIndex[tIdx] =
                      (toolArgsByIndex[tIdx] ?? '') + fn['arguments'] as String;
                }
              }
            }
          }
          // 流结束
          if (choice?['finish_reason'] != null) {
            if ((choice['finish_reason'] as String) == 'tool_calls' &&
                toolIdByIndex.isNotEmpty) {
              final calls = toolIdByIndex.entries
                  .map((e) => LlmToolCall(
                        id: e.value,
                        name: toolNameByIndex[e.key] ?? '',
                        arguments: toolArgsByIndex[e.key] ?? '',
                      ))
                  .toList();
              yield LlmStreamEvent.toolCalls(calls);
            }
            yield LlmStreamEvent.done(const LlmUsage());
            return;
          }
        } catch (_) {}
      }
    }
    yield LlmStreamEvent.done(const LlmUsage());
  }

  @override
  Future<String> chatComplete(
    ApiConfig config, {
    required List<Message> messages,
    String? systemPrompt,
    List<LlmToolDefinition>? tools,
  }) async {
    final toolChoice = (tools != null && tools.isNotEmpty) ? 'auto' : null;
    final toolJson = LlmProvider.serializeTools(tools);
    final response = await http
        .post(
          Uri.parse('${_base(config)}/chat/completions'),
          headers: _headers(config),
          body: jsonEncode({
            'model': config.modelName,
            'messages': LlmProvider.serializeMessages(messages, systemPrompt: systemPrompt),
            ...LlmProvider.buildRequestExtras(config),
            if (toolJson.isNotEmpty) ...{
              'tools': toolJson,
              'tool_choice': toolChoice,
            },
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final json = jsonDecode(response.body);
    final msg = json['choices']?[0]?['message'];
    if (msg?['tool_calls'] is List && (msg['tool_calls'] as List).isNotEmpty) {
      throw Exception('chatComplete 不支持 tool_calls，请改用 chatStream');
    }
    return msg?['content'] as String? ?? '';
  }

  String _base(ApiConfig config) {
    final url = config.apiEndpoint.trim();
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  Map<String, String> _headers(ApiConfig config) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${config.apiKey}',
      };
}
