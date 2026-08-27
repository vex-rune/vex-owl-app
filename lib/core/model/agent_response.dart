import 'message.dart';

/// Agent 层产出的事件 —— 一条 emit 对应一个具体类型。
///
/// **设计原则**:
/// * [sealed class]:用 `switch` 穷举,避免 if/else 拆包;
/// * **单一职责**:每条 response 只描述"这次 emit 的内容",不带"运行配置"
///   (模型名 / 参数 / token usage 挂在 [AgentResponseMetadata] 上);
/// * **事件 vs 内容分离**:tool_call / tool_result 是"事件",text / thinking
///   是"内容",终态是"完成信号" —— 形态不同,不应塞进同一对象。
///
/// **消费方**:
/// * [ConversationService] 收到后按 subtype 分发落库;
/// * UI 层在 ChatPage 收到翻译过的 [Message],与本类型无关。
///
/// **关于 [ToolCallRecord]**:Agent 与 UI 都需要的"工具调用数据载体",
/// 复用 message.dart 中的定义(Agent 层唯一一处触到 message.dart 的地方,
/// 仅使用 [ToolCallRecord] 类型,不读 [Message] 字段)。
sealed class AgentResponse {
  /// 本次 emit 关联的元数据(模型名 / 参数 / token 消耗)。
  ///
  /// 同一 run 内多次 emit 共用同一份元数据(创建 ChatOpenAI 时确定)。
  /// TokenUsage 仅终态 emit 携带完整值。
  final AgentResponseMetadata metadata;
  const AgentResponse({required this.metadata});
}

/// 文本片段(可携带工具调用 —— langchain 流式收尾时可能把 tool_call 附在最后一个 chunk)。
///
/// 流式过程中,LangChain 的 `ChatResult.output.toolCalls` 在累积后期
/// 会"沿途"出现 —— 业务上等价于"这段文本里还有未处理的工具调用"。
/// Agent 层如实保留,Service 层负责分类落库。
final class AgentText extends AgentResponse {
  final String content;
  final List<ToolCallRecord> toolCalls;
  const AgentText({
    required this.content,
    this.toolCalls = const [],
    required super.metadata,
  });
}

/// 思考过程片段(Chain-of-Thought)。
final class AgentThinking extends AgentResponse {
  final String content;
  const AgentThinking({required this.content, required super.metadata});
}

/// 工具调用事件(assistant 决定调用哪个 tool)。
final class AgentToolCall extends AgentResponse {
  final String callId;
  final String name;
  final Map<String, dynamic> args;
  const AgentToolCall({
    required this.callId,
    required this.name,
    required this.args,
    required super.metadata,
  });
}

/// 工具执行结果(role=tool,回写给模型继续对话)。
final class AgentToolResult extends AgentResponse {
  final String callId;
  final String name;
  final String output;
  const AgentToolResult({
    required this.callId,
    required this.name,
    required this.output,
    required super.metadata,
  });
}

/// 终态信号 —— 一回合最后一次 emit,告诉订阅方"这次 run 已结束"。
final class AgentFinish extends AgentResponse {
  final AgentFinishReason reason;

  /// 错误消息(仅 [AgentFinishReason.error] 时携带)。
  final String? errorMessage;

  /// 本次 run 累计 token 消耗(终态时由 provider 返回,流式片段为 null)。
  final TokenUsage? usage;
  const AgentFinish({
    required this.reason,
    this.errorMessage,
    this.usage,
    required super.metadata,
  });

  bool get isSuccess => reason == AgentFinishReason.complete;
  bool get isError => reason == AgentFinishReason.error;
}

/// 终态原因。
enum AgentFinishReason {
  /// 正常完成。
  complete,

  /// 因工具调用而中断(等待 tool 结果后再继续)。
  toolCall,

  /// 达到模型 max_tokens 上限。
  length,

  /// 异常终止。
  error,
}

/// 运行元数据 —— 与 [AgentResponse] 一对一捆绑,不独立 emit。
///
/// 字段含义:
/// * [modelName]:本次 run 使用的模型(如 `gpt-4o-mini` / `deepseek-chat`);
/// * [modelParams]:其他模型参数(temperature / topP / maxTokens 等),
///   形式 `Map<String, dynamic>`,便于诊断"为什么这次输出不一样";
/// * [usage]:本次 run 的 token 消耗统计;非终态 emit 上为 null,
///   仅 [AgentFinish] 携带完整 usage。
///
/// 暴露 metadata 而不藏在 run 内部:
/// UI / 日志在收到一条 emit 时,**一次性**就能拿到"这是哪个模型、用的什么参数、
/// 消耗了多少 token",无需额外 join / 回查。
final class AgentResponseMetadata {
  const AgentResponseMetadata({
    this.modelName,
    this.modelParams,
    this.usage,
  });

  final String? modelName;
  final Map<String, dynamic>? modelParams;
  final TokenUsage? usage;

  /// 空元数据占位(未知 / 测试场景)。
  static const AgentResponseMetadata empty = AgentResponseMetadata();
}

/// Token 消耗统计。
///
/// 与 langchain `LanguageModelUsage` 的映射关系:
/// * `LanguageModelUsage.promptTokens` → [promptTokens]
/// * `LanguageModelUsage.responseTokens` → [completionTokens]
/// * `LanguageModelUsage.totalTokens` → [totalTokens]
///
/// 全部字段可选 —— langchain 对流式片段的 usage 通常不完整,
/// 终态时由 provider 返回的完整 usage 给出。
class TokenUsage {
  const TokenUsage({
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
  });

  /// 输入侧 token 数。
  final int? promptTokens;

  /// 输出侧 token 数。
  final int? completionTokens;

  /// 合计 token 数。
  final int? totalTokens;
}