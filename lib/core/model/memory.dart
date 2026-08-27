/// WikeLLM 记忆模型(对应 docs/WikeLLM记忆.md §3)。
///
/// 记忆以 Markdown 文件形式落盘:
/// - `profile.md`         (profile)
/// - `long_term.md`       (long_term)
/// - `short_term.md`      (short_term)
/// - `history/yyyymm/yyyymmdd.md`  (history · 每会话一行)
enum MemoryScope {
  profile,
  shortTerm,
  longTerm,
  history;

  String get fileName {
    switch (this) {
      case MemoryScope.profile:
        return 'profile.md';
      case MemoryScope.shortTerm:
        return 'short_term.md';
      case MemoryScope.longTerm:
        return 'long_term.md';
      case MemoryScope.history:
        // history 是日期化的多文件,这里返回占位;实际路径在 MemoryRepository 拼装
        return 'history';
    }
  }
}

/// 跨域查询返回结果。
class MemoryQueryResult {
  const MemoryQueryResult({
    required this.scope,
    required this.lines,
  });
  final MemoryScope scope;
  final List<String> lines;
}