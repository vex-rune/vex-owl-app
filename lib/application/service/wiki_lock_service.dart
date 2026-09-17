/// Wiki 文件锁服务（v5.0）
///
/// 基于 `wiki/.meta/wiki.lock` 的简单文件锁：
/// - 写入 Wiki 文件前必须 `acquire`（带 TTL，默认 5 分钟）
/// - 写入完成后立即 `release`
/// - TTL 过期自动失效（防崩溃遗留死锁）
/// - 同一时刻只允许一个写者；多个读者可并发
///
/// 锁文件结构：
/// ```json
/// {
///   "version": 1,
///   "lock_id": "uuid-v4",
///   "owner": "ingest|compressor|user_edit|export",
///   "acquired_at": "2026-09-17T10:30:00Z",
///   "expires_at": "2026-09-17T10:35:00Z",
///   "operation": "ingest_session_abc123"
/// }
/// ```
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/util/talker_service.dart';

/// 锁持有者类型
enum LockOwner {
  ingest('ingest'),
  compressor('compressor'),
  userEdit('user_edit'),
  export('export');

  const LockOwner(this.value);
  final String value;

  static LockOwner fromString(String s) {
    for (final o in LockOwner.values) {
      if (o.value == s) return o;
    }
    return LockOwner.userEdit;
  }
}

/// 锁文件内容
class WikiLock {
  const WikiLock({
    required this.lockId,
    required this.owner,
    required this.acquiredAt,
    required this.expiresAt,
    required this.operation,
  });

  final String lockId;
  final LockOwner owner;
  final DateTime acquiredAt;
  final DateTime expiresAt;
  final String operation;

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);

  Map<String, dynamic> toJson() => {
        'version': 1,
        'lock_id': lockId,
        'owner': owner.value,
        'acquired_at': acquiredAt.toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
        'operation': operation,
      };

  static WikiLock fromJson(Map<String, dynamic> json) {
    return WikiLock(
      lockId: json['lock_id'] as String? ?? '',
      owner: LockOwner.fromString(json['owner'] as String? ?? 'user_edit'),
      acquiredAt:
          DateTime.tryParse(json['acquired_at'] as String? ?? '')?.toUtc() ??
              DateTime.now().toUtc(),
      expiresAt:
          DateTime.tryParse(json['expires_at'] as String? ?? '')?.toUtc() ??
              DateTime.now().toUtc(),
      operation: json['operation'] as String? ?? '',
    );
  }
}

/// 锁获取失败异常
class WikiLockException implements Exception {
  WikiLockException(this.message, {this.code = 'lock_failed'});

  final String message;
  final String code;

  @override
  String toString() => '[$code] $message';
}

/// Wiki 文件锁服务
class WikiLockService {
  WikiLockService(this._wikiRoot);

  /// Wiki 根目录绝对路径（含 `.owl/wiki/` 或 `llm-wiki/wiki/`）
  final String _wikiRoot;

  /// 默认锁 TTL（5 分钟）
  static const Duration defaultTtl = Duration(minutes: 5);

  /// 锁文件路径
  String get _lockPath => p.join(_wikiRoot, '.meta', 'wiki.lock');

  /// 短暂内存缓存：上次持有的 lockId（避免重入）
  String? _lastLockId;
  DateTime? _lastLockAt;

  /// 读取当前锁文件内容
  Future<WikiLock?> readLock() async {
    final file = File(_lockPath);
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return WikiLock.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// 尝试获取锁
  ///
  /// [owner] 操作者身份
  /// [operation] 当前操作的描述（如 `ingest_session_abc`）
  /// [ttl] 锁有效期（默认 5 分钟）
  ///
  /// 返回获取到的锁句柄（用于 release）。失败抛 [WikiLockException]。
  Future<WikiLock> acquire({
    required LockOwner owner,
    required String operation,
    Duration ttl = defaultTtl,
  }) async {
    final lockFile = File(_lockPath);
    final lockDir = lockFile.parent;
    if (!await lockDir.exists()) {
      await lockDir.create(recursive: true);
    }

    // 短时重试：5 次 * 100ms = 500ms 等待，避免短冲突
    for (var attempt = 0; attempt < 5; attempt++) {
      final existing = await readLock();
      if (existing == null || existing.isExpired) {
        // 无锁或已过期 → 抢锁
        final newLock = WikiLock(
          lockId: _genId(),
          owner: owner,
          acquiredAt: DateTime.now().toUtc(),
          expiresAt: DateTime.now().toUtc().add(ttl),
          operation: operation,
        );
        await _writeLockAtomic(newLock);
        _lastLockId = newLock.lockId;
        _lastLockAt = newLock.acquiredAt;
        TalkerService.instance.wiki(
          '🔒 锁已获取：${owner.value} / $operation (ttl=${ttl.inSeconds}s)',
        );
        return newLock;
      }

      // 已被占用 → 短暂等待后重试
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    // 重试后仍被占用 → 抛异常
    final current = await readLock();
    throw WikiLockException(
      'Wiki 文件锁被占用（owner=${current?.owner.value}，'
      'operation=${current?.operation}，'
      'expires_at=${current?.expiresAt.toIso8601String()}）',
      code: 'lock_busy',
    );
  }

  /// 释放锁（仅当 lockId 匹配时释放）
  Future<void> release(WikiLock lock) async {
    final existing = await readLock();
    if (existing == null) return;
    if (existing.lockId != lock.lockId) {
      TalkerService.instance.wiki(
        '⚠️ 释放锁失败：lockId 不匹配（当前=${existing.lockId}，要释放=${lock.lockId}）',
      );
      return;
    }
    try {
      final file = File(_lockPath);
      if (await file.exists()) await file.delete();
      _lastLockId = null;
      _lastLockAt = null;
      TalkerService.instance.wiki('🔓 锁已释放：${lock.operation}');
    } catch (e) {
      TalkerService.instance.wiki('⚠️ 释放锁异常：$e');
    }
  }

  /// 在锁内执行某个异步操作（自动 acquire + release）
  ///
  /// 适用于"必须串行"的写操作块。
  Future<T> withLock<T>({
    required LockOwner owner,
    required String operation,
    required Future<T> Function(WikiLock lock) action,
    Duration ttl = defaultTtl,
  }) async {
    final lock = await acquire(owner: owner, operation: operation, ttl: ttl);
    try {
      return await action(lock);
    } finally {
      await release(lock);
    }
  }

  /// 清理过期锁（启动时调用一次）
  Future<void> cleanupExpired() async {
    final existing = await readLock();
    if (existing != null && existing.isExpired) {
      try {
        final file = File(_lockPath);
        if (await file.exists()) await file.delete();
        TalkerService.instance.wiki('🧹 已清理过期锁：${existing.operation}');
      } catch (_) {
        // ignore
      }
    }
  }

  // ───────────────────────── 内部辅助 ─────────────────────────

  Future<void> _writeLockAtomic(WikiLock lock) async {
    final file = File(_lockPath);
    final tmp = File('${_lockPath}.tmp');
    await tmp.writeAsString(jsonEncode(lock.toJson()), flush: true);
    if (await file.exists()) await file.delete();
    await tmp.rename(_lockPath);
  }

  static int _seq = 0;
  String _genId() {
    _seq = (_seq + 1) & 0xFFFF;
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    return 'lock-$ts-${_seq.toRadixString(36)}';
  }
}