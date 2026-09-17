/// 会话文件系统服务（v5）
///
/// 负责扫描 / 创建 / 归档 `wiki/sessions/{sessionId}.md` 会话文件。
/// v5 规范：文件名 = sessionId（稳定），不再使用 {date}-{name}。
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../data/repository/i_wiki_repository.dart';

/// 会话文件服务。
///
/// 负责扫描 / 创建 / 归档 `wiki/sessions/{sessionId}.md` 会话文件。
class SessionFileService {
  SessionFileService(this._wiki);

  final IWikiRepository _wiki;

  /// wiki/sessions 目录的绝对路径（惰性初始化）
  String? _sessionsDir;

  Future<String> get sessionsDir async {
    if (_sessionsDir != null) return _sessionsDir!;
    final wikiRoot = await _wiki.getRootPath();
    _sessionsDir = p.join(wikiRoot, 'sessions');
    return _sessionsDir!;
  }

  /// 扫描 wiki/sessions/*.md（非 .archive 子目录），返回文件名列表
  Future<List<String>> listActiveSessionFiles() async {
    final dir = Directory(await sessionsDir);
    if (!await dir.exists()) return [];
    final files = <String>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File && entity.path.endsWith('.md')) {
        files.add(p.basename(entity.path));
      }
    }
    return files;
  }

  /// 归档会话（移动文件到 .archive/ 子目录）
  Future<void> archiveSessionFile(String fileName) async {
    final src = File(p.join(await sessionsDir, fileName));
    if (!await src.exists()) return;
    final archiveDir = Directory(p.join(await sessionsDir, '.archive'));
    if (!await archiveDir.exists()) {
      await archiveDir.create(recursive: true);
    }
    final dst = File(p.join(archiveDir.path, fileName));
    if (await dst.exists()) {
      // 已存在同名归档文件，覆盖
      await dst.delete();
    }
    await src.rename(dst.path);
  }

  /// 取消归档（从 .archive/ 移回根目录）
  Future<void> unarchiveSessionFile(String fileName) async {
    final archiveDir = Directory(p.join(await sessionsDir, '.archive'));
    final src = File(p.join(archiveDir.path, fileName));
    if (!await src.exists()) return;
    final dst = File(p.join(await sessionsDir, fileName));
    if (await dst.exists()) {
      await dst.delete();
    }
    await src.rename(dst.path);
  }

  /// 删除会话文件（不可逆）
  Future<void> deleteSessionFile(String fileName) async {
    final sessions = Directory(await sessionsDir);
    final candidates = [
      File(p.join(sessions.path, fileName)),
      File(p.join(sessions.path, '.archive', fileName)),
    ];
    for (final f in candidates) {
      if (await f.exists()) await f.delete();
    }
  }

  /// 确保 sessions 目录存在（初始化时调用）
  Future<void> ensureDirectory() async {
    final dir = Directory(await sessionsDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final archive = Directory(p.join(await sessionsDir, '.archive'));
    if (!await archive.exists()) {
      await archive.create(recursive: true);
    }
  }
}