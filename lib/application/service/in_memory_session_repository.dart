/// 内存态会话仓库（Phase 1 过渡用，Phase 3 将被 wiki/sessions/*.md 替代）。
///
/// 设计原则：
/// - 不再依赖任何持久化层（SQLite 已全部移除）
/// - 提供 `ISessionRepository` 兼容接口（基于旧的 `Session` 模型）
/// - 内存保存所有会话，重启后清空
/// - Phase 3 完成 Session ↔ wiki/sessions/*.md 完整迁移后，本类将被删除
library;

import 'dart:async';
import 'dart:math';

import '../../core/model/session.dart';

/// 内存会话仓库
///
/// 单例，所有 SessionController 共享同一份内存状态。
class InMemorySessionRepository {
  InMemorySessionRepository._();
  static final InMemorySessionRepository instance = InMemorySessionRepository._();

  final Map<String, Session> _sessions = {};
  final _changes = StreamController<void>.broadcast();

  /// 订阅数据变更（用于其他组件监听变化）
  Stream<void> get changes => _changes.stream;

  /// 获取所有会话（按 updatedAt 降序）
  List<Session> listAll() {
    final list = _sessions.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  /// 根据 ID 获取
  Session? getById(String id) => _sessions[id];

  /// 创建会话
  Future<Session> create(String name) async {
    final now = DateTime.now();
    final id = _generateId();
    final session = Session(
      id: id,
      name: name,
      createdAt: now,
      updatedAt: now,
      archived: false,
    );
    _sessions[id] = session;
    _changes.add(null);
    return session;
  }

  /// 更新名称
  Future<void> updateName(String id, String name) async {
    final s = _sessions[id];
    if (s == null) return;
    _sessions[id] = s.copyWith(name: name, updatedAt: DateTime.now());
    _changes.add(null);
  }

  /// 更新上下文（消息 JSON 字符串）
  Future<void> updateContext(String id, String context) async {
    final s = _sessions[id];
    if (s == null) return;
    _sessions[id] = s.copyWith(
      context: context,
      updatedAt: DateTime.now(),
      messageCount: _countMessages(context),
    );
    _changes.add(null);
  }

  /// 删除会话
  Future<void> delete(String id) async {
    if (_sessions.remove(id) != null) _changes.add(null);
  }

  /// 归档会话
  Future<void> archive(String id) async {
    final s = _sessions[id];
    if (s == null) return;
    _sessions[id] = s.copyWith(archived: true, updatedAt: DateTime.now());
    _changes.add(null);
  }

  /// 设置会话顶置状态
  Future<void> setPinned(String id, bool pinned) async {
    final s = _sessions[id];
    if (s == null) return;
    _sessions[id] = s.copyWith(pinned: pinned, updatedAt: DateTime.now());
    _changes.add(null);
  }

  /// 清空所有会话
  void clear() {
    _sessions.clear();
    _changes.add(null);
  }

  /// 关闭资源
  void dispose() {
    _changes.close();
  }

  /// 生成会话唯一 ID（UUID 简化版）
  String _generateId() {
    final rand = Random();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  int _countMessages(String context) {
    if (context.trim().isEmpty) return 0;
    try {
      // 简单计数：解析 JSON 数组长度
      final trimmed = context.trim();
      if (!trimmed.startsWith('[')) return 0;
      return trimmed.split(RegExp(r'(?<=}),(?=\{)')).length;
    } catch (_) {
      return 0;
    }
  }
}