/// 上游"模型请求"信息。
///
/// [AgentSubscription.doOnRequest] 回调携带该对象,
/// 描述 Agent 在工具循环中的第几轮 [attempt] 与送往模型的原始 [payload]。
///
/// 独立成文件(`core/model/agent_request.dart`)的原因:
/// 之前的实现嵌在 `agent.dart` 里,但它本质是 Agent 层使用的**数据载体**,
/// 不属于"协议"层 —— 放在 `model/` 与其他 Agent 相关数据模型([AgentResponse])
/// 一致,便于未来 Agent 子模块独立演进。
class AgentRequest {
  const AgentRequest({
    required this.attempt,
    required this.payload,
  });

  /// 工具循环的第几轮(从 0 起)。
  ///
  /// 多轮工具调用场景:`attempt = 0` 表示首次提问,`attempt = 1` 表示
  /// 工具结果回送后的第二次调用,以此类推。
  final int attempt;

  /// 模型请求的原始 payload(便于调试 / 日志)。
  ///
  /// 字段结构由 Agent 实现决定:通常包含 `messages` / `tools` / `model`
  /// 等键值,具体形态取决于 LangChain / OpenAI SDK 版本。
  final Map<String, dynamic> payload;
}