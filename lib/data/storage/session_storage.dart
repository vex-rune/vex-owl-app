/// 会话文件系统存储服务（v6.4）
///
/// 负责 `.owl/sessions/{id}/` 下的 JSONL 文件读写：
/// - `session.jsonl` — 会话元数据（单行）
/// - `messages.jsonl` — 完整消息历史（每行一条）
/// - `summary.md` — 压缩摘要（可选）
///
/// 设计：
/// - 消息追加用 appendLine（高性能）
/// - 元数据更新用全量覆写
/// - 所有操作走 AtomicFileWriter（原子写 + 备份 + 审计）
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/core.dart';
import '../../core/model/session.dart';
import '../../core/model/message.dart';
import 'owl_root.dart';
import 'atomic_file_writer.dart';

/// 会话文件系统存储服务
class SessionStorage {
  SessionStorage({
    required String owlRoot,
    AtomicFileWriter? writer,
  })  : _owlRoot = owlRoot,
        _writer = writer ?? AtomicFileWriter(rootPath: owlRoot);

  final String _owlRoot;
  final AtomicFileWriter _writer;

  // ── 会话元数据（session.jsonl）────────────────────────────────────────

  /// 加载所有会话元数据（扫描 sessions/*/session.jsonl）
  Future<List<Session>> listAll() async {
    final sessionsDir = Directory(p.join(_owlRoot, 'sessions'));
    if (!await sessionsDir.exists()) return [];

    final sessions = <Session>[];
    await for (final entity in sessionsDir.list(followLinks: false)) {
      if (entity is Directory) {
        final sessionJsonl = File(p.join(entity.path, 'session.jsonl'));
        if (await sessionJsonl.exists()) {
          try {
            final line = (await sessionJsonl.readAsString()).trim();
            if (line.isNotEmpty && line.endsWith('}')) {
              final json = jsonDecode(line) as Map<String, dynamic>;
              sessions.add(Session.fromJsonl(json));
            }
          } catch (e) {
            log.debug('⚠️ 加载会话失败：${entity.path} / $e');
          }
        }
      }
    }

    // 按 updatedAt 降序排列
    sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sessions;
  }

  /// 加载单个会话元数据
  Future<Session?> load(String sessionId) async {
    final path = p.join(_owlRoot, 'sessions', sessionId, 'session.jsonl');
    final file = File(path);
    if (!await file.exists()) return null;

    try {
      final line = (await file.readAsString()).trim();
      if (line.isEmpty || !line.endsWith('}')) return null;
      final json = jsonDecode(line) as Map<String, dynamic>;
      return Session.fromJsonl(json);
    } catch (e) {
      log.debug('⚠️ 加载会话失败：$sessionId / $e');
      return null;
    }
  }

  /// 保存会话元数据（全量覆写 session.jsonl）
  Future<void> save(Session session) async {
    final relativePath = 'sessions/${session.id}/session.jsonl';
    final content = '${jsonEncode(session.toJsonl())}\n';
    await _writer.write(relativePath, content);
  }

  /// 创建新会话（创建目录 + session.jsonl）
  Future<Session> create(String name) async {
    final now = DateTime.now();
    final id = _generateId();
    final session = Session(
      id: id,
      name: name,
      createdAt: now,
      updatedAt: now,
      archived: false,
      messageCount: 0,
    );

    // 创建会话目录
    final sessionDir = Directory(p.join(_owlRoot, 'sessions', id));
    if (!await sessionDir.exists()) {
      await sessionDir.create(recursive: true);
    }

    // 写入 session.jsonl
    await save(session);

    return session;
  }

  /// 删除会话（删除整个目录）
  Future<void> delete(String sessionId) async {
    final relativePath = 'sessions/$sessionId';
    await _writer.deleteDirectory(relativePath);
    log.debug('🗑️ 删除会话：$sessionId');
  }

  /// 归档会话（移动到 sessions/.archive/{id}/）
  Future<void> archive(String sessionId) async {
    final srcDir = Directory(p.join(_owlRoot, 'sessions', sessionId));
    if (!await srcDir.exists()) return;

    final archiveDir =
        Directory(p.join(_owlRoot, 'sessions', '.archive', sessionId));
    if (!await archiveDir.exists()) {
      await archiveDir.create(recursive: true);
    }

    // 复制文件到归档目录
    await for (final entity in srcDir.list(followLinks: false)) {
      final name = p.basename(entity.path);
      final dst = File(p.join(archiveDir.path, name));
      if (entity is File) {
        await entity.copy(dst.path);
      }
    }

    // 删除原目录
    await srcDir.delete(recursive: true);
    log.debug('📦 归档会话：$sessionId');
  }

  /// 取消归档（从 .archive/ 移回）
  Future<void> unarchive(String sessionId) async {
    final archiveDir =
        Directory(p.join(_owlRoot, 'sessions', '.archive', sessionId));
    if (!await archiveDir.exists()) return;

    final srcDir = Directory(p.join(_owlRoot, 'sessions', sessionId));
    if (!await srcDir.exists()) {
      await srcDir.create(recursive: true);
    }

    // 复制文件回原目录
    await for (final entity in archiveDir.list(followLinks: false)) {
      final name = p.basename(entity.path);
      final dst = File(p.join(srcDir.path, name));
      if (entity is File) {
        await entity.copy(dst.path);
      }
    }

    // 删除归档目录
    await archiveDir.delete(recursive: true);
    log.debug('📦 取消归档：$sessionId');
  }

  // ── 消息历史（messages.jsonl）────────────────────────────────────────

  /// 加载消息历史（逐行读取 messages.jsonl）
  Future<List<Message>> loadMessages(String sessionId) async {
    final path = p.join(_owlRoot, 'sessions', sessionId, 'messages.jsonl');
    final file = File(path);
    if (!await file.exists()) return [];

    try {
      final lines = await file.readAsLines();
      final messages = <Message>[];
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        if (!trimmed.endsWith('}')) continue; // 跳过损坏行
        try {
          final json = jsonDecode(trimmed) as Map<String, dynamic>;
          messages.add(Message.fromJsonl(json));
        } catch (_) {
          // 损坏行跳过
        }
      }
      return messages;
    } catch (e) {
      log.debug('⚠️ 加载消息失败：$sessionId / $e');
      return [];
    }
  }

  /// 保存消息历史（全量覆写 messages.jsonl）
  Future<void> saveMessages(String sessionId, List<Message> messages) async {
    final relativePath = 'sessions/$sessionId/messages.jsonl';
    final buffer = StringBuffer();
    for (final msg in messages) {
      buffer.writeln(jsonEncode(msg.toJsonl()));
    }
    await _writer.write(relativePath, buffer.toString());
  }

  /// 追加消息（高性能，writeln 追加到文件末尾）
  Future<void> appendMessages(String sessionId, List<Message> messages) async {
    final relativePath = 'sessions/$sessionId/messages.jsonl';
    for (final msg in messages) {
      await _writer.appendLine(relativePath, jsonEncode(msg.toJsonl()));
    }
  }

  /// 保存压缩摘要（summary.md）
  Future<void> saveSummary(String sessionId, String summary) async {
    final relativePath = 'sessions/$sessionId/summary.md';
    await _writer.write(relativePath, summary);
  }

  /// 加载压缩摘要
  Future<String?> loadSummary(String sessionId) async {
    final path = p.join(_owlRoot, 'sessions', sessionId, 'summary.md');
    final file = File(path);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  // ── 内部辅助 ─────────────────────────────────────────────────────────

  String _generateId() {
    final r = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final s = (r.hashCode).abs().toRadixString(36);
    return '$r-$s';
  }
}
