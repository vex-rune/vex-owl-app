/// Wiki 文件原子写入器（v5.0）
///
/// 流程（参考 plan §9.4）：
/// 1. 加锁 `.meta/wiki.lock`
/// 2. 校验 path 必须在 wiki/ 白名单内
/// 3. 校验 path 匹配对应 front-matter schema（todos/sessions/concepts/profile）
/// 4. 解析现有 front-matter，合并新内容
/// 5. 自动更新 updated_at = now()
/// 6. 写 .tmp → fsync → rename
/// 7. 备份原文件到 .backup/{path}.{ts}.bak
/// 8. 追加 .audit.log（私有目录）
/// 9. 释放锁
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/core.dart';
import '../../core/model/wiki_file.dart';
import 'wiki_lock_service.dart';

/// Wiki 文件写入异常
class WikiWriteException implements Exception {
  WikiWriteException(this.message, {this.code = 'write_failed'});

  final String message;
  final String code;

  @override
  String toString() => '[$code] $message';
}

/// 文件类型（用于校验与索引分类）
enum WikiFileKind {
  profile,
  todo,
  session,
  concept,
  indexFile,
  schema,
  unknown,
}

class WikiFileWriter {
  WikiFileWriter({
    required this.wikiRoot,
    required WikiLockService lockService,
  }) : _lock = lockService;

  /// Wiki 根目录绝对路径（如 `<docs>/.owl/wiki/`）
  final String wikiRoot;
  final WikiLockService _lock;

  /// 1MB 写入上限（与 FileTools 保持一致）
  static const int maxBytes = 1024 * 1024;

  /// 写入一个 Wiki 文件
  ///
  /// [kind] 文件类型（用于校验路径）
  /// [file] 已构造好的 WikiFile（含 front-matter + body）
  Future<void> write(WikiFileKind kind, WikiFile file) async {
    // 1. 路径校验
    _validatePath(kind, file.relativePath);

    // 2. 锁内串行写入
    await _lock.withLock(
      owner: LockOwner.userEdit,
      operation: 'write:${file.relativePath}',
      action: (lock) async {
        await _writeUnlocked(kind, file);
      },
    );
  }

  /// 不加锁写入（仅供内部迁移场景，外部请走 [write]）
  Future<void> writeUnlocked(WikiFileKind kind, WikiFile file) async {
    _validatePath(kind, file.relativePath);
    await _writeUnlocked(kind, file);
  }

  /// 删除一个 Wiki 文件
  Future<void> delete(WikiFileKind kind, String relativePath) async {
    _validatePath(kind, relativePath);
    await _lock.withLock(
      owner: LockOwner.userEdit,
      operation: 'delete:$relativePath',
      action: (_) async {
        final absPath = p.join(wikiRoot, relativePath);
        final f = File(absPath);
        if (await f.exists()) {
          await _backup(relativePath);
          await f.delete();
          await _appendAudit('delete', relativePath, sizeBytes: 0);
        }
      },
    );
  }

  /// 直接写入原始内容（不走 WikiFile 包装，不加 front-matter）
  ///
  /// 适用于 index.md 这类人类可读展示文件（v5 不带 front-matter）。
  /// 仍走加锁 + 原子写 + 备份 + 审计流程。
  Future<void> writeRaw({
    required WikiFileKind kind,
    required String relativePath,
    required String rawContent,
  }) async {
    _validatePath(kind, relativePath);
    await _lock.withLock(
      owner: LockOwner.userEdit,
      operation: 'write_raw:$relativePath',
      action: (_) async {
        final absPath = p.join(wikiRoot, relativePath);
          final target = File(absPath);
          if (!await target.parent.exists()) {
            await target.parent.create(recursive: true);
          }
          if (await target.exists()) {
            await _backup(relativePath);
          }
          if (rawContent.length > maxBytes) {
            throw WikiWriteException(
              '内容超过 ${maxBytes ~/ 1024}KB 限制',
              code: 'content_too_large',
            );
          }
          final tmp = File('$absPath.tmp');
          await tmp.writeAsString(rawContent, flush: true);
          if (await target.exists()) await target.delete();
          await tmp.rename(absPath);
          await _appendAudit(
            'update',
            relativePath,
            sizeBytes: rawContent.length,
          );
        },
    );
  }

  // ───────────────────────── 内部核心 ─────────────────────────

