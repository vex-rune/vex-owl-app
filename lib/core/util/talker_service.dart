import 'package:flutter/foundation.dart';

/// 全局日志服务（单例）
///
/// 使用 Flutter 内置 debugPrint 实现，支持自动标签推断和日志级别。
///
/// 日志级别：
/// - DEBUG：详细的调试信息，仅开发时使用
/// - INFO：一般信息，重要操作提示
/// - ERROR：错误信息，需要关注的问题
///
/// 使用方式（自动标签）：
///   import 'package:vexowl/core/core.dart';
///   log.debug('调试信息');           // 自动带上文件名对应的标签
///   log.info('一般信息');
///   log.error('错误信息');
///
/// 文件名 → 标签映射：
///   session_controller.dart   → [SESSION]
///   settings_controller.dart  → [SETTINGS]
///   chat_controller.dart      → [CHAT]
///   *_provider.dart           → [LLM]
///   *_storage.dart            → [DB]
///   wiki_*.dart               → [WIKI]
///
/// 日志级别枚举
enum LogLevel { debug, info, error }

/// 全局日志实例
///
/// 使用方式：
///   import 'package:vexowl/core/core.dart';
///   log.debug('调试信息');  // 自动带上当前文件的标签
///   log.info('一般信息');
///   log.error('错误信息');
final log = TalkerService.instance;

/// 过滤示例：
///   log.setFilter(['LLM', 'CHAT']);  // 只看 LLM 和 CHAT
///   log.setMinLevel(LogLevel.info);   // 只显示 INFO 及以上
class TalkerService {
  TalkerService._();
  static final _instance = TalkerService._();
  static TalkerService get instance => _instance;

  List<String> _filter = [];
  LogLevel _minLevel = LogLevel.debug;

  /// 文件名到标签的映射
  static const Map<String, String> _tagMap = {
    'session': 'SESSION',
    'settings': 'SETTINGS',
    'chat': 'CHAT',
    'wiki': 'WIKI',
    'provider': 'LLM',
    'storage': 'DB',
    'http': 'HTTP',
    'ui': 'UI',
    'perm': 'PERM',
    'file_tools': 'FILE',
  };

  /// 初始化
  void init() {
    debugPrint('[Talker] 全局日志服务已初始化，filter=$_filter');
  }

  /// 设置标签过滤器（仅显示指定 tag 的日志）
  void setFilter(List<String> tags) {
    _filter = tags;
    debugPrint('[Talker] 过滤器已更新: $tags');
  }

  /// 设置最小日志级别（默认 debug 显示全部）
  void setMinLevel(LogLevel level) {
    _minLevel = level;
    debugPrint('[Talker] 最小日志级别已更新: $level');
  }

  /// 从调用栈获取当前文件名
  String _getCallerTag() {
    try {
      final stack = StackTrace.current.toString().split('\n');
      // 跳过前两行（当前方法和 _getCallerTag 本身）
      for (final line in stack.skip(2)) {
        // 匹配文件路径如 #3      package:xxx/session_controller.dart
        final match = RegExp(r'package:\w+/(.+)\.dart').firstMatch(line);
        if (match != null) {
          final fileName = match.group(1)!.toLowerCase();
          // 查找匹配的标签
          for (final entry in _tagMap.entries) {
            if (fileName.contains(entry.key)) {
              return entry.value;
            }
          }
        }
      }
    } catch (_) {}
    return 'APP';
  }

  /// 是否应该打印此消息
  bool _shouldPrint(String tag, LogLevel level) {
    // 检查标签过滤
    if (_filter.isNotEmpty && !_filter.contains(tag)) {
      return false;
    }
    // 检查级别过滤
    return level.index >= _minLevel.index;
  }

  // ── 自动标签的日志方法 ─────────────────────────────────

  void debug(String message) {
    final tag = _getCallerTag();
    if (_shouldPrint(tag, LogLevel.debug)) {
      debugPrint('[$tag] 🔵 $message');
    }
  }

  void info(String message) {
    final tag = _getCallerTag();
    if (_shouldPrint(tag, LogLevel.info)) {
      debugPrint('[$tag] ℹ️ $message');
    }
  }

  /// 错误日志，可选带上堆栈跟踪
  void error(String message, [StackTrace? stackTrace]) {
    final tag = _getCallerTag();
    if (_shouldPrint(tag, LogLevel.error)) {
      debugPrint('[$tag] ❌ $message');
      if (stackTrace != null) {
        // 只打印关键帧，过滤 Flutter 内部帧
        final frames = stackTrace.toString().split('\n');
        final relevant = frames.where((f) => !f.contains('flutter/lib/src')).take(5);
        debugPrint('  StackTrace:\n${relevant.join('\n')}');
      }
    }
  }
}
