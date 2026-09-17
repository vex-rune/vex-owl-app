import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../../core/core.dart';
import '../service/in_memory_session_repository.dart';
import '../service/session_file_service.dart';

/// 会话管理控制器（基于 ChangeNotifier + Riverpod）
///
/// 负责会话的 CRUD 操作、切换、归档、自动命名等逻辑。
/// **Phase 1.5（SQLite 清理阶段）**：使用内存仓库 + wiki/sessions/*.md 文件级操作。
/// - 内存中保存会话元数据和最近 20 条消息（启动后从文件加载，变更后写回）
/// - `wiki/sessions/{date}-{name}.md` 作为「摘要 + 近期消息」的可浏览备份
/// - 完整的双向迁移（包含摘要压缩）将在 Phase 3 完成
///
/// 所有可变字段在修改后调用 [notifyListeners] 触发 UI 重建。
class SessionController extends ChangeNotifier {
  SessionController(this._ref) {
    _initialize();
  }

  final Ref _ref;

  late final InMemorySessionRepository _repo = InMemorySessionRepository.instance;
  late final SessionFileService _fileService =
      SessionFileService(_ref.read(wikiRepositoryProvider));

  // ── 内部可变状态 ──

  List<Session> _sessions = const [];
  Session? _currentSession;

  // ── Getters ──

  List<Session> get sessions => _sessions;
  Session? get currentSession => _currentSession;

  /// 异步初始化：确保目录存在 + 订阅变更流
  Future<void> _initialize() async {
    try {
      await _fileService.ensureDirectory();
    } catch (e) {
      debugPrint('初始化 sessions 目录失败：$e');
    }
    _repo.changes.listen((_) => _syncFromRepo());
    await loadSessions();
  }

  /// 从内存仓库同步到 UI 状态
  void _syncFromRepo() {
    _sessions = _repo.listAll();
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
      _sessions = _repo.listAll();
      if (_currentSession == null && _sessions.isNotEmpty) {
        _currentSession = _sessions.first;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('加载会话列表失败：$e');
    }
  }

  /// 创建新会话
  ///
  /// [name] 会话名称，创建后自动设为当前会话。
  /// 返回新创建的会话对象。
  Future<Session?> createSession(String name) async {
    try {
      final session = await _repo.create(name);
      _sessions = _repo.listAll();
      _currentSession = session;
      notifyListeners();
      return session;
    } catch (e) {
      debugPrint('创建会话失败：$e');
      return null;
    }
  }

  /// 切换当前会话
  ///
  /// [id] 目标会话的唯一标识。
  /// 如果找到对应会话则设为当前会话。
  void switchSession(String id) {
    final index = _sessions.indexWhere((s) => s.id == id);
    if (index != -1) {
      _currentSession = _sessions[index];
      notifyListeners();
    } else {
      debugPrint('未找到指定会话');
    }
  }

  /// 删除指定会话
  ///
  /// [id] 要删除的会话 ID。
  /// 删除后如果该会话是当前选中的，自动切换到列表中的下一个会话。
  Future<void> deleteSession(String id) async {
    try {
      await _repo.delete(id);
      _sessions = _repo.listAll();

      // 如果删除的是当前会话，切换到列表中第一个
      if (_currentSession?.id == id) {
        _currentSession = _sessions.isNotEmpty ? _sessions.first : null;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('删除会话失败：$e');
    }
  }

  /// 归档指定会话
  ///
  /// [id] 要归档的会话 ID。
  Future<void> archiveSession(String id) async {
    try {
      await _repo.archive(id);
      _sessions = _repo.listAll();

      // 如果归档的是当前会话，切换到下一个
      if (_currentSession?.id == id) {
        final activeSessions = _sessions.where((s) => !s.archived).toList();
        _currentSession =
            activeSessions.isNotEmpty ? activeSessions.first : null;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('归档会话失败：$e');
    }
  }

  /// 重命名指定会话
  Future<void> renameSession(String id, String name) async {
    try {
      await _repo.updateName(id, name);
      _sessions = _repo.listAll();

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
  ///
  /// 若已顶置则取消，否则设为顶置。
  Future<void> togglePin(String id) async {
    final s = _repo.getById(id);
    if (s == null) return;
    await _repo.setPinned(id, !s.pinned);
    _sessions = _repo.listAll();
    notifyListeners();
  }

  /// 更新会话上下文（供 ChatController 等调用）
  Future<void> updateSessionContext(String id, String context) async {
    try {
      await _repo.updateContext(id, context);
    } catch (e) {
      debugPrint('更新会话上下文失败：$e');
    }
  }
}

/// Riverpod Provider：暴露 [SessionController]
final sessionControllerProvider =
    ChangeNotifierProvider<SessionController>(
  (ref) => SessionController(ref),
);
