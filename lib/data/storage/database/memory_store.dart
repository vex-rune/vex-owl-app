import 'package:drift/drift.dart';

import 'app_database.dart';

part 'memory_store.g.dart';

/// 记忆条目表(profile / short_term / long_term / history 共表,scope 区分)。
@DataClassName('MemoryEntry')
class MemoryEntries extends Table {
  TextColumn get id => text()();
  TextColumn get scope => text()();
  TextColumn get conversationId => text().nullable()();
  TextColumn get title => text().nullable()();
  TextColumn get body => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 记忆存储。
@DriftAccessor(tables: [MemoryEntries])
class MemoryStore extends DatabaseAccessor<AppDatabase>
    with _$MemoryStoreMixin {
  MemoryStore(super.db);

  /// 追加一条记忆条目。
  Future<void> insert(MemoryEntriesCompanion entry) =>
      into(memoryEntries).insert(entry, mode: InsertMode.insertOrReplace);

  /// 按 scope 查询所有条目,按时间升序。
  Future<List<MemoryEntry>> listByScope(String scope) =>
      (select(memoryEntries)
            ..where((m) => m.scope.equals(scope))
            ..orderBy([
              (m) => OrderingTerm(expression: m.createdAt, mode: OrderingMode.asc),
            ]))
          .get();

  /// 按 scope + keyword 模糊查询。
  Future<List<MemoryEntry>> search(String scope, String keyword) {
    final query = select(memoryEntries)
      ..where((m) => m.scope.equals(scope))
      ..orderBy([
        (m) => OrderingTerm(expression: m.createdAt, mode: OrderingMode.asc),
      ]);
    if (keyword.isNotEmpty) {
      query.where((m) => m.body.like('%$keyword%'));
    }
    return query.get();
  }

  /// 按 conversationId 查询 history 条目。
  Future<List<MemoryEntry>> historyByConversation(String conversationId) =>
      (select(memoryEntries)
            ..where((m) =>
                m.scope.equals('history') &
                m.conversationId.equals(conversationId))
            ..orderBy([
              (m) => OrderingTerm(expression: m.createdAt, mode: OrderingMode.desc),
            ]))
          .get();

  /// 清空某个 scope(供 reset 之类操作使用)。
  Future<int> clearScope(String scope) =>
      (delete(memoryEntries)..where((m) => m.scope.equals(scope))).go();
}