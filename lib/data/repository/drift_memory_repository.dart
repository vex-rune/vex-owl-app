import 'package:drift/drift.dart' show Value;

import '../../core/model/memory.dart';
import '../../core/repository/memory_repository.dart';
import '../storage/database/app_database.dart';

/// Drift 持久化的 MemoryRepository 实现。
///
/// WikeLLM 4 个 scope(profile / short_term / long_term / history)
/// 共用一张 memory_entries 表,以 scope 列区分。
class DriftMemoryRepository implements MemoryRepository {
  DriftMemoryRepository(this.db);

  final AppDatabase db;

  // ---- scope 名称常量 ----

  static const String _kProfile = 'profile';
  static const String _kShortTerm = 'short_term';
  static const String _kLongTerm = 'long_term';
  static const String _kHistory = 'history';

  String _scopeName(MemoryScope scope) {
    switch (scope) {
      case MemoryScope.profile:
        return _kProfile;
      case MemoryScope.shortTerm:
        return _kShortTerm;
      case MemoryScope.longTerm:
        return _kLongTerm;
      case MemoryScope.history:
        return _kHistory;
    }
  }

  MemoryScope _fromScopeName(String scope) {
    switch (scope) {
      case _kProfile:
        return MemoryScope.profile;
      case _kShortTerm:
        return MemoryScope.shortTerm;
      case _kLongTerm:
        return MemoryScope.longTerm;
      case _kHistory:
        return MemoryScope.history;
      default:
        return MemoryScope.shortTerm;
    }
  }

  // ---- profile ----

  @override
  Future<String> readProfile() => _readScope(_kProfile);

  @override
  Future<void> writeProfile(String markdown) async {
    await _replaceScope(_kProfile, markdown);
  }

  // ---- short_term ----

  @override
  Future<String> readShortTerm() => _readScope(_kShortTerm);

  @override
  Future<void> appendShortTerm(String content) async {
    await _appendScope(_kShortTerm, content);
  }

  // ---- long_term ----

  @override
  Future<String> readLongTerm() => _readScope(_kLongTerm);

  @override
  Future<void> appendLongTerm(String content) async {
    await _appendScope(_kLongTerm, content);
  }

  // ---- history ----

  @override
  Future<void> writeHistoryLine({
    required String conversationId,
    required String title,
    required String summary,
  }) async {
    final now = DateTime.now();
    final body = '**$title**  `$conversationId`  $summary';
    await db.memoryStore.insert(
      MemoryEntriesCompanion(
        id: Value('hist-${now.microsecondsSinceEpoch}'),
        scope: const Value(_kHistory),
        conversationId: Value(conversationId),
        title: Value(title),
        body: Value(body),
        createdAt: Value(now),
      ),
    );
  }

  // ---- query ----

  @override
  Future<MemoryQueryResult> query(String scope, String keyword) async {
    final scopeName = _scopeName(_fromScopeName(scope));
    final rows = await db.memoryStore.search(scopeName, keyword);
    return MemoryQueryResult(
      scope: _fromScopeName(scope),
      lines: rows.map((r) => r.body).toList(),
    );
  }

  // ---- context prompt ----

  @override
  Future<String> buildContextPrompt(String conversationId) async {
    final buffer = StringBuffer();

    final profile = await readProfile();
    if (profile.trim().isNotEmpty) {
      buffer.writeln('## 个人画像');
      buffer.writeln(profile);
    }

    final shortTerm = await readShortTerm();
    if (shortTerm.trim().isNotEmpty) {
      buffer.writeln('\n## 短期记忆');
      buffer.writeln(shortTerm);
    }

    // 历史:取最近 50 条 history 摘要
    final historyRows = await db.memoryStore.search(_kHistory, '');
    if (historyRows.isNotEmpty) {
      buffer.writeln('\n## 历史摘要');
      for (final r in historyRows.take(50)) {
        buffer.writeln('- ${r.title ?? '未命名'}  ${r.body}');
      }
    }

    return buffer.toString();
  }

  // ---- 内部读写 ----

  Future<String> _readScope(String scopeName) async {
    final rows = await db.memoryStore.listByScope(scopeName);
    return rows.map((r) => r.body).join('\n');
  }

  Future<void> _replaceScope(String scopeName, String body) async {
    // 清空当前 scope 再插入单条
    await db.memoryStore.clearScope(scopeName);
    final now = DateTime.now();
    await db.memoryStore.insert(
      MemoryEntriesCompanion(
        id: Value('$scopeName-singleton'),
        scope: Value(scopeName),
        body: Value(body),
        createdAt: Value(now),
      ),
    );
  }

  Future<void> _appendScope(String scopeName, String content) async {
    final now = DateTime.now();
    await db.memoryStore.insert(
      MemoryEntriesCompanion(
        id: Value('$scopeName-${now.microsecondsSinceEpoch}'),
        scope: Value(scopeName),
        body: Value('\n$content\n'),
        createdAt: Value(now),
      ),
    );
  }
}