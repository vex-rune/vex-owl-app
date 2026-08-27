import 'package:drift/drift.dart' show Value;

import '../../core/model/conversation.dart';
import '../../core/repository/repository_error.dart';
import '../../core/repository/session_repository.dart';
import '../storage/database/app_database.dart';

/// Drift 持久化的 [SessionRepository] 实现。
///
/// 只负责 Session 聚合根的持久化;消息读写由 [DriftMessageRepository] 承担。
class DriftSessionRepository implements SessionRepository {
  DriftSessionRepository(this.db);

  final AppDatabase db;

  @override
  Future<Session> create({
    required String title,
    required String agentId,
  }) async {
    final now = DateTime.now();
    final id = 'session-${now.microsecondsSinceEpoch}';
    final session = Session(
      id: id,
      title: title,
      pinned: false,
      createdAt: now,
      updatedAt: now,
      round: 0,
      agentId: agentId,
    );
    await db.sessionStore.insertSession(
      SessionsCompanion(
        id: Value(session.id),
        title: Value(session.title),
        pinned: Value(session.pinned),
        createdAt: Value(session.createdAt),
        updatedAt: Value(session.updatedAt),
        round: Value(session.round),
        agentId: Value(session.agentId),
      ),
    );
    return session;
  }

  @override
  Future<Session?> findById(String id) async {
    final row = await db.sessionStore.findById(id);
    return row == null ? null : _toSession(row);
  }

  @override
  Future<List<Session>> snapshot() async {
    final rows = await db.sessionStore.listAll();
    return rows.map(_toSession).toList();
  }

  @override
  Stream<List<Session>> watch() async* {
    await for (final rows in db.sessionStore.watchAll()) {
      yield rows.map(_toSession).toList();
    }
  }

  @override
  Future<void> rename(String id, String newTitle) async {
    if (newTitle.trim().isEmpty) {
      throw SessionValidationError(
        SessionValidation.emptyTitle,
        '标题不能为空',
      );
    }
    final truncated = newTitle.length > 32
        ? newTitle.substring(0, 32)
        : newTitle;
    await db.sessionStore.updatePartial(
      id,
      SessionsCompanion(
        title: Value(truncated),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> pin(String id) async {
    await _touchOnExisting(id, (current) {
      return SessionsCompanion(
        pinned: const Value(true),
        updatedAt: Value(DateTime.now()),
      );
    });
  }

  @override
  Future<void> unpin(String id) async {
    await _touchOnExisting(id, (current) {
      return SessionsCompanion(
        pinned: const Value(false),
        updatedAt: Value(DateTime.now()),
      );
    });
  }

  @override
  Future<void> delete(String id) async {
    try {
      await db.sessionStore.deleteById(id);
    } catch (e) {
      throw RepositoryError(
        RepositoryErrorKind.storage,
        '删除会话失败: $id',
        e,
      );
    }
  }

  @override
  Future<void> bumpRound(String id) async {
    final current = await findById(id);
    if (current == null) return;
    await db.sessionStore.updatePartial(
      id,
      SessionsCompanion(
        round: Value(current.round + 1),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// 读出现有行,委托给 [patch] 生成更新字段;找不到时抛 [RepositoryError.notFound]。
  Future<void> _touchOnExisting(
    String id,
    SessionsCompanion Function(Session current) patch,
  ) async {
    final current = await findById(id);
    if (current == null) {
      throw RepositoryError(
        RepositoryErrorKind.notFound,
        '会话不存在: $id',
      );
    }
    await db.sessionStore.updatePartial(id, patch(current));
  }

  Session _toSession(SessionRow row) => Session(
    id: row.id,
    title: row.title,
    pinned: row.pinned,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    round: row.round,
    agentId: row.agentId,
  );
}
