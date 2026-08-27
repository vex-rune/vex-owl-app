/// 会话模型(对应 docs §3.1 SessionService)。
///
/// 不可变值类型,所有更新通过 [copyWith] 完成。
class Session {
  const Session({
    required this.id,
    required this.title,
    required this.pinned,
    required this.createdAt,
    required this.updatedAt,
    required this.round,
    required this.agentId,
  });

  /// 唯一 ID(由调用方生成;v1.x 内存版使用 uuid)。
  final String id;

  /// 会话标题(默认 '新对话',首轮完成后由 AI 改名,≤10 字)。
  final String title;

  /// 是否置顶。
  final bool pinned;

  /// 创建时间。
  final DateTime createdAt;

  /// 最近活跃时间(用于 SQL 排序:`ORDER BY pinned DESC, updated_at DESC`)。
  final DateTime updatedAt;

  /// 当前已完成轮次。首轮为 1,被 rename 后即视为已完成首轮。
  final int round;

  /// 绑定的 Agent ID(v1.x 固定 'fast-qa')。
  final String agentId;

  Session copyWith({
    String? title,
    bool? pinned,
    DateTime? updatedAt,
    int? round,
    String? agentId,
  }) =>
      Session(
        id: id,
        title: title ?? this.title,
        pinned: pinned ?? this.pinned,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        round: round ?? this.round,
        agentId: agentId ?? this.agentId,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'pinned': pinned,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'round': round,
        'agentId': agentId,
      };

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        id: json['id']! as String,
        title: json['title']! as String,
        pinned: (json['pinned'] as bool?) ?? false,
        createdAt: DateTime.parse(json['createdAt']! as String),
        updatedAt: DateTime.parse(json['updatedAt']! as String),
        round: (json['round'] as int?) ?? 0,
        agentId: (json['agentId'] as String?) ?? 'fast-qa',
      );
}

/// 会话写入校验异常(对外暴露的领域错误)。
class SessionValidationError implements Exception {
  SessionValidationError(this.code, this.message);
  final SessionValidation code;
  final String message;
  @override
  String toString() => 'SessionValidationError($code): $message';
}

enum SessionValidation {
  emptyTitle,
  tooLongTitle,
  notFound,
}