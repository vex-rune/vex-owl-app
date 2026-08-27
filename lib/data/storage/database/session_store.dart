import 'package:drift/drift.dart';

import 'app_database.dart';

part 'session_store.g.dart';

/// 会话表。
@DataClassName('SessionRow')
class Sessions extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 64)();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get round => integer().withDefault(const Constant(0))();
  TextColumn get agentId => text().withDefault(const Constant('fast-qa'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 会话存储。
///
/// 所有方法返回 Drift 自带 `SessionRow` 数据类;
/// `SessionRepository` 实现负责映射到领域 `Session` 模型。
@DriftAccessor(tables: [Sessions])
class SessionStore extends DatabaseAccessor<AppDatabase>
    with _$SessionStoreMixin {
  SessionStore(super.db);

  /// 插入会话。
  Future<void> insertSession(SessionsCompanion entry) =>
      into(sessions).insert(entry, mode: InsertMode.insertOrReplace);

  /// 按 ID 查询。
  Future<SessionRow?> findById(String id) =>
      (select(sessions)..where((s) => s.id.equals(id))).getSingleOrNull();

  /// 列出全部会话(按 pinned DESC, updatedAt DESC 排序)。
  Future<List<SessionRow>> listAll() => (select(sessions)
        ..orderBy([
          (s) => OrderingTerm(expression: s.pinned, mode: OrderingMode.desc),
          (s) => OrderingTerm(expression: s.updatedAt, mode: OrderingMode.desc),
        ]))
      .get();

  /// 按 ID 更新部分字段。
  Future<int> updatePartial(String id, SessionsCompanion patch) =>
      (update(sessions)..where((s) => s.id.equals(id))).write(patch);

  /// 按 ID 删除。
  Future<int> deleteById(String id) =>
      (delete(sessions)..where((s) => s.id.equals(id))).go();

  /// 观察会话列表变化(供 UI 订阅)。
  Stream<List<SessionRow>> watchAll() => (select(sessions)
        ..orderBy([
          (s) => OrderingTerm(expression: s.pinned, mode: OrderingMode.desc),
          (s) => OrderingTerm(expression: s.updatedAt, mode: OrderingMode.desc),
        ]))
      .watch();
}