import '../model/conversation.dart';

/// 会话仓储(只管 Session 聚合根)。
///
/// 历史注解:早期版本把消息读写也放进同一接口,导致 SessionRepository 与
/// MessageRepository 互相纠缠,粒度太粗。现在拆成两个独立抽象:
///
/// * [SessionRepository] —— 会话元数据(create / findById / rename / pin / delete / bumpRound ...);
/// * [MessageRepository] —— 消息持久化与流式生命周期。
///
/// 调用方约定:
/// * 一次 AI 回复流程对应一次 send 调用,
///   消息侧的生命周期由 [MessageRepository] 承载;
/// * 错误语义:本接口的方法在"业务错误"时抛 [SessionValidationError],
///   "底层不可用"等基础设施错误由实现方抛 [RepositoryError]。
abstract class SessionRepository {
  /// 创建新会话。
  ///
  /// 成功时 `round = 0, pinned = false`,`updatedAt = createdAt`。
  Future<Session> create({required String title, required String agentId});

  /// 按 ID 查询会话,不存在返回 `null`(不抛)。
  Future<Session?> findById(String id);

  /// 一次性快照(按 `pinned DESC, updatedAt DESC` 排序)。
  Future<List<Session>> snapshot();

  /// 实时订阅会话列表(每次表变更发射新快照)。
  Stream<List<Session>> watch();

  /// 重命名会话。
  ///
  /// * `newTitle.trim()` 为空 → 抛 [SessionValidationError](emptyTitle);
  /// * 长度超限由实现自行决定截断 / 抛错(v1.x 走截断 32 字符)。
  /// * 不存在的 ID → 抛 [SessionValidationError](notFound)。
  Future<void> rename(String id, String newTitle);

  /// 置顶 / 取消置顶。
  Future<void> pin(String id);
  Future<void> unpin(String id);

  /// 删除会话及其消息(实现负责级联,或借助外键)。
  Future<void> delete(String id);

  /// 给指定会话的轮次计数 +1,不存在时静默 no-op。
  Future<void> bumpRound(String id);
}
