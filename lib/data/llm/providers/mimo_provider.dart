import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../core/core.dart';
import '../llm_provider.dart';
import '../models/mimo_models.dart';

/// MiMo（小米）API Provider
///
/// MiMo 模型通过 vLLM / SGLang 等推理引擎自部署，
/// API 完全兼容 OpenAI 格式。用户需要自行配置部署端点。
///
/// 模型：MiMo-7B-RL, MiMo-7B-RL-0530
/// 部署文档：https://github.com/XiaomiMiMo/MiMo
class MimoProvider implements LlmProvider {
  static const String _defaultModel = 'mimo-v2.5-pro';
  static const String _defaultEndpoint = 'https://token-plan-cn.xiaomimimo.com/v1';

  @override
  String get id => 'mimo';

  @override
  String get displayName => 'MiMo (小米)';

  @override
  List<ProviderModelPreset> get supportedModels => const [
        ProviderModelPreset(
          id: 'mimo-v2.5-pro',
          displayName: 'MiMo V2.5 Pro',
          contextWindow: 32768,
          maxOutputTokens: 8192,
          description: '小米 MiMo V2.5 Pro 推理模型',
        ),
        ProviderModelPreset(
          id: 'mimo-v2.5',
          displayName: 'MiMo V2.5',
          contextWindow: 32768,
          maxOutputTokens: 8192,
          description: '小米 MiMo V2.5 模型',
        ),
      ];

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
        streaming: true,
        toolCalls: true,
        vision: false,
        thinking: false,
        systemPrompt: true,
      );

  @override
  ProviderConfigSchema get configSchema => const ProviderConfigSchema(
        showEndpoint: true,
        showModel: true,
        endpointFixed: false,
        modelFixed: false,
        endpointEditable: true,
        endpointDefault: _defaultEndpoint,
        modelDefault: _defaultModel,
        requiresApiKey: false,
      );

  @override
  ApiConfig resolveConfig(ApiConfig config) {
    final endpoint = config.apiEndpoint.isNotEmpty
        ? config.apiEndpoint
        : _defaultEndpoint;
    return config.copyWith(
      apiEndpoint: endpoint,
      modelName:
          config.modelName.isNotEmpty ? config.modelName : _defaultModel,
    );
  }

  @override
  bool supports(ApiConfig config) {
    if (config.providerId == 'mimo') return true;
    final model = config.modelName.toLowerCase();
    return model.startsWith('mimo');
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
            Uri.parse('${_base(config)}/chat/completions'),
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
      // 检查响应体中是否有错误
      if (response.statusCode >= 400) {
        try {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          final error = body['error']?['message'] ?? body['message'];
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
    final toolChoice = (tools != null && tools.isNotEmpty) ? 'auto' : null;
    final toolJson = LlmProvider.serializeTools(tools);

    final request = http.Request(
      'POST',
      Uri.parse('${_base(config)}/chat/completions'),
    );
    request.headers.addAll(_headers(config));

    final body = <String, dynamic>{
      'model': _modelName(config),
      'messages':
          LlmProvider.serializeMessages(messages, systemPrompt: systemPrompt),
      'stream': true,
      ...LlmProvider.buildRequestExtras(config),
      if (toolJson.isNotEmpty) ...{
        'tools': toolJson,
        'tool_choice': toolChoice,
      },
    };
    request.body = jsonEncode(body);

    log.debug(
      'POST ${_base(config)}/chat/completions\n'
      'Headers: {\n'
      '  Content-Type: application/json\n'
      '  Authorization: Bearer ${_maskKey(config.apiKey)}\n'
      '}\n'
      'Body: <contains_api_key>',
    );

    http.StreamedResponse response;
    try {
      response = await request.send().timeout(const Duration(seconds: 60));
    } catch (e) {
      log.error('网络异常: $e');
      yield LlmStreamEvent.error('网络异常：$e');
      return;
    }

    log.debug('HTTP ${response.statusCode}');

    if (response.statusCode < 200 || response.statusCode >= 300) {
      yield LlmStreamEvent.error('HTTP ${response.statusCode}');
      return;
    }

    String buf = '';
    bool streamEnded = false;

    // 工具调用聚合缓冲
    final toolIdByIndex = <int, String>{};
    final toolNameByIndex = <int, String>{};
    final toolArgsByIndex = <int, String>{};

    await for (final chunk in response.stream.transform(utf8.decoder)) {
      buf += chunk;

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
          break;
        }

        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final chunkObj = MimoSSEChunk.fromJson(json);
          final choice = chunkObj.choices?.first;
          if (choice == null) continue;

          final delta = choice.delta;
          if (delta == null) continue;

          // 正文内容增量
          final text = delta.content;
          if (text != null && text.isNotEmpty) {
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
            'model': _modelName(config),
            'messages': LlmProvider.serializeMessages(
                messages, systemPrompt: systemPrompt),
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

  String _modelName(ApiConfig config) {
    return config.modelName.isNotEmpty ? config.modelName : _defaultModel;
  }

  Map<String, String> _headers(ApiConfig config) => {
        'Content-Type': 'application/json',
        if (config.apiKey.isNotEmpty)
          'Authorization': 'Bearer ${config.apiKey}',
      };

  String _maskKey(String key) {
    if (key.length <= 8) return '****';
    return '${key.substring(0, 4)}...${key.substring(key.length - 4)}';
  }
}
