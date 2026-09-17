/// 记忆与压缩提示词模板。
///
/// 提供：
/// - 压缩摘要提示词（[compressSystemPrompt] / [buildCompressUserPrompt]）
/// - 记忆注入区块模板（[buildMemoryBlock]）
/// - 短期记忆聚合提示词（[buildShortTermAggregationPrompt]）
library;

/// 压缩摘要的系统提示词。
///
/// 指导 LLM 将多轮对话历史压缩为简洁摘要，要求保留关键事实。
const String compressSystemPrompt =
    '''你是一个会话历史压缩助手。你的任务是将多轮对话历史压缩为简洁的摘要。

## 压缩规则

1. 提取对话的核心主题、关键结论、重要决定
2. 保留具体的数字、日期、名称等可执行信息
3. 忽略对话过程中的试探性讨论和无关内容
4. 摘要语言跟随对话原文（对话为中文则中文输出）
5. 输出格式为 Markdown，结构清晰
6. 摘要长度控制在指定字符数以内（不要超出）
7. 不要在摘要中包含「以上是对话摘要」之类的元说明，直接输出摘要内容本身''';

/// 构建压缩摘要的用户提示词。
///
/// [existingSummary] 已有摘要（若有），用于滚动合并
/// [messagesJson] 待压缩的对话历史 JSON 字符串
/// [maxChars] 摘要目标字符数
String buildCompressUserPrompt({
  required String? existingSummary,
  required String messagesJson,
  required int maxChars,
}) {
  final existing = (existingSummary == null || existingSummary.isEmpty)
      ? '（无）'
      : existingSummary;
  return '''
## 现有摘要（若有）

$existing

## 待压缩对话历史

$messagesJson

## 要求

请基于「现有摘要」和「待压缩对话历史」生成新的合并摘要。
摘要长度不超过 $maxChars 字符。直接输出摘要内容，无需前缀说明。
''';
}

// ═══════════════════════════════════════════════════
//  记忆注入区块
// ═══════════════════════════════════════════════════

/// 构建四源记忆区块（注入到 systemPrompt 头部）。
///
/// [profile] 用户画像内容
/// [index] 知识库索引内容
/// [shortTermList] 近期记忆列表（每个元素为「文件名：摘要」）
/// [shortTermDays] 短期记忆时间窗
/// [todos] 待办内容
String buildMemoryBlock({
  required String profile,
  required String index,
  required List<String> shortTermList,
  required int shortTermDays,
  required String todos,
}) {
  final buf = StringBuffer();
  buf.writeln('# 记忆上下文');
  buf.writeln();
  buf.writeln('> 以下是你的本地记忆信息，仅作参考。不要在回复中直接复述。');
  buf.writeln();

  if (profile.trim().isNotEmpty) {
    buf.writeln('## 用户画像');
    buf.writeln();
    buf.writeln(profile.trim());
    buf.writeln();
  }

  if (index.trim().isNotEmpty) {
    buf.writeln('## 知识库索引');
    buf.writeln();
    buf.writeln(index.trim());
    buf.writeln();
  }

  if (shortTermList.isNotEmpty) {
    buf.writeln('## 近期记忆（近 $shortTermDays 天）');
    buf.writeln();
    for (final entry in shortTermList) {
      buf.writeln(entry);
    }
    buf.writeln();
  }

  if (todos.trim().isNotEmpty) {
    buf.writeln('## 当前待办');
    buf.writeln();
    buf.writeln(todos.trim());
    buf.writeln();
  }

  return buf.toString();
}

// ═══════════════════════════════════════════════════
//  短期记忆聚合（可选 Phase 4+）
// ═══════════════════════════════════════════════════

/// 构建短期记忆聚合提示词。
///
/// 当时间窗内的会话摘要过多时，让 LLM 生成一份综合摘要。
String buildShortTermAggregationPrompt({
  required List<String> sessionSummaries,
  required int maxChars,
}) {
  final joined = sessionSummaries.map((s) => '- $s').join('\n');
  return '''
以下是用户近期的多个会话摘要，请合并为一份连贯的短期记忆摘要，长度不超过 $maxChars 字符。

## 会话摘要列表

$joined

## 要求

- 按时间顺序组织
- 提取跨会话的关键主题和决定
- 保留重要的项目/任务/事实信息
- 不要输出「以上是合并摘要」之类的元说明
- 直接输出合并后的摘要内容
''';
}