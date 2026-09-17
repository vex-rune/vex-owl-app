/// 原子文件写入器（v6.4）
///
/// 从 WikiFileWriter 中抽取的通用原子写入基础设施，供所有存储层复用：
/// - 原子写入：tmp → rename（含 Windows 兼容）
/// - 备份：原文件 → .backup/{path}.{ts}.bak
/// - 审计日志：追加到 .audit.log
/// - 文件锁：共享 WikiLockService
/// - JSONL 追加：appendLine / appendAll
///
/// 设计原则：
/// - 所有写操作走原子写入（tmp → rename），崩溃后最多丢失最后一条
/// - JSONL 追加用 FileMode.append，不走原子写（append 单行是 OS 原子操作）
/// - 文件锁由 WikiLockService 统一管理（TTL 5 分钟防死锁）
library;

import 'dart:convert' as convert;
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/core.dart';
import '../../application/service/wiki_lock_service.dart';

/// 原子写入异常
class AtomicWriteException implements Exception {
  AtomicWriteException(this.message, {this.code = 'atomic_write_failed'});

  final String message;
  final String code;

  @override
  String toString() => '[$code] $message';
}

/// 原子文件写入器
///
/// [rootPath] 应用根目录（`.owl/` 的绝对路径）
class AtomicFileWriter {
  AtomicFileWriter({
    required String rootPath,
    WikiLockService? lockService,
  })  : _rootPath = rootPath,
        _lockService = lockService;

  /// 应用根目录（`.owl/`）
  final String _rootPath;

  /// 文件锁服务（共享 WikiLockService 实例）
  final WikiLockService? _lockService;

  /// 1MB 写入上限
  static const int maxBytes = 1024 * 1024;

  // ── 公开 API ─────────────────────────────────────────────────────────────

  /// 原子写入文件（tmp → rename），含备份 + 审计
  ///
  /// [relativePath] 相对于 rootPath 的路径，如 `sessions/abc/session.jsonl`
  /// [content] 文件内容
  /// [owner] 锁持有者（默认 userEdit）
  Future<void> write(
    String relativePath,
    String content, {
    LockOwner owner = LockOwner.userEdit,
  }) async {
    _validatePath(relativePath);

    if (content.length > maxBytes) {
      throw AtomicWriteException(
        '内容超过 ${maxBytes ~/ 1024}KB 限制',
        code: 'content_too_large',
      );
    }

    Future<void> doWrite() async {
      final absPath = p.join(_rootPath, relativePath);
      final target = File(absPath);

      // 确保父目录存在
      if (!await target.parent.exists()) {
        await target.parent.create(recursive: true);
      }

      // 备份原文件
      final existed = await target.exists();
      if (existed) {
        await _backup(relativePath);
      }

      // 原子写：tmp → rename
      final tmp = File('$absPath.tmp');
      await tmp.writeAsString(content, flush: true);
      if (existed) await target.delete();
      await _renameAtomic(absPath, tmp.path);

      // 审计
      await _appendAudit(
        existed ? 'update' : 'create',
        relativePath,
        sizeBytes: content.length,
      );

      log.debug(
        '📝 写入 $relativePath (${content.length}B)',
      );
    }

    if (_lockService != null) {
      await _lockService!.withLock(
        owner: owner,
        operation: 'write:$relativePath',
        action: (_) => doWrite(),
      );
    } else {
      await doWrite();
    }
  }

  /// JSONL 追加写入（直接 append，不加锁）
  ///
  /// 适用于 messages.jsonl 新消息追加。单行 append 在大多数 OS 上是原子操作。
  /// 若文件不存在则创建；若文件末尾无换行则先补换行。
  Future<void> appendLine(String relativePath, String line) async {
    _validatePath(relativePath);
    final absPath = p.join(_rootPath, relativePath);

    final file = File(absPath);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }

    // 检测末尾是否已有换行
    String toWrite = line;
    if (await file.exists()) {
      final length = await file.length();
      if (length > 0) {
        // 读取最后 1 字节判断
        final raf = await file.open(mode: FileMode.read);
        await raf.setPosition(length - 1);
        final lastByte = await raf.readByte();
        await raf.close();
        if (lastByte != 10 && lastByte != 13) {
          // 末尾无换行，补一个
          toWrite = '\n$line';
        }
      }
    }

    await file.writeAsString('$toWrite\n', mode: FileMode.append, flush: true);
  }

  /// JSONL 批量追加（等同于多次 appendLine）
  Future<void> appendAll(
    String relativePath,
    List<String> lines,
  ) async {
    for (final line in lines) {
      await appendLine(relativePath, line);
    }
  }

  /// 原子删除文件（先备份，再删除）
  Future<void> delete(
    String relativePath, {
    LockOwner owner = LockOwner.userEdit,
  }) async {
    _validatePath(relativePath);

    Future<void> doDelete() async {
      final absPath = p.join(_rootPath, relativePath);
      final file = File(absPath);
      if (await file.exists()) {
        await _backup(relativePath);
        await file.delete();
        await _appendAudit('delete', relativePath, sizeBytes: 0);
        log.debug('🗑️ 删除 $relativePath');
      }
    }

    if (_lockService != null) {
      await _lockService!.withLock(
        owner: owner,
        operation: 'delete:$relativePath',
        action: (_) => doDelete(),
      );
    } else {
      await doDelete();
    }
  }

  /// 执行带锁操作（由调用方决定锁粒度）
  Future<T> withLock<T>({
    required LockOwner owner,
    required String operation,
    required Future<T> Function() action,
  }) async {
    final fn = action;
    if (_lockService != null) {
      return _lockService!.withLock(
        owner: owner,
        operation: operation,
        action: (_) => fn(),
      );
    }
    return fn();
  }

  /// 删除目录（递归删除）
  Future<void> deleteDirectory(String relativePath) async {
    _validatePath(relativePath);
    final absPath = p.join(_rootPath, relativePath);
    final dir = Directory(absPath);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      log.debug('🗑️ 删除目录 $relativePath');
    }
  }

  // ── 内部实现 ─────────────────────────────────────────────────────────────

  /// 备份到 `.backup/{path}.{ts}.bak`
  Future<void> _backup(String relativePath) async {
    try {
      final src = File(p.join(_rootPath, relativePath));
      if (!await src.exists()) return;

      final backupDir = Directory(p.join(_rootPath, '.backup'));
      if (!await backupDir.exists()) await backupDir.create(recursive: true);

      // 备份文件名保留原路径结构（用 __ 替换 /）
      final safeName = relativePath.replaceAll('/', '__');
      final ts = DateTime.now().toUtc().millisecondsSinceEpoch;
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
      final auditDir = Directory(p.join(_rootPath, '.meta'));
      if (!await auditDir.exists()) await auditDir.create(recursive: true);
      final log = File(p.join(auditDir.path, '.audit.log'));
      final entry = convert.jsonEncode({
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

  /// 原子重命名（Windows 兼容）
  ///
  /// Windows 10+ 支持 rename 直接覆盖；旧版回退 copy → delete。
  Future<void> _renameAtomic(String targetPath, String tmpPath) async {
    final tmp = File(tmpPath);
    try {
      // 优先尝试直接 rename（Windows 10+ 支持覆盖）
      await tmp.rename(targetPath);
    } catch (e) {
      // rename 失败（可能是 Windows 上目标文件被占用），回退 copy + delete
      try {
        final target = File(targetPath);
        await tmp.copy(targetPath);
        await tmp.delete();
        log.debug(
          '⚠️ rename 回退 copy+delete：$targetPath',
        );
      } catch (_) {
        throw AtomicWriteException('原子写入失败：$e', code: 'rename_failed');
      }
    }
  }

  /// 路径校验
  void _validatePath(String relativePath) {
    if (relativePath.isEmpty) {
      throw AtomicWriteException('路径不能为空', code: 'empty_path');
    }
    if (relativePath.contains('..')) {
      throw AtomicWriteException('路径不允许包含 `..`', code: 'parent_dir');
    }
    if (p.isAbsolute(relativePath)) {
      throw AtomicWriteException('不允许使用绝对路径', code: 'absolute_path');
    }
    // 不允许直接操作 .meta/ 和 .backup/ 根目录
    if (relativePath == '.meta' || relativePath == '.backup' ||
        relativePath.startsWith('.meta/') || relativePath.startsWith('.backup/')) {
      throw AtomicWriteException(
        '不允许直接操作 .meta/ 或 .backup/',
        code: 'forbidden_dir',
      );
    }
  }
}

/// JSONL 文件读写工具类
class JsonlFile {
  JsonlFile._();

  /// 逐行读取，每行 jsonDecode 后返回 Map 列表
  static Future<List<Map<String, dynamic>>> readAll(String path) async {
    final file = File(path);
    if (!await file.exists()) return [];

    final lines = await file.readAsLines();
    final result = <Map<String, dynamic>>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      // 检测末尾不完整行（非 } 结尾则截断）
      if (!trimmed.endsWith('}')) continue;
      try {
        result.add(convert.jsonDecode(trimmed) as Map<String, dynamic>);
      } catch (_) {
        // 损坏行跳过
      }
    }
    return result;
  }

  /// 流式逐行读取（适合大文件）
  static Stream<Map<String, dynamic>> readStream(String path) async* {
    final file = File(path);
    if (!await file.exists()) return;

    await for (final line in file
        .openRead()
        .transform(convert.utf8.decoder)
        .transform(convert.LineSplitter())) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (!trimmed.endsWith('}')) continue;
      try {
        yield convert.jsonDecode(trimmed) as Map<String, dynamic>;
      } catch (_) {
        // 损坏行跳过
      }
    }
  }

  /// 全量覆写（每行一个 JSON 对象，末尾加换行符）
  static Future<void> writeAll(
    String path,
    List<Map<String, dynamic>> objects,
  ) async {
    final file = File(path);
    final dir = file.parent;
    if (!await dir.exists()) await dir.create(recursive: true);

    final buffer = StringBuffer();
    for (final obj in objects) {
      buffer.writeln(convert.jsonEncode(obj));
    }
    await file.writeAsString(buffer.toString());
  }

  /// 追加一行（文件末尾直接 writeln）
  static Future<void> appendLine(
    String path,
    Map<String, dynamic> object,
  ) async {
    final file = File(path);
    final dir = file.parent;
    if (!await dir.exists()) await dir.create(recursive: true);

    final line = convert.jsonEncode(object);
    // 检测末尾换行
    String toWrite = line;
    if (await file.exists()) {
      final length = await file.length();
      if (length > 0) {
        final raf = await file.open(mode: FileMode.read);
        await raf.setPosition(length - 1);
        final lastByte = await raf.readByte();
        await raf.close();
        if (lastByte != 10 && lastByte != 13) {
          toWrite = '\n$line';
        }
      }
    }

    await file.writeAsString('$toWrite\n', mode: FileMode.append, flush: true);
  }

  /// 追加多行
  static Future<void> appendAll(
    String path,
    List<Map<String, dynamic>> objects,
  ) async {
    for (final obj in objects) {
      await appendLine(path, obj);
    }
  }
}
