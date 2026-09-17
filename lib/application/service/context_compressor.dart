/// 上下文压缩服务（v5）。
///
/// 职责：
/// - 当会话消息数超过配置上限时，根据 `ContextStrategy` 执行压缩
/// - 截断策略：纯内存裁剪，不调用 LLM
/// - 压缩策略：调用 LLM 生成滚动摘要，写入 `wiki/sessions/{sessionId}.md`
///   （v5 新规：文件名为 sessionId，不再用 {date}-{name}，便于 wikilink 引用）
/// - 失败降级：异常时回退到截断，不阻塞主对话流程
///
/// 设计为 fire-and-forget，调用方无需 await。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/core.dart';
import '../../core/model/wiki_front_matter.dart';
import 'session_file_service.dart';

/// 压缩结果枚举
enum CompressResult {
  /// 无需压缩（消息数未超限）
  notNeeded,

  /// 截断完成（无 LLM 调用）
  truncated,

  /// 压缩完成并写入文件
  compressed,

  /// 压缩失败，已降级为截断
  compressedFailedFallbackToTruncate,
}

/// 压缩选项
class CompressOptions {
  const CompressOptions({
    required this.strategy,
    required this.maxMessages,
    required this.summaryMaxChars,
  });

  final ContextStrategy strategy;
  final int maxMessages;
  final int summaryMaxChars;

  CompressOptions fromSettings(AppSettings s) => CompressOptions(
        strategy: s.context.strategy,
        maxMessages: s.context.maxMessages,
        summaryMaxChars: s.context.summaryMaxChars,
      );
}

/// 压缩依赖（注入 LLM 调用能力 + 设置源）
abstract class CompressorDependencies {
  /// 调用 LLM（非流式）生成摘要。失败时抛出异常。
  Future<String> callLlm({
    required String systemPrompt,
    required String userPrompt,
    required ApiConfig config,
  });

  /// 获取当前默认 API 配置（压缩用的模型）
  ApiConfig? get defaultConfig;

  /// 获取当前 AppSettings（含压缩策略配置）
  AppSettings get settings;

  /// Wiki 仓库（用于写 sessions/*.md）
  SessionFileService get sessionFileService;
}

/// 上下文压缩服务
class ContextCompressor {
  ContextCompressor(this._deps);

  final CompressorDependencies _deps;

  /// 检查是否需要压缩
  ///
  /// [messageCount] 当前内存中的消息总数（含用户+助手）
  bool needsCompress(int messageCount, CompressOptions options) {
    if (options.strategy == ContextStrategy.nolimit) return false;
    return messageCount > options.maxMessages;
  }

  /// 执行压缩（异步，调用方可 fire-and-forget）
  ///
  /// 返回压缩结果，可用于 UI 提示。
  Future<CompressResult> compressIfNeeded({
    required Session session,
    required List<Message> messages,
  }) async {
    final settings = _deps.settings;
    final options = CompressOptions(
      strategy: settings.context.strategy,
      maxMessages: settings.context.maxMessages,
      summaryMaxChars: settings.context.summaryMaxChars,
    );

    if (!needsCompress(messages.length, options)) {
      return CompressResult.notNeeded;
    }

    final overflow = messages.length - options.maxMessages;
    final oldMessages = messages.sublist(0, overflow);
    log.info(
      '🗜️ 触发上下文压缩：策略=${options.strategy.name} '
      '当前=${messages.length} 上限=${options.maxMessages} '
      '待裁剪=$overflow',
    );

    switch (options.strategy) {
      case ContextStrategy.truncate:
        return CompressResult.truncated;
      case ContextStrategy.nolimit:
        return CompressResult.notNeeded;
      case ContextStrategy.compress:
        return _compressWithLlm(
          session: session,
          oldMessages: oldMessages,
          summaryMaxChars: options.summaryMaxChars,
        );
    }
  }

  /// LLM 压缩 + 写入文件
  Future<CompressResult> _compressWithLlm({
    required Session session,
    required List<Message> oldMessages,
    required int summaryMaxChars,
  }) async {
    final cfg = _deps.defaultConfig;
    if (cfg == null) {
      log.info(
        '⚠️ 压缩失败：无默认 API 配置，降级为截断',
      );
      return CompressResult.compressedFailedFallbackToTruncate;
    }

    try {
      final messagesJson = jsonEncode(
        oldMessages.map((m) => m.toJson()).toList(),
      );

      final userPrompt = buildCompressUserPrompt(
        existingSummary: null, // Phase 1.5 暂不读旧摘要
        messagesJson: messagesJson,
        maxChars: summaryMaxChars,
      );

      final summary = await _deps.callLlm(
        systemPrompt: compressSystemPrompt,
        userPrompt: userPrompt,
        config: cfg,
      );

      // 写入 wiki/sessions/{date}-{name}.md
      await _writeSummary(session, summary);
      log.info(
        '✅ 压缩完成：${oldMessages.length} 条消息 → ${summary.length} 字摘要',
      );
      return CompressResult.compressed;
    } catch (e, st) {
      log.error('❌ 压缩失败：$e\n$st');
      return CompressResult.compressedFailedFallbackToTruncate;
    }
  }

  /// 将压缩摘要写入 wiki/sessions/{sessionId}.md（v5）
  ///
  /// v5 规范：文件名 = sessionId（稳定），便于其他文档 `[[sessionId]]` 引用。
  /// 重命名会话时不影响文件名，只改 front-matter 的 title。
  Future<void> _writeSummary(Session session, String summary) async {
    final dir = await _deps.sessionFileService.sessionsDir;
    final file = File(p.join(dir, '${session.id}.md'));

    final fm = WikiFrontMatter(
      title: session.name,
      description: '会话摘要 · ${session.name}',
      weight: 5,
      extras: {
        'session_id': session.id,
        'archived': false,
        'message_count': session.messageCount,
      },
    );

    final buf = StringBuffer();
    buf.write(fm.serialize());
    buf.writeln('# ${session.name}');
    buf.writeln();
    buf.writeln('## 摘要');
    buf.writeln();
    buf.writeln(summary.trim());
    buf.writeln();
    buf.writeln('## 关联');
    buf.writeln();
    buf.writeln('- [[profile]]');
    buf.writeln();
    buf.writeln('> 来源：会话历史压缩 | 生成时间：${DateTime.now().toUtc().toIso8601String()}');

    await file.writeAsString(buf.toString(), flush: true);
  }
}

// ═══════════════════════════════════════════════════
//  工具：获取默认配置（在没有依赖注入时的临时方案）
// ═══════════════════════════════════════════════════

/// 默认 CompressorDependencies 实现占位。
///
/// 真正的实现需要 ChatController 注入（持有 SettingsController 和 LLM Provider）。
/// Phase 3 后续步骤会创建。
class DefaultCompressorDependencies implements CompressorDependencies {
  DefaultCompressorDependencies({
    required this.settings,
    required this.defaultConfig,
    required this.sessionFileService,
    required this.llmCaller,
  });

  @override
  final AppSettings settings;
  @override
  final ApiConfig? defaultConfig;
  @override
  final SessionFileService sessionFileService;

  /// LLM 调用闭包（由 ChatController 注入）
  final Future<String> Function({
    required String systemPrompt,
    required String userPrompt,
    required ApiConfig config,
  }) llmCaller;

  @override
  Future<String> callLlm({
    required String systemPrompt,
    required String userPrompt,
    required ApiConfig config,
  }) {
    return llmCaller(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      config: config,
    );
  }
}