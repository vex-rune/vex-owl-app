import 'dart:async';
import 'dart:ui';

import 'package:langchain/langchain.dart' as lc;
import 'package:langchain_openai/langchain_openai.dart';

import '../model/agent_request.dart';
import '../model/agent_response.dart';
import '../model/message.dart';
import '../model/owl_config.dart';
import '../util/think_parser.dart';
import 'agent.dart';
import 'tool_registry.dart';

/// 快问快答 Agent。
///
/// **Agent 层不接触数据库**:emit 的是 [AgentResponse](无 DB 字段,
/// 通过 sealed class 区分 thinking / text / tool_call / tool_result / finish),
/// 由 [ConversationService] 在收到后负责补 conversationId / turnId /
/// createdAt / streaming 等字段落库为 [Message]。
///
/// 行为流程:
/// 1. emit [AgentThinking] 占位;
/// 2. 调 [ChatOpenAI.stream] 累积 [accumulator],每段 emit 一次 [AgentText];
/// 3. 若流结束时带 [lc.AIChatMessageToolCall],进入工具循环(最多 [maxToolRounds] 轮);
///    每轮 emit `AgentToolCall` + `AgentToolResult`;
/// 4. 终态 emit `AgentFinish(reason: complete)`;
/// 5. 失败 emit `AgentFinish(reason: error, errorMessage: ...)`。
///
/// 每次 emit 都携带 [AgentResponseMetadata]:
/// * [AgentResponseMetadata.modelName] / [modelParams] 在创建 ChatOpenAI 时确定;
/// * [AgentResponseMetadata.usage] 仅终态 [AgentFinish] 携带完整值。
///
/// **所有 [MessageRepository] 调用由 ConversationService 完成** —— Agent 只产出内容。
class QuickAgent implements Agent {
  QuickAgent({
    required this.chat,
    required this.toolRegistry,
    this.maxToolRounds = 5,
  });

  final ChatOpenAI chat;
  final ToolRegistry toolRegistry;
  final int maxToolRounds;

  @override
  AgentRun run({required AgentHandle handle, required OwlConfig config}) {
    final controller = StreamController<AgentResponse>.broadcast();
    final metadata = AgentResponseMetadata(
      modelName: chat.defaultOptions.model ?? config.model,
      modelParams: {
        'temperature': chat.defaultOptions.temperature,
        // 后续如有 topP / maxTokens 等字段,继续追加。
      },
    );
    _runInner(handle, config, controller, metadata);

    return _QuickAgentRun(controller.stream, () => controller.close());
  }

  Future<void> _runInner(
    AgentHandle handle,
    OwlConfig config,
    StreamController<AgentResponse> controller,
    AgentResponseMetadata metadata,
  ) async {
    try {
      // 1. 构造 messages(系统提示 + 历史 AgentResponse)
      final messages = <lc.ChatMessage>[
        lc.ChatMessage.system(
          '你是灵枭,一个简洁、高效的本地 AI 助手。回答尽量精炼,必要时可调用工具。',
        ),
        ...handle.history.map(_toLcMessage),
      ];

      final toolSpecs = toolRegistry.specs();
      lc.ChatResult? lastAccumulator;

      for (var round = 0; round < maxToolRounds; round++) {
        // 流式调用 ChatOpenAI
        final stream = chat.stream(
          lc.PromptValue.chat(messages),
          options: ChatOpenAIOptions(model: config.model, tools: toolSpecs),
        );

        // 用 langchain 自带的 ChatResult.concat 累积流式片段
        var accumulator = _emptyChatResult();
        // 解析 <think>...</think> 标签的流式状态机(独立模块 lib/core/util/think_parser.dart)
        final parser = ThinkParser();
        await for (final chunk in stream) {
          // chunk.output.content 是本段 delta(不是累积全文)
          // parser 拆出 think / text,由本层 emit AgentThinking / AgentText
          for (final c in parser.feed(chunk.output.content)) {
            switch (c) {
              case ThinkThinking(:final content):
                controller.add(AgentThinking(content: content, metadata: metadata));
              case ThinkText(:final content):
                controller.add(AgentText(content: content, metadata: metadata));
            }
          }
          accumulator = accumulator.concat(chunk);
        }
        // 流结束 flush 残留(标签未闭合等边界情况)
        for (final c in parser.close()) {
          switch (c) {
            case ThinkThinking(:final content):
              controller.add(AgentThinking(content: content, metadata: metadata));
            case ThinkText(:final content):
              controller.add(AgentText(content: content, metadata: metadata));
          }
        }

        lastAccumulator = accumulator;
        final ai = accumulator.output;
        if (ai.toolCalls.isEmpty) break; // 本轮无工具调用,退出循环

        // 3. 工具调用:emit AgentToolCall + AgentToolResult
        for (final tc in ai.toolCalls) {
          // tool_call 行
          controller.add(AgentToolCall(
            callId: tc.id,
            name: tc.name,
            args: tc.arguments,
            metadata: metadata,
          ));

          // 执行工具
          final output = await toolRegistry.execute(tc.name, tc.arguments);

          // tool_result 行
          controller.add(AgentToolResult(
            callId: tc.id,
            name: tc.name,
            output: output,
            metadata: metadata,
          ));

          messages.add(lc.ChatMessage.tool(toolCallId: tc.id, content: output));
        }
        messages.add(ai);
      }

      // 4. 终态:done —— Service 收到后 finalize 占位 + bumpRound
      final finalUsage = lastAccumulator?.usage;
      controller.add(AgentFinish(
        reason: AgentFinishReason.complete,
        usage: finalUsage == null
            ? null
            : TokenUsage(
                promptTokens: finalUsage.promptTokens,
                completionTokens: finalUsage.responseTokens,
                totalTokens: finalUsage.totalTokens,
              ),
        metadata: metadata,
      ));
      await controller.close();
    } catch (e) {
      // 5. 失败:emit error —— Service 收到后 markError
      controller.add(AgentFinish(
        reason: AgentFinishReason.error,
        errorMessage: e.toString(),
        metadata: metadata,
      ));
      await controller.close();
    }
  }

