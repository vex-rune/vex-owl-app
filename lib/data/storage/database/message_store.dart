import 'package:drift/drift.dart';

import 'app_database.dart';

part 'message_store.g.dart';

/// 消息表。
@DataClassName('MessageRow')
class Messages extends Table {
  TextColumn get id => text()();
  TextColumn get conversationId =>
      text().customConstraint('REFERENCES sessions(id) ON DELETE CASCADE')();
  TextColumn get role => text()();
  /// 消息内容形态(枚举名,例如 `text` / `error` / `thinking`)。
  /// v1 默认 `text`,与历史数据保持兼容。
  TextColumn get type =>
      text().withDefault(const Constant('text'))();
  TextColumn get content => text().withDefault(const Constant(''))();
  TextColumn get toolCallsJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get streaming => boolean().withDefault(const Constant(false))();
  /// 所属助手回合 id(v3 引入)。
  ///
  /// 用户 / 系统消息为 null;同一回合内的 assistant + tool 事件共享同一个值。
  /// 历史数据(v1/v2 写入的)为 null,UI 层在 [groupTurns] 中回退为"单事件回合"。
  TextColumn get turnId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 消息存储。
@DriftAccessor(tables: [Messages])
class MessageStore extends DatabaseAccessor<AppDatabase>
    with _$MessageStoreMixin {
  MessageStore(super.db);

  /// 追加消息(insertOrReplace 以支持流式占位消息的最终化)。
  Future<void> insertOrReplace(MessageRow msg) => into(messages).insert(
        msg,
        mode: InsertMode.insertOrReplace,
      );

  /// 按会话加载最近 limit 条(默认 50)。
  Future<List<MessageRow>> loadByConversation(String conversationId,
      {int limit = 50}) {
    return (select(messages)
          ..where((m) => m.conversationId.equals(conversationId))
          ..orderBy([
            (m) => OrderingTerm(expression: m.createdAt, mode: OrderingMode.asc),
          ]))
        .get()
        .then((all) => all.length <= limit ? all : all.sublist(all.length - limit));
  }

  /// 订阅某会话的消息变更(写后立即 emit,UI 可即时刷新)。
  ///
  /// **emit 触发时机**:首次订阅时先发一次当前快照,后续每次 messages 表写入
  /// 该 conversationId 的行都会重发。
  Stream<List<MessageRow>> watchByConversation(String conversationId) {
    final query = select(messages)
      ..where((m) => m.conversationId.equals(conversationId))
      ..orderBy([
        (m) => OrderingTerm(expression: m.createdAt, mode: OrderingMode.asc),
      ]);
    return query.watch();
  }

  /// 部分字段更新(流式累积 + finalize 用)。
  Future<int> updatePartial(String id, MessagesCompanion patch) =>
      (update(messages)..where((m) => m.id.equals(id))).write(patch);

  /// 按 ID 查询(单条)。
  Future<MessageRow?> findById(String id) =>
      (select(messages)..where((m) => m.id.equals(id))).getSingleOrNull();

  /// 删除某会话所有消息(级联删除由会话删除触发;此处兜底)。
  Future<int> deleteByConversation(String conversationId) =>
      (delete(messages)..where((m) => m.conversationId.equals(conversationId)))
          .go();
}