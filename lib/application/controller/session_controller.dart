import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../../core/core.dart';
import '../../data/repository/i_session_repository.dart';
import '../../data/repository/file_session_repository.dart';
import '../../data/storage/session_storage.dart';
import '../../data/storage/owl_root.dart';

/// 会话管理控制器（v6.4）
///
/// 基于 ChangeNotifier + Riverpod。
/// 所有可变字段在修改后调用 [notifyListeners] 触发 UI 重建。
///
/// v6.4 变更：
/// - 使用 [ISessionRepository] 替代内存仓库，持久化到 JSONL 文件
/// - 修复 Stream 订阅泄漏（保存 subscription，在 dispose 中 cancel）
/// - 修复 _onSessionChanged 竞态（加载消息异步完成后再切换）
class SessionController extends ChangeNotifier {
  SessionController(this._ref) {
    log.debug('初始化 SessionController');
    _initialize();
  }

  final Ref _ref;

  late final ISessionRepository _repo;

  StreamSubscription<void>? _changesSubscription;

  // ── 内部可变状态 ──

  List<Session> _sessions = const [];
  Session? _currentSession;
  List<Message> _currentMessages = const [];

  // ── Getters ──

  List<Session> get sessions => _sessions;
  Session? get currentSession => _currentSession;
  List<Message> get currentMessages => _currentMessages;

  /// 异步初始化：从磁盘加载会话列表 + 订阅变更流
  Future<void> _initialize() async {
    log.debug('初始化 SessionRepository');
    // 创建 SessionStorage 和 FileSessionRepository
    final owlRoot = OwlRoot.instance;
    final storage = SessionStorage(owlRoot: owlRoot.rootPath!);
    _repo = FileSessionRepository(storage);

    // 订阅变更流（保存 subscription，在 dispose 中 cancel）
    _changesSubscription = _repo.changes.listen((_) {
      _syncFromRepo(); // fire-and-forget
    });

    // 加载会话列表
    await loadSessions();
    log.info('SessionController 初始化完成');
  }

  /// 从仓库同步到 UI 状态
  Future<void> _syncFromRepo() async {
    _sessions = await _repo.listAll();
    if (_currentSession == null && _sessions.isNotEmpty) {
      _currentSession = _sessions.first;
    }
    notifyListeners();
  }

  /// 从仓库加载所有会话列表
  ///
  /// 加载完成后如果存在会话，默认选中第一个（最新更新的）。
  Future<void> loadSessions() async {
    try {
      log.debug('加载会话列表...');
      _sessions = await _repo.listAll();
      if (_currentSession == null && _sessions.isNotEmpty) {
        _currentSession = _sessions.first;
        // 加载当前会话的消息
        await _loadMessages(_currentSession!.id);
      }
      log.info('加载了 ${_sessions.length} 个会话');
      notifyListeners();
    } catch (e, st) {
      log.error('加载会话列表失败：$e', st);
    }
  }

  /// 加载指定会话的消息
  Future<void> _loadMessages(String sessionId) async {
    try {
      log.debug('加载消息: $sessionId');
      _currentMessages = await _repo.loadMessages(sessionId);
      log.debug('加载了 ${_currentMessages.length} 条消息');
    } catch (e, st) {
      log.error('加载消息失败：$e', st);
      _currentMessages = const [];
    }
  }

  /// 创建新会话
  ///
  /// [name] 会话名称，创建后自动设为当前会话。
  Future<Session?> createSession(String name) async {
    try {
      log.info('创建新会话: $name');
      final session = await _repo.create(name);
      _sessions = await _repo.listAll();
      _currentSession = session;
      _currentMessages = const [];
      notifyListeners();
      log.info('会话创建成功: ${session?.id}');
      return session;
    } catch (e, st) {
      log.error('创建会话失败：$e', st);
      return null;
    }
  }

  /// 切换当前会话
  ///
  /// [id] 目标会话的唯一标识。
  /// 如果找到对应会话则设为当前会话，并加载其消息。
  Future<void> switchSession(String id) async {
    log.info('切换会话: $id');
    final index = _sessions.indexWhere((s) => s.id == id);
    if (index != -1) {
      _currentSession = _sessions[index];
      await _loadMessages(id);
      notifyListeners();
      log.info('已切换到会话: ${_currentSession?.name}');
    } else {
      log.error('未找到指定会话: $id');
    }
  }