  /// Agent 历史(historical [AgentResponse])→ langchain [lc.ChatMessage] 翻译。
  ///
  /// 用途:把上游已持久化的"非 DB 化"消息送回模型。
  lc.ChatMessage _toLcMessage(AgentResponse r) {
    return switch (r) {
      AgentText() => lc.ChatMessage.ai(r.content),
      AgentThinking() => lc.ChatMessage.ai(''), // 不回送 thinking
      AgentToolCall() => lc.ChatMessage.ai(''), // 单事件不属于完整消息
      AgentToolResult() => lc.ChatMessage.tool(
          toolCallId: r.callId,
          content: r.output,
        ),
      AgentFinish() => lc.ChatMessage.ai(''), // 终态不回送
    };
  }

  lc.ChatResult _emptyChatResult() => lc.ChatResult(
    id: '',
    output: const lc.AIChatMessage(content: ''),
    finishReason: lc.FinishReason.unspecified,
    metadata: const {},
    usage: const lc.LanguageModelUsage(),
  );

  /// Agent 自身不再生成 ID —— turnId 由 [ConversationService] 统一分配,
/// 以保持 Agent 层与 DB 概念彻底解耦。
}

/// QuickAgent 的 AgentRun 包装。
class _QuickAgentRun implements AgentRun {
  _QuickAgentRun(this._stream, this._closer);

  final Stream<AgentResponse> _stream;
  final Future<void> Function() _closer;

  bool _disposed = false;

  @override
  AgentSubscription subscribe() => _QuickAgentSubscription(_stream, _closer);

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _closer();
  }

  @override
  bool get isDisposed => _disposed;
}

/// 链式回调订阅实现(QuickAgent 专用)。
class _QuickAgentSubscription implements AgentSubscription {
  _QuickAgentSubscription(this._stream, this._closer) {
    _subscribe();
  }

  final Stream<AgentResponse> _stream;
  final Future<void> Function() _closer;

  VoidCallback? _onFirst;
  void Function(AgentResponse)? _onEach;
  VoidCallback? _onComplete;
  VoidCallback? _onCancel;
  VoidCallback? _onTerminate;
  void Function(Object, StackTrace?)? _onError;
  void Function(AgentSignal)? _onFinally;
  void Function(List<ToolCallRecord>)? _onTools;

  /// 收集到的全部 tool_call(从 [AgentToolCall] 抽取),按发生顺序。
  /// 终态时一次性回调给 doOnTools。
  final List<ToolCallRecord> _tools = [];

  StreamSubscription<AgentResponse>? _sub;
  bool _disposed = false;
  bool _terminated = false;

  void _subscribe() {
    // doFirst:同步立即触发
    _onFirst?.call();

    _sub = _stream.listen(
      (response) {
        // 聚合 tool_call:从 AgentToolCall 抽取
        if (response is AgentToolCall) {
          _tools.add(ToolCallRecord(
            toolCallId: response.callId,
            name: response.name,
            args: response.args,
            output: '',
          ));
        }
        _onEach?.call(response);
      },
      onError: (e, st) {
        _onError?.call(e, st);
        _terminate(AgentSignal.errored);
      },
      onDone: () {
        _onComplete?.call();
        _terminate(AgentSignal.completed);
      },
      cancelOnError: false,
    );
  }

  Future<void> _terminate(AgentSignal signal) async {
    if (_terminated) return;
    _terminated = true;

    if (signal == AgentSignal.cancelled) {
      _onCancel?.call();
    }
    _onTerminate?.call();
    _onFinally?.call(signal);
    // 终态时一次性把工具列表回调出去(无论完整 / 异常 / 取消)。
    _onTools?.call(List.unmodifiable(_tools));

    await _sub?.cancel();
    await _closer();
  }

  @override
  AgentSubscription doFirst(VoidCallback cb) {
    _onFirst = cb;
    return this;
  }

  @override
  AgentSubscription doOnRequest(void Function(AgentRequest req) cb) {
    // QuickAgent 暂未实现 request 通知(流式场景下模型请求不可观测)
    return this;
  }

  @override
  AgentSubscription doOnEach(void Function(AgentResponse response) cb) {
    _onEach = cb;
    return this;
  }

  @override
  AgentSubscription doOnComplete(VoidCallback cb) {
    _onComplete = cb;
    return this;
  }

  @override
  AgentSubscription doOnCancel(VoidCallback cb) {
    _onCancel = cb;
    return this;
  }

  @override
  AgentSubscription doOnTerminate(VoidCallback cb) {
    _onTerminate = cb;
    return this;
  }

  @override
  AgentSubscription doOnError(
    void Function(Object error, StackTrace? stackTrace) cb,
  ) {
    _onError = cb;
    return this;
  }

  @override
  AgentSubscription doFinally(void Function(AgentSignal signal) cb) {
    _onFinally = cb;
    return this;
  }

  @override
  AgentSubscription doOnTools(void Function(List<ToolCallRecord> tools) cb) {
    _onTools = cb;
    return this;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _terminate(AgentSignal.cancelled);
  }

  @override
  bool get isDisposed => _disposed;
}