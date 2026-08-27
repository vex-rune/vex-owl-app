import 'dart:async';
import 'dart:ui';

import '../model/agent_request.dart';
import '../model/agent_response.dart';
import '../model/message.dart';
import '../model/owl_config.dart';

/// 流式聊天的"代理"抽象。
///
/// 一个 [Agent] 代表一种模型编排策略(快问快答 / RAG / 多模态等)。
/// 启动一次 Agent 会得到一个 [AgentRun] 句柄,UI 通过订阅它拿到流式
/// [AgentResponse] 与生命周期回调。
///
/// **重要**:Agent 本身**不执行任何持久化操作**(不读 / 不写 messageRepository),
/// 也不接触数据库模型 [Message]。所有 DB 操作由 [ConversationService] 完成:
/// Service 把历史 [Message] 转成 [AgentResponse] 喂给 Agent,
/// Agent 流式产出 [AgentResponse],Service 收到后再补 DB 字段落库。
/// 这样 Agent 层是干净的 LLM 抽象,可以独立测试与复用。
abstract class Agent {
  AgentRun run({
    required AgentHandle handle,
    required OwlConfig config,
  });
}

/// Agent 上下文入口。承载一次运行所需的最小信息。
///
/// [history] 是一组 [AgentResponse](不是 [Message])——
/// 由 [ConversationService] 从已持久化的 [Message] 列表翻译而成。
/// Agent 内部不再访问 MessageRepository,只消费 [AgentResponse] 即可。
class AgentHandle {
  final String conversationId;
  final List<AgentResponse> history;
  const AgentHandle({
    required this.conversationId,
    required this.history,
  });
}

/// 终态信号(用于 doFinally)。
enum AgentSignal { completed, cancelled, errored }

/// Agent 单次运行的句柄。**必须显式调用 [subscribe] 才会激活**。
abstract class AgentRun implements Disposable {
  /// 订阅,返回链式回调句柄 [AgentSubscription]。
  AgentSubscription subscribe();

  /// 是否已释放(controller 已 close,无法再订阅)。
  bool get isDisposed;
}

/// 订阅链:对 Reactor / Flux 风格 doOnXXX 的最小实现。
///
/// 注意:这里的 doOnXXX **不发送任何"事件"**,它们是订阅生命周期的回调;
/// 真正的"消息推送"通过 `doOnEach(AgentResponse)` 走。
abstract class AgentSubscription implements Disposable {
  AgentSubscription doFirst(VoidCallback cb);
  AgentSubscription doOnRequest(void Function(AgentRequest req) cb);
  AgentSubscription doOnEach(void Function(AgentResponse response) cb);
  AgentSubscription doOnComplete(VoidCallback cb);
  AgentSubscription doOnCancel(VoidCallback cb);
  AgentSubscription doOnTerminate(VoidCallback cb);
  AgentSubscription doOnError(
    void Function(Object error, StackTrace? stackTrace) cb,
  );
  AgentSubscription doFinally(void Function(AgentSignal signal) cb);

  /// 一次性回调:本次 AgentRun 调用的全部 [ToolCallRecord] 集合(去重、按发生顺序)。
  ///
  /// 触发时机:与 [doOnComplete] 同期;若 AgentRun 中途出错或被取消,仍然会触发,
  /// 携带"已发生的"工具调用(可能为空)。
  ///
  /// UI 可用它做"工具汇总"卡片 —— 把整个回合里调用了哪些工具一次性展示出来,
  /// 而不必逐条监听 [doOnEach]。
  ///
  /// 注:`ToolCallRecord` 来自 message.dart,Agent 仅以"数据载体"形式复用,
  /// 不读 [Message] 的 DB 字段。
  AgentSubscription doOnTools(void Function(List<ToolCallRecord> tools) cb);

  /// 主动取消订阅,触发 doOnCancel + doOnTerminate + doFinally(cancelled)。
  @override
  Future<void> dispose();

  bool get isDisposed;
}

/// 通用 Disposable 顶层接口(对应 Reactor 的 Disposable)。
abstract class Disposable {
  Future<void> dispose();
}