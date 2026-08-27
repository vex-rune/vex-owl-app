import 'dart:developer' as developer;

/// 应用日志工具。
///
/// 设计目标:
/// * 输出稳定的 `[Tag]` 前缀,便于在 Logcat 里 grep 过滤
/// * 提供 [info] / [warn] / [error] 三档,匹配 `dart:developer` 的日志级别
/// * 支持任意 [Object] 作为 message,内部统一 toString
/// * **敏感字段自动脱敏** —— 形如 `sk-xxx...` 的 API key 在落日志前会变成 `sk-****1234`
///
/// 用法:
/// ```dart
/// Log.info('OpenAI', 'POST $url model=$model');
/// Log.warn('OpenAI', 'retry $attempt/$max', extra: {'delay': delay});
/// Log.error('OpenAI', 'request failed', error: e);
/// ```
///
/// 在 Logcat 中过滤: `grep "OpenAI"` 或 `grep "ConversationService"`。
class Log {
  Log._();

  /// redact 的 key 长度下限 —— 短于此长度的字符串不算 api key,不脱敏。
  static const int _redactMinLength = 12;

  /// 匹配 OpenAI / 兼容端常见的 `sk-...` 形式 key。
  static final _keyPattern = RegExp(r'sk-[A-Za-z0-9_\-]{8,}');

  static void info(String tag, String message, {Object? extra}) {
    final m = _redact(message);
    developer.log(m, name: tag, level: 800);
    if (extra != null) {
      developer.log('extra=${_redact(extra.toString())}', name: tag, level: 800);
    }
  }

  static void warn(String tag, String message, {Object? extra}) {
    final m = _redact(message);
    developer.log(m, name: tag, level: 900);
    if (extra != null) {
      developer.log('extra=${_redact(extra.toString())}', name: tag, level: 900);
    }
  }

  static void error(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Object? extra,
  }) {
    final m = _redact(message);
    developer.log(
      m,
      name: tag,
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
    if (extra != null) {
      developer.log('extra=${_redact(extra.toString())}', name: tag, level: 1000);
    }
  }

  /// 把字符串中所有 `sk-...` 形式的 key 脱敏为 `sk-****1234`。
  static String _redact(String s) {
    if (s.length < _redactMinLength) return s;
    return s.replaceAllMapped(_keyPattern, (m) {
      final full = m.group(0)!;
      if (full.length < 8) return full;
      return '${full.substring(0, 3)}****${full.substring(full.length - 4)}';
    });
  }

  /// 把一个 [Exception] / 任意错误对象归类为可读类型,便于用户自助排查。
  ///
  /// 返回值是中文化的简短标签,例如 `网络异常`、`鉴权失败`。
  static String classifyError(Object e) {
    final s = e.toString();
    if (s.contains('SocketException') ||
        s.contains('ConnectionTimeout') ||
        s.contains('Connection refused') ||
        s.contains('Failed host lookup')) {
      return '网络异常';
    }
    if (s.contains('Unauthorized') || s.contains('401')) {
      return '鉴权失败 (API Key 无效或过期)';
    }
    if (s.contains('Forbidden') || s.contains('403')) {
      return '权限不足 (可能被服务端拒绝)';
    }
    if (s.contains('TooManyRequests') || s.contains('429')) {
      return '请求过于频繁 (已自动重试)';
    }
    if (s.contains('FormatException') || s.contains('JSON')) {
      return '响应解析失败';
    }
    if (s.contains('CancelToken') || s.contains('user_cancelled')) {
      return '用户取消';
    }
    return '未知错误';
  }
}