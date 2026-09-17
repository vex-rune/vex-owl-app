/// 文件系统会话仓库实现（v6.4）
///
/// 实现 [ISessionRepository] 接口，内部调用 [SessionStorage]。
/// 提供变更流供外部监听。
library;

import 'dart:async';

import '../../core/model/session.dart';
import '../../core/model/message.dart';
import 'i_session_repository.dart';
import '../storage/session_storage.dart';

/// 文件系统会话仓库
class FileSessionRepository implements ISessionRepository {
  FileSessionRepository(this._storage) {
    _changesController.onListen = null; // 确保 broadcast
  }

  final SessionStorage _storage;

  final _changesController = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changesController.stream;

  void _notifyChanged() {
    _changesController.add(null);
  }

  // ── ISessionRepository 实现 ───────────────────────────────────────────

  @override
  Future<List<Session>> listAll() => _storage.listAll();

  @override
  Future<Session?> getById(String sessionId) => _storage.load(sessionId);

  @override
  Future<Session> create(String name) async {
    final session = await _storage.create(name);
    _notifyChanged();
    return session;
  }

  @override
  Future<void> update(Session session) async {
    final updated = session.copyWith(updatedAt: DateTime.now());
    await _storage.save(updated);
    _notifyChanged();
  }

  @override
  Future<void> delete(String sessionId) async {
    await _storage.delete(sessionId);
    _notifyChanged();
  }

  @override
  Future<void> archive(String sessionId) async {
    await _storage.archive(sessionId);
    _notifyChanged();
  }

  @override
  Future<void> unarchive(String sessionId) async {
    await _storage.unarchive(sessionId);
    _notifyChanged();
  }

  @override
  Future<List<Message>> loadMessages(String sessionId) =>
      _storage.loadMessages(sessionId);

  @override
  Future<void> saveMessages(String sessionId, List<Message> messages) async {
    await _storage.saveMessages(sessionId, messages);
  }

  @override
  Future<void> appendMessages(String sessionId, List<Message> messages) async {
    if (messages.isEmpty) return;
    await _storage.appendMessages(sessionId, messages);
    // 更新会话 messageCount
    final session = await _storage.load(sessionId);
    if (session != null) {
      final updated = session.copyWith(
        messageCount: session.messageCount + messages.length,
        updatedAt: DateTime.now(),
      );
      await _storage.save(updated);
      _notifyChanged();
    }
  }

  /// 关闭资源
  void dispose() {
    _changesController.close();
  }
}
