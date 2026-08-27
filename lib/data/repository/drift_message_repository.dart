import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import '../../core/model/message.dart';
import '../../core/repository/message_repository.dart';
import '../../core/repository/repository_error.dart';
import '../storage/database/app_database.dart';

/// Drift 持久化的 [MessageRepository] 实现。
///
/// 把 ConversationService 关心的消息生命周期(append / appendDelta / finalize /
/// markError)与 Session 的元数据持久化解耦。
class DriftMessageRepository implements MessageRepository {
  DriftMessageRepository(this.db);

  final AppDatabase db;

  @override
  Future<void> append(Message message) async {
    await db.messageStore.insertOrReplace(_toRow(message));
  }

  @override
  Future<void> appendDelta(String messageId, String delta) async {
    final row = await _findRow(messageId);
    if (row == null) return;
    await db.messageStore.updatePartial(
      messageId,
      MessagesCompanion(content: Value(row.content + delta)),
    );
  }

  @override
  Future<List<Message>> loadHistory(
    String conversationId, {
    int limit = 50,
  }) async {
    final rows = await db.messageStore.loadByConversation(
      conversationId,
      limit: limit,
    );
    return rows.map(_toMessage).toList();
  }

  @override
  Future<Message?> findById(String messageId) async {
    final row = await db.messageStore.findById(messageId);
    return row == null ? null : _toMessage(row);
  }

  @override
  Stream<List<Message>> watch(String conversationId) {
    return db.messageStore
        .watchByConversation(conversationId)
        .map((rows) => rows.map(_toMessage).toList(growable: false));
  }

  @override
  Future<void> finalize(
    String messageId, {
    required String content,
    List<ToolCallRecord>? toolCalls,
  }) async {
    try {
      await db.messageStore.updatePartial(
        messageId,
        MessagesCompanion(
          content: Value(content),
          toolCallsJson: Value(
            toolCalls == null
                ? null
                : jsonEncode(toolCalls.map((t) => t.toJson()).toList()),
          ),
          streaming: const Value(false),
        ),
      );
    } catch (e) {
      throw RepositoryError(
        RepositoryErrorKind.storage,
        'finalize 失败: $messageId',
        e,
      );
    }
  }

  @override
  Future<void> markError(String messageId, String errorText) async {
    final row = await _findRow(messageId);
    if (row == null) return;
    await db.messageStore.updatePartial(
      messageId,
      MessagesCompanion(
        type: Value(MessageType.error.name),
        content: Value(errorText),
        toolCallsJson: const Value(null),
        streaming: const Value(false),
      ),
    );
  }

  // ---- 内部 ----

  Future<MessageRow?> _findRow(String messageId) =>
      db.messageStore.findById(messageId);

  Message _toMessage(MessageRow row) {
    final calls = row.toolCallsJson;
    List<ToolCallRecord>? tools;
    if (calls != null && calls.isNotEmpty) {
      final list = jsonDecode(calls) as List<dynamic>;
      tools = list
          .map((e) => ToolCallRecord.fromJson(e! as Map<String, dynamic>))
          .toList();
    }
    // 反序列化 type 时,未知值直接抛错 —— 避免静默 fallback 掩盖数据损坏。
    // row.type 是非空 TextColumn,drift 列默认值 'text' 已在 schema 层兜底。
    final typeName = row.type;
    final type = MessageType.values.cast<MessageType?>().firstWhere(
      (t) => t?.name == typeName,
      orElse: () {
        throw RepositoryError(
          RepositoryErrorKind.storage,
          '反序列化 Message 失败:未知 type "$typeName", messageId=${row.id}',
        );
      },
    );
    return Message(
                                                                                            id: row.id,
      conversationId: row.conversationId,
      role: MessageRole.values.byName(row.role),
      type: type,
      content: row.content,
      toolCalls: tools,
      createdAt: row.createdAt,
      streaming: row.streaming,
      turnId: row.turnId,
    );
  }

  MessageRow _toRow(Message msg) => MessageRow(
    id: msg.id,
    conversationId: msg.conversationId,
    role: msg.role.name,
    type: (msg.type ?? MessageType.text).name,
    content: msg.content,
    toolCallsJson: msg.toolCalls == null
        ? null
        : jsonEncode(msg.toolCalls!.map((t) => t.toJson()).toList()),
    createdAt: msg.createdAt,
    streaming: msg.streaming,
    turnId: msg.turnId,
  );
}
