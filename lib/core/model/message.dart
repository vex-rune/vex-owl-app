/// 消息模型。
///
/// 不可变值类型。
///
/// 通过 [type] 区分消息内容形态:
/// * [MessageType.text]:用户输入或助手最终回复(Markdown)
/// * [MessageType.system]:注入给模型的系统提示
/// * [MessageType.toolCall]:助手触发工具调用的轨迹
/// * [MessageType.thinking]:模型推理过程(Chain-of-Thought)
/// * [MessageType.plan]:agent 在执行前发布的计划列表
/// * [MessageType.error]:对话失败/中断的错误提示(承载原始错误描述)
///
/// [role] 与 [type] 正交:`role` 描述"谁发的",
/// `type` 描述"内容是什么形态"。
class Message {
  const Message({
  required this.id,
  required this.conversationId,
  required this.role,
  required this.content,
  required this.toolCalls,
  required this.createdAt,
  required this.streaming,
  this.type,
  this.thinkingContent,
  this.planItems,
  this.turnId,
  });

  /// 消息 ID。
  final String id;

  /// 所属会话 ID。
  final String conversationId;

  /// 消息角色(谁发的)。
  final MessageRole role;

  /// 所属助手回合 id。
  ///
  /// 同一回合内的所有 Message(thinking / text / toolCall / tool_result / plan)
  /// 共享同一个 turnId。用户 / 系统消息为 null。
  ///
  /// 设为可空,保留对历史数据(尚未写入 turnId 的旧消息)的兼容。
  final String? turnId;

  /// 消息内容形态。
  ///
  /// 可空:旧实例(热重载、跨版本兼容)可能没设置该字段。
  /// UI 层统一使用 [effectiveType],空值回落为 [MessageType.text]。
  final MessageType? type;

  /// 永远非空的 type 视图(用于渲染分发)。
  ///
  /// 为空时回落为 [MessageType.text],避免 UI 层处理 null。
  MessageType get effectiveType => type ?? MessageType.text;

  /// 已累积的文本内容。
  ///
  /// * [MessageType.text]:Markdown 文本(用户输入或助手回复)
  /// * [MessageType.system]:系统提示原文
  /// * 其他类型:可空
  final String content;

  /// 工具调用轨迹。
  /// * [MessageType.toolCall] 时作为消息的主体
  /// * [MessageType.text] 时表示"该回复中包含的工具调用"(向后兼容)
  /// * `null` 表示该消息不含工具调用。
  final List<ToolCallRecord>? toolCalls;

  /// 思考 / 推理过程文本。仅 [MessageType.thinking] 使用。
  final String? thinkingContent;

  /// 计划步骤。仅 [MessageType.plan] 使用。
  final List<PlanItem>? planItems;

  /// 创建时间。
  final DateTime createdAt;

  /// 是否仍在流式输出中。
  final bool streaming;
}

/// 消息内容形态。
enum MessageType {
  /// 纯文本(Markdown 格式):用户输入或助手最终回复。
  text,

  /// 系统提示:注入给模型的 system 指令或运行时提醒。
  system,

  /// 工具调用:assistant 触发工具调用的轨迹,主体是 [Message.toolCalls]。
  toolCall,

  /// 思考 / 推理过程:Chain-of-Thought,主体是 [Message.thinkingContent]。
  thinking,

  /// 计划列表:agent 在执行前发布的步骤,主体是 [Message.planItems]。
  plan,

  /// 错误提示:对话失败 / 取消时留下的错误消息,主体是 [Message.content](原始错误文本)。
  ///
  /// 通常 `role == MessageRole.assistant`、`streaming == false`,
  /// 用于在对话气泡中以警示样式呈现网络异常、AI 调用错误等。
  error,
}

/// 消息角色。
enum MessageRole { user, assistant, system, tool }

/// 计划条目。
///
/// 仅在 [Message.type] == [MessageType.plan] 时承载。
class PlanItem {
  const PlanItem({
    required this.id,
    required this.title,
    required this.status,
    this.description,
  });

  /// 步骤唯一 ID(用于跨消息跟踪同一个步骤)。
  final String id;

  /// 步骤标题。
  final String title;

  /// 当前状态。
  final PlanItemStatus status;

  /// 可选的详细说明。
  final String? description;

  PlanItem copyWith({
    String? title,
    PlanItemStatus? status,
    String? description,
  }) => PlanItem(
    id: id,
    title: title ?? this.title,
    status: status ?? this.status,
    description: description ?? this.description,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'status': status.name,
    if (description != null) 'description': description,
  };

  factory PlanItem.fromJson(Map<String, dynamic> json) => PlanItem(
    id: json['id']! as String,
    title: json['title']! as String,
    status: PlanItemStatus.values.byName(json['status']! as String),
    description: json['description'] as String?,
  );
}

/// 计划条目状态。
enum PlanItemStatus {
  /// 待执行。
  pending,

  /// 执行中。
  inProgress,

  /// 已完成。
  done,

  /// 已跳过。
  skipped,
}

/// 工具调用记录。
class ToolCallRecord {
  const ToolCallRecord({
    required this.toolCallId,
    required this.name,
    required this.args,
    required this.output,
  });

  /// OpenAI tool_call.id(用于回传 tool result)。
  final String toolCallId;

  /// 工具名。
  final String name;

  /// 工具参数。
  final Map<String, dynamic> args;

  /// 工具输出(text 或 markdown 字符串)。
  final String output;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'toolCallId': toolCallId,
    'name': name,
    'args': args,
    'output': output,
  };

  factory ToolCallRecord.fromJson(Map<String, dynamic> json) => ToolCallRecord(
    toolCallId: json['toolCallId']! as String,
    name: json['name']! as String,
    args: Map<String, dynamic>.from(json['args']! as Map),
    output: (json['output'] as String?) ?? '',
  );
}
