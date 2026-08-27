import '../model/message.dart';

/// 会话消息仓储。
///
/// 会话 (Session) 与消息 (Message) 是两个不同的聚合根:
/// `SessionRepository` 只负责会话的元数据(create/findById/rename/pin/delete...),
/// 消息的读写与生命周期交给本接口;职责分离后两边可以独立演进与测试。
///
/// 流式生命周期:
/// 1. [append] 写入 assistant 占位消息(`streaming == true`);
/// 2. 应用层每收到一段增量,可调 [appendDelta] 把内容拼到末尾(也可只在内存里累积);
/// 3. 流结束调 [finalize] 一次性覆盖最终内容,标记 `streaming = false`,
///    并把工具调用记录序列化入库;
/// 4. 失败 / 取消调 [markError] 就地把占位消息改写成错误形态。
abstract class MessageRepository {
  /// 写入一条消息(用户 / 助手 / 系统)。
  ///
  /// 使用 `insert or replace` 语义,允许重复写同 ID(占位 → finalize 复用)。
  Future<void> append(Message message);

  /// 追加一段流式文本到已有消息的 `content` 末尾。
  ///
  /// [messageId] 不存在时静默 no-op。
  Future<void> appendDelta(String messageId, String delta);

  /// 加载会话的历史消息,默认 50 条。
  ///
  /// 包含 `streaming == true` 的未完成消息;
  /// 送入 LLM 前调用方需自行过滤。
  Future<List<Message>> loadHistory(String conversationId, {int limit = 50});

  /// 按 ID 查询单条消息。
  ///
  /// **场景**:ChatPage 在流式落库前先 `findById` 判断是否要"先 append 占位
  /// 还是直接 appendDelta"。`null` 表示尚未落库。
  Future<Message?> findById(String messageId);

  /// 订阅会话消息变更,首次订阅发快照,后续每次写入重发。
  ///
  /// 用于 UI 监听 AgentRun 在 doOnEach / doOnComplete 中持续落库的事件。
  Stream<List<Message>> watch(String conversationId);

  /// 结束一条流式消息,把最终内容与工具调用记录落盘。
  ///
  /// 必须由 [append] 先以 `streaming == true` 写入过同 ID。
  Future<void> finalize(
    String messageId, {
    required String content,
    List<ToolCallRecord>? toolCalls,
  });

  /// 把一条 assistant 占位消息就地改写为错误形态。
  ///
  /// [messageId] 不存在时静默 no-op。
  Future<void> markError(String messageId, String errorText);
}
