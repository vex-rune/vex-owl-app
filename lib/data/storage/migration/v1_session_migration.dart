/// 会话数据迁移器（v6.4）
///
/// 将旧版 `.owl/wiki/sessions/*.md` 迁移到新版 `.owl/sessions/{id}/` 目录结构。
///
/// 迁移内容：
/// - 扫描 `wiki/sessions/*.md`
/// - 解析 front-matter 提取 sessionId
/// - 创建 `sessions/{id}/` 目录
/// - 写入 `session.jsonl` + `messages.jsonl`
/// - 旧文件移到 `.legacy/` 目录（可恢复）
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/model/session.dart';
import '../../../core/model/message.dart';
import '../../../core/model/wiki_front_matter.dart';
import '../../../core/model/llm_tool_call.dart';
import '../../../core/core.dart';

/// 会话数据迁移器
class V1SessionMigration {
  V1SessionMigration({
    required String owlRoot,
  })  : _owlRoot = owlRoot,
        _wikiSessionsDir = p.join(owlRoot, 'wiki', 'sessions');

  final String _owlRoot;
  final String _wikiSessionsDir;

  /// 执行迁移
  ///
  /// 返回迁移的会话数量。
  Future<int> migrate() async {
    final wikiDir = Directory(_wikiSessionsDir);
    if (!await wikiDir.exists()) {
      log.debug('📦 会话迁移：旧 sessions 目录不存在，跳过');
      return 0;
    }

    // 检查是否已迁移过
    final sessionsDir = Directory(p.join(_owlRoot, 'sessions'));
    if (await sessionsDir.exists()) {
      final hasContent = await _dirHasContent(sessionsDir);
      if (hasContent) {
        log.debug('📦 会话迁移：sessions 目录已有内容，跳过');
        return 0;
      }
    }

    int count = 0;
    final legacyDir = Directory(p.join(_owlRoot, '.legacy'));
    if (!await legacyDir.exists()) {
      await legacyDir.create(recursive: true);
    }

    await for (final entity in wikiDir.list(followLinks: false)) {
      if (entity is File && entity.path.endsWith('.md')) {
        final migrated = await _migrateFile(entity, legacyDir);
        if (migrated) count++;
      }
    }

    if (count > 0) {
      log.debug('✅ 会话迁移完成：$count 个会话');
    }
    return count;
  }

  Future<bool> _migrateFile(File file, Directory legacyDir) async {
    try {
      final content = await file.readAsString();
      final (fm, body) = WikiFrontMatter.parse(content);

      // 提取 sessionId
      final sessionId = fm.extras['session_id'] as String? ??
          p.basenameWithoutExtension(file.path);

      // 创建新目录
      final newDir = Directory(p.join(_owlRoot, 'sessions', sessionId));
      if (!await newDir.exists()) {
        await newDir.create(recursive: true);
      }

      // 解析 body 中的消息历史（如果有）
      final messages = _parseMessagesFromBody(body);

      // 构建 Session 对象
      final session = Session(
        id: sessionId,
        name: fm.title,
        createdAt: fm.updatedAt,
        updatedAt: fm.updatedAt,
        archived: fm.extras['archived'] == true,
        pinned: fm.extras['pinned'] == true,
        messageCount: messages.length,
      );

      // 写入 session.jsonl
      final sessionFile = File(p.join(newDir.path, 'session.jsonl'));
      await sessionFile.writeAsString('${jsonEncode(session.toJsonl())}\n');

      // 写入 messages.jsonl
      if (messages.isNotEmpty) {
        final messagesFile = File(p.join(newDir.path, 'messages.jsonl'));
        final buffer = StringBuffer();
        for (final msg in messages) {
          buffer.writeln(jsonEncode(msg.toJsonl()));
        }
        await messagesFile.writeAsString(buffer.toString());
      }

      // 复制旧文件到 .legacy/
      final legacyFile = File(p.join(legacyDir.path, p.basename(file.path)));
      await file.copy(legacyFile.path);

      // 删除原文件
      await file.delete();

      log.debug(
        '📦 迁移会话：$sessionId（${messages.length} 条消息）',
      );
      return true;
    } catch (e) {
      log.debug('⚠️ 迁移会话失败：${file.path} / $e');
      return false;
    }
  }

  /// 从 body 内容中解析消息历史
  ///
  /// 旧格式：每行 `role: content\n`
  List<Message> _parseMessagesFromBody(String body) {
    final messages = <Message>[];
    final lines = body.split(RegExp(r'\r\n|\r|\n'));

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final colonIdx = trimmed.indexOf(': ');
      if (colonIdx < 0) continue;

      final roleStr = trimmed.substring(0, colonIdx);
      final content = trimmed.substring(colonIdx + 2);

      MessageRole role;
      switch (roleStr.toLowerCase()) {
        case 'user':
          role = MessageRole.user;
          break;
        case 'assistant':
          role = MessageRole.assistant;
          break;
        case 'system':
          role = MessageRole.system;
          break;
        case 'tool':
          role = MessageRole.tool;
          break;
        default:
          continue;
      }

      messages.add(Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        sessionId: '',
        role: role,
        parts: [TextPart(content)],
        createdAt: DateTime.now(),
      ));
    }

    return messages;
  }

  Future<bool> _dirHasContent(Directory dir) async {
    await for (final entity in dir.list(followLinks: false)) {
      final basename = p.basename(entity.path);
      if (basename.startsWith('.')) continue;
      return true;
    }
    return false;
  }
}