  Future<void> _writeUnlocked(WikiFileKind kind, WikiFile file) async {
    final absPath = p.join(wikiRoot, file.relativePath);
    final target = File(absPath);

    // 确保父目录存在
    if (!await target.parent.exists()) {
      await target.parent.create(recursive: true);
    }

    // 备份原文件（如果存在）
    final existed = await target.exists();
    if (existed) {
      await _backup(file.relativePath);
    }

    // 自动维护 updated_at
    final fm = file.frontMatter.copyWith(
      updatedAt: DateTime.now().toUtc(),
    );
    final finalFile = file.copyWith(frontMatter: fm);
    final content = finalFile.serialize();

    if (content.length > maxBytes) {
      throw WikiWriteException(
        '内容超过 ${maxBytes ~/ 1024}KB 限制',
        code: 'content_too_large',
      );
    }

    // 原子写：tmp → fsync → rename
    final tmp = File('$absPath.tmp');
    await tmp.writeAsString(content, flush: true);
    if (await target.exists()) await target.delete();
    await tmp.rename(absPath);

    // 审计日志
    await _appendAudit(
      existed ? 'update' : 'create',
      file.relativePath,
      sizeBytes: content.length,
    );

    log.debug(
      '📝 写入 ${file.relativePath} (${content.length}B, kind=${kind.name})',
    );
  }

  /// 备份到 `.backup/{path}.{ts}.bak`
  Future<void> _backup(String relativePath) async {
    try {
      final src = File(p.join(wikiRoot, relativePath));
      if (!await src.exists()) return;
      final ts = DateTime.now().toUtc().millisecondsSinceEpoch;
      final backupDir = Directory(p.join(wikiRoot, '.backup'));
      if (!await backupDir.exists()) await backupDir.create(recursive: true);
      // 备份文件名保留原路径结构（用 __ 替换 /）
      final safeName = relativePath.replaceAll('/', '__');
      final dst = File(p.join(backupDir.path, '$safeName.$ts.bak'));
      await src.copy(dst.path);
    } catch (e) {
      log.debug('⚠️ 备份失败：$relativePath / $e');
    }
  }

  /// 追加一条审计日志到 `.audit.log`
  Future<void> _appendAudit(
    String action,
    String relativePath, {
    required int sizeBytes,
  }) async {
    try {
      final auditDir = Directory(p.join(wikiRoot, '.meta'));
      if (!await auditDir.exists()) await auditDir.create(recursive: true);
      final log = File(p.join(auditDir.path, '.audit.log'));
      final entry = jsonEncode({
        'ts': DateTime.now().toUtc().toIso8601String(),
        'action': action,
        'path': relativePath,
        'size_bytes': sizeBytes,
      });
      await log.writeAsString('$entry\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // 审计日志失败不应阻塞主写入
    }
  }

  // ───────────────────────── 路径校验 ─────────────────────────

  /// 校验路径必须落在 wiki/ 白名单内
  void _validatePath(WikiFileKind kind, String relativePath) {
    if (relativePath.isEmpty) {
      throw WikiWriteException('路径不能为空', code: 'empty_path');
    }
    if (relativePath.contains('..')) {
      throw WikiWriteException('路径不允许包含 `..`', code: 'parent_dir');
    }
    if (p.isAbsolute(relativePath)) {
      throw WikiWriteException('不允许使用绝对路径', code: 'absolute_path');
    }
    // 不允许写入 .meta/ 或 .backup/
    if (relativePath.startsWith('.meta/') ||
        relativePath.startsWith('.backup/') ||
        relativePath.startsWith('raw/')) {
      throw WikiWriteException(
        '不允许写入此目录',
        code: 'forbidden_dir',
      );
    }

    // 类型路径白名单
    switch (kind) {
      case WikiFileKind.profile:
        if (relativePath != 'profile.md') {
          throw WikiWriteException(
            'profile 类型必须写到 profile.md',
            code: 'wrong_path',
          );
        }
        break;
      case WikiFileKind.todo:
        if (!RegExp(r'^todos/todo-[a-f0-9-]+\.md$').hasMatch(relativePath)) {
          throw WikiWriteException(
            'todo 类型必须写到 todos/todo-{uuid}.md',
            code: 'wrong_path',
          );
        }
        break;
      case WikiFileKind.session:
        if (!RegExp(r'^sessions/[^/]+\.md$').hasMatch(relativePath)) {
          throw WikiWriteException(
            'session 类型必须写到 sessions/{sessionId}.md',
            code: 'wrong_path',
          );
        }
        break;
      case WikiFileKind.concept:
        if (!RegExp(r'^concepts/[^/]+\.md$').hasMatch(relativePath)) {
          throw WikiWriteException(
            'concept 类型必须写到 concepts/{entityId}.md',
            code: 'wrong_path',
          );
        }
        break;
      case WikiFileKind.indexFile:
        if (relativePath != 'index.md') {
          throw WikiWriteException('index 类型必须写到 index.md', code: 'wrong_path');
        }
        break;
      case WikiFileKind.schema:
        throw WikiWriteException('schema.md 不可写', code: 'schema_immutable');
      case WikiFileKind.unknown:
        // 未知类型：允许任意 wiki/ 下非系统路径
        if (relativePath == 'schema.md' ||
            relativePath == 'context-settings.md' ||
            relativePath == 'api-configs.md') {
          throw WikiWriteException(
            '此路径不在写入白名单',
            code: 'not_writable',
          );
        }
        break;
    }
  }
}