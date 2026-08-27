import 'message.dart';

/// 一次助手回合(Assistant Turn)。
///
/// 一回合 = 用户发出一条消息后,助手产生的所有事件(thinking / text /
/// tool_call / tool_result / plan / error),以同一 [turnId] 关联。
///
/// 模型职责:
/// * 不持有"运行中"状态 —— 是否流式由 [Message.streaming] 判断;
/// * 不存储额外的存储结构 —— 仅作为 UI 渲染层 / 查询层的临时聚合对象;
/// * 不引入新的持久化形式 —— DB 仍是"每事件一行 Message"。
///
/// 排序保证:
/// [events] 按 [Message.createdAt] 升序 —— 反映真实的执行时序。
class AssistantTurn {
  AssistantTurn._({required this.turnId, required this.events});

  /// 构造并校验事件序列。
  ///
  /// * [turnId] 非空;
  /// * 所有事件都满足 `event.turnId == turnId`;
  /// * 所有事件都满足 `event.role == MessageRole.assistant || event.role == MessageRole.tool`;
  /// * 按 createdAt 升序排列。
  ///
  /// 校验失败时抛 [ArgumentError] —— 应当由调用方(纯函数 [groupTurns])保证合法性,
  /// 这里仅做防御性断言。
  factory AssistantTurn.from(String turnId, List<Message> events) {
    assert(turnId.isNotEmpty, 'turnId 不能为空');
    final sorted = [...events]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final e in sorted) {
      assert(e.turnId == turnId, '事件 turnId 与聚合 turnId 不一致');
      assert(
        e.role == MessageRole.assistant || e.role == MessageRole.tool,
        '回合内只能包含 assistant / tool 角色',
      );
    }
    return AssistantTurn._(turnId: turnId, events: sorted);
  }

  final String turnId;
  final List<Message> events;

  /// 最后一条非流式的 text 事件内容(若有)。
  ///
  /// 助手"最终回复"文本 = 回合内最后一条 type == text 且 streaming == false 的
  /// Message.content。若不存在(回合被取消 / 中断),返回 null。
  String? get finalText {
    Message? last;
    for (final e in events) {
      if (e.type == MessageType.text && !e.streaming) last = e;
    }
    return last?.content;
  }

  /// 思考过程(若有)。
  Message? get thinking => events.cast<Message?>().firstWhere(
    (m) => m?.type == MessageType.thinking,
    orElse: () => null,
  );

  /// 工具调用行(role=assistant + type=toolCall),按发生顺序。
  List<Message> get toolCalls => events
      .where((m) =>
          m.type == MessageType.toolCall && m.role == MessageRole.assistant)
      .toList(growable: false);

  /// 工具结果行(role=tool + type=toolCall),按发生顺序。
  List<Message> get toolResults => events
      .where((m) =>
          m.type == MessageType.toolCall && m.role == MessageRole.tool)
      .toList(growable: false);

  /// 错误(若有)。
  Message? get error => events.cast<Message?>().firstWhere(
    (m) => m?.type == MessageType.error,
    orElse: () => null,
  );

  /// 是否仍在流式输出中 —— 任意事件 streaming == true 即视为进行中。
  bool get isStreaming => events.any((m) => m.streaming);

  @override
  String toString() => 'AssistantTurn($turnId, ${events.length} events)';
}

/// 把扁平的消息列表拆分为"用户消息 / 助手回合"序列,保持原有顺序。
///
/// 规则:
/// 1. 按 [Message.createdAt] 升序;
/// 2. `role == user`  → 作为独立 [Message] 元素保留;
/// 3. `role ∈ {assistant, tool}` 且 `turnId != null` → 按 turnId 聚合为 [AssistantTurn];
/// 4. `role ∈ {assistant, tool}` 且 `turnId == null`(历史数据) → 退化为"单事件回合",
///    用消息自身 id 作为 turnId(向后兼容,不会跨回合串)。
///
/// 返回的元素类型:[Message] 表示用户消息,[AssistantTurn] 表示助手回合。
List<Object> groupTurns(List<Message> messages) {
  final sorted = [...messages]
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  final byTurnId = <String, List<Message>>{};
  final result = <Object>[];
  final emittedTurnIds = <String>{};

  for (final m in sorted) {
    final isAssistantSide =
        m.role == MessageRole.assistant || m.role == MessageRole.tool;
    if (!isAssistantSide) {
      result.add(m);
      continue;
    }
    final tid = m.turnId ?? m.id;
    byTurnId.putIfAbsent(tid, () => []).add(m);
    if (emittedTurnIds.add(tid)) {
      result.add(AssistantTurn.from(tid, byTurnId[tid]!));
    } else {
      // 同一 turnId 已发出,需要把已发出的回合替换为最新的(包含新事件)。
      final idx = result.indexWhere(
        (e) => e is AssistantTurn && e.turnId == tid,
      );
      if (idx >= 0) {
        result[idx] = AssistantTurn.from(tid, byTurnId[tid]!);
      }
    }
  }

  return result;
}