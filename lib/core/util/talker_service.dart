import 'package:flutter/foundation.dart';

/// 全局日志服务（单例）
///
/// 使用 Flutter 内置 debugPrint 实现，支持 tag 过滤。
///
/// 标签前缀约定：
/// - [LLM]       → LLM 请求/响应（Provider 层面）
/// - [CHAT]      → 对话业务逻辑（Controller 层面）
/// - [DB]        → 数据库操作
/// - [WIKI]      → Wiki 文件操作
/// - [HTTP]      → HTTP 网络请求
/// - [SESSION]   → 会话管理
/// - [PERM]      → 权限操作
/// - [UI]        → UI 交互
///
/// 过滤示例：
///   TalkerService().setFilter(['LLM', 'CHAT']);  // 只看 LLM 和 CHAT
///   TalkerService().setFilter([]);               // 显示全部
class TalkerService {
  TalkerService._();
  static final _instance = TalkerService._();
  static TalkerService get instance => _instance;

  List<String> _filter = [];

  /// 初始化
  void init() {
    debugPrint('[Talker] 全局日志服务已初始化，filter=$_filter');
  }

  /// 设置标签过滤器（仅显示指定 tag 的日志）
  void setFilter(List<String> tags) {
    _filter = tags;
    debugPrint('[Talker] 过滤器已更新: $tags');
  }

  /// 是否应该打印此消息
  bool _shouldPrint(String tag) {
    if (_filter.isEmpty) return true;
    return _filter.contains(tag);
  }

  void debug(String message) => debugPrint(message);
  void info(String message) => debugPrint(message);

  // ── 带 tag 的快捷方法 ──────────────────────────────────

  void llm(String message) {
    if (_shouldPrint(kTagLlm)) debugPrint('[$kTagLlm] $message');
  }

  void llmReq(String message) {
    if (_shouldPrint(kTagLlm)) debugPrint('[$kTagLlm] 📤 $message');
  }

  void llmResp(String message) {
    if (_shouldPrint(kTagLlm)) debugPrint('[$kTagLlm] 📥 $message');
  }

  void llmError(String message) {
    if (_shouldPrint(kTagLlm)) debugPrint('[$kTagLlm] ❌ $message');
  }

  void chat(String message) {
    if (_shouldPrint(kTagChat)) debugPrint('[$kTagChat] $message');
  }

  void chatInfo(String message) {
    if (_shouldPrint(kTagChat)) debugPrint('[$kTagChat] $message');
  }

  void db(String message) {
    if (_shouldPrint(kTagDb)) debugPrint('[$kTagDb] $message');
  }

  void dbInfo(String message) {
    if (_shouldPrint(kTagDb)) debugPrint('[$kTagDb] $message');
  }

  void wiki(String message) {
    if (_shouldPrint(kTagWiki)) debugPrint('[$kTagWiki] $message');
  }

  void http(String message) {
    if (_shouldPrint(kTagHttp)) debugPrint('[$kTagHttp] $message');
  }

  void httpInfo(String message) {
    if (_shouldPrint(kTagHttp)) debugPrint('[$kTagHttp] $message');
  }

  void session(String message) {
    if (_shouldPrint(kTagSession)) debugPrint('[$kTagSession] $message');
  }

  void ui(String message) {
    if (_shouldPrint(kTagUi)) debugPrint('[$kTagUi] $message');
  }

  void perm(String message) {
    if (_shouldPrint(kTagPerm)) debugPrint('[$kTagPerm] $message');
  }

  // ── Tag 常量 ───────────────────────────────────────────

  static const String kTagLlm = 'LLM';
  static const String kTagChat = 'CHAT';
  static const String kTagDb = 'DB';
  static const String kTagWiki = 'WIKI';
  static const String kTagHttp = 'HTTP';
  static const String kTagSession = 'SESSION';
  static const String kTagUi = 'UI';
  static const String kTagPerm = 'PERM';
}
