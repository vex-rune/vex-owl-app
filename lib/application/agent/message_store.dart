import '../../core/model/message.dart';
import '../../core/repository/message_repository.dart';

/// 单个 turn 的消息流式落库编排器。
///
/// **职责**:把"接收一段 delta"的请求翻译成"是首次 append 占位,还是
/// 继续 appendDelta",并把 finalize / 错误标记这些生命周期操作集中到一处。
///
/// **为何不直接放 ChatPage**:同一段判断(`findById` + 决定 append / appendDelta)
/// 在 Orchestrator、CLI 工具、测试 fixture 都会用到 —— 抽到 application 层
/// 后,ChatPage 退化成"接 InputBar.onSend → 调 store.appendDelta" 的薄壳,
/// 而核心逻辑可被 dart test 直接覆盖。
class TurnMessageStore {
  TurnMessageStore({required MessageRepository messageRepository})
      : _messageRepository = messageRepository;

  final MessageRepository _messageRepository;

  /// 把一段 delta 追加到 [turnId] 对应的 assistant 消息。
  ///
  /// 首次调用(行还不存在)会 append 一条 `streaming = true` 的占位 Message,
  /// 后续调用走 [MessageRepository.appendDelta]。
  ///
  /// 返回"这次操作是创建了占位(true)还是继续追加(false)",用于调用方埋点。
  Future<bool> appendDelta({
    required String conversationId,
    required String turnId,
    required String delta,
  }) async {
    final existing = await _messageRepository.findById(turnId);
    if (existing == null) {
      final msg = Message(
        id: turnId,
        conversationId: conversationId,
        role: MessageRole.assistant,
        type: MessageType.text,
        content: delta,
        toolCalls: null,
        createdAt: DateTime.now(),
        streaming: true,
        turnId: turnId,
      );
      await _messageRepository.append(msg);
      return true;
    }
    await _messageRepository.appendDelta(turnId, delta);
    return false;
  }

  /// 终结 turn:把 streaming 标记置 false,内容已经通过 [appendDelta] 累积完。
  ///
  /// 占位行不存在时静默 no-op(可能因 Agent 在第一段 emit 前就 fail)。
  Future<void> finalize(String turnId) async {
    final existing = await _messageRepository.findById(turnId);
    if (existing == null) return;
    await _messageRepository.finalize(
      turnId,
      content: existing.content,
      toolCalls: null,
    );
  }

  /// 把当前 turn 标为错误形态,内容已经累积的部分保留,
  /// 由 UI 渲染时识别 [MessageType.error]。
  Future<void> markError(String turnId, String errorText) async {
    await _messageRepository.markError(turnId, errorText);
  }
}