  /// 删除指定会话
  Future<void> deleteSession(String id) async {
    try {
      await _repo.delete(id);
      _sessions = await _repo.listAll();

      // 如果删除的是当前会话，切换到列表中第一个
      if (_currentSession?.id == id) {
        _currentSession = _sessions.isNotEmpty ? _sessions.first : null;
        _currentMessages = _currentSession != null
            ? await _repo.loadMessages(_currentSession!.id)
            : const [];
      }
      notifyListeners();
    } catch (e) {
      debugPrint('删除会话失败：$e');
    }
  }

  /// 归档指定会话
  Future<void> archiveSession(String id) async {
    try {
      await _repo.archive(id);
      _sessions = await _repo.listAll();

      // 如果归档的是当前会话，切换到下一个
      if (_currentSession?.id == id) {
        final activeSessions = _sessions.where((s) => !s.archived).toList();
        _currentSession =
            activeSessions.isNotEmpty ? activeSessions.first : null;
        _currentMessages = _currentSession != null
            ? await _repo.loadMessages(_currentSession!.id)
            : const [];
      }
      notifyListeners();
    } catch (e) {
      debugPrint('归档会话失败：$e');
    }
  }

  /// 重命名指定会话
  Future<void> renameSession(String id, String name) async {
    try {
      final session = await _repo.getById(id);
      if (session == null) return;
      await _repo.update(session.copyWith(name: name));
      _sessions = await _repo.listAll();

      // 如果是当前会话，同步更新
      if (_currentSession?.id == id) {
        _currentSession = _sessions.firstWhere((s) => s.id == id);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('重命名失败：$e');
    }
  }

  /// 自动为会话命名
  ///
  /// 简易方案：截取消息前 15 个字符作为会话名称。
  Future<void> autoNameSession(String id, String firstMessage) async {
    final name = firstMessage.length > 15
        ? firstMessage.substring(0, 15)
        : firstMessage;
    await renameSession(id, name);
  }

  /// 切换会话顶置状态
  Future<void> togglePin(String id) async {
    final session = await _repo.getById(id);
    if (session == null) return;
    await _repo.update(session.copyWith(pinned: !session.pinned));
    _sessions = await _repo.listAll();
    notifyListeners();
  }

  /// 更新会话上下文（供 ChatController 等调用）
  ///
  /// v6.4：不再使用 context JSON 字符串，改为追加消息到 messages.jsonl
  Future<void> appendMessages(String id, List<Message> messages) async {
    try {
      await _repo.appendMessages(id, messages);
      _sessions = await _repo.listAll();
      // 同步更新 currentSession 引用
      if (_currentSession?.id == id) {
        final updated = await _repo.getById(id);
        if (updated != null) _currentSession = updated;
        // 追加到内存中的消息列表
        _currentMessages = [..._currentMessages, ...messages];
      }
      notifyListeners();
    } catch (e) {
      debugPrint('追加消息失败：$e');
    }
  }

  /// 全量替换当前会话消息（用于加载历史消息）
  void setMessages(List<Message> messages) {
    _currentMessages = messages;
    notifyListeners();
  }

  /// 取消归档会话
  Future<void> unarchiveSession(String id) async {
    try {
      await _repo.unarchive(id);
      _sessions = await _repo.listAll();
      notifyListeners();
    } catch (e) {
      debugPrint('取消归档失败：$e');
    }
  }

  @override
  void dispose() {
    // 修复 C1：取消 StreamSubscription 订阅，防止内存泄漏
    _changesSubscription?.cancel();
    if (_repo is FileSessionRepository) {
      (_repo as FileSessionRepository).dispose();
    }
    super.dispose();
  }
}

/// Riverpod Provider：暴露 [SessionController]
final sessionControllerProvider =
    ChangeNotifierProvider<SessionController>(
  (ref) => SessionController(ref),
);
