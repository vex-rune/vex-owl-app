/// 会话数据模型。
///
/// 采用不可变设计，通过 [copyWith] 创建修改后的副本。
/// 每个会话包含名称、时间戳、归档状态和消息计数等信息。
library;

/// 会话数据模型。
///
/// 不可变对象，使用 [copyWith] 生成修改后的副本。
class Session {
  const Session({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.context = '',
    this.archived = false,
    this.messageCount = 0,
    this.pinned = false,
  });

  /// 会话唯一标识
  final String id;

  /// 会话名称
  final String name;

  /// 会话创建时间
  final DateTime createdAt;

  /// 会话最后更新时间
  final DateTime updatedAt;

  /// 临时上下文（JSON 格式，最多 10 轮对话）
  final String context;

  /// 是否已归档
  final bool archived;

  /// 是否已顶置（置顶显示在抽屉顶部）
  final bool pinned;

  /// 会话中的消息数量
  final int messageCount;

  /// 创建当前会话的修改副本。
  ///
  /// 未指定的参数保持原值不变。
  Session copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? context,
    bool? archived,
    bool? pinned,
    int? messageCount,
  }) {
    return Session(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      context: context ?? this.context,
      archived: archived ?? this.archived,
      pinned: pinned ?? this.pinned,
      messageCount: messageCount ?? this.messageCount,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Session &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt &&
          context == other.context &&
          archived == other.archived &&
          pinned == other.pinned &&
          messageCount == other.messageCount;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        createdAt,
        updatedAt,
        context,
        archived,
        pinned,
        messageCount,
      );

  @override
  String toString() =>
      'Session(id: $id, name: $name, archived: $archived, '
      'pinned: $pinned, messageCount: $messageCount)';

  // ── JSONL 序列化 ─────────────────────────────────────────────────────

  /// 序列化为单行 JSON 对象（用于 session.jsonl）
  Map<String, dynamic> toJsonl() => {
        'version': 1,
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'context': context,
        'archived': archived,
        'pinned': pinned,
        'messageCount': messageCount,
      };

  /// 从单行 JSON 对象反序列化
  factory Session.fromJsonl(Map<String, dynamic> json) {
    return Session(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '未命名会话',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
      context: json['context'] as String? ?? '',
      archived: json['archived'] as bool? ?? false,
      pinned: json['pinned'] as bool? ?? false,
      messageCount: json['messageCount'] as int? ?? 0,
    );
  }
}
