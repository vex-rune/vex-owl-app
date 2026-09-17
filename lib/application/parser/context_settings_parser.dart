/// context-settings.md 解析器。
///
/// 文件结构：
/// ```markdown
/// ---
/// version: 1
/// ---
/// # 应用设置
///
/// ## ⚙️ 上下文管理
/// - 策略：truncate
/// - 最大条数：20
/// - 摘要长度：300
///
/// ## ⚙️ 记忆注入
/// - 总开关：on
/// - 用户画像：on
/// ...
/// ```
///
/// 负责：
/// - Markdown 字符串 → [AppSettings] 模型（[parse]）
/// - [AppSettings] 模型 → Markdown 字符串（[serialize]）
/// - 解析失败时回退默认值（不抛异常）
library;

import '../../core/model/app_settings.dart';
import 'markdown_writer.dart';

class ContextSettingsParser {
  /// 段落标题常量
  static const _sectionContext = '⚙️ 上下文管理';
  static const _sectionMemory = '⚙️ 记忆注入';
  static const _sectionTokenBudget = '⚙️ Token 预算';
  static const _sectionFeatures = '⚙️ 功能开关';
  static const _sectionStats = '⚙️ 统计';

  /// Markdown 字符串 → [AppSettings]，失败时返回默认值
  static AppSettings parse(String content) {
    final (frontMatter, body) = MarkdownParser.parseFrontMatter(content);
    final sections = MarkdownParser.parseSections(body);

    ContextSettings context = const ContextSettings();
    MemorySettings memory = const MemorySettings();
    FeatureSettings features = const FeatureSettings();
    TokenSettings tokens = const TokenSettings();
    StatsSettings stats = const StatsSettings();

    for (final s in sections) {
      switch (s.title) {
        case _sectionContext:
          context = _parseContext(s);
          break;
        case _sectionMemory:
          memory = _parseMemory(s);
          break;
        case _sectionTokenBudget:
          // Token 预算在 memory 里读
          memory = _parseMemoryWithTokenBudget(memory, s);
          break;
        case _sectionFeatures:
          features = _parseFeatures(s);
          break;
        case _sectionStats:
          stats = _parseStats(s);
          break;
      }
    }

    return AppSettings(
      version: frontMatter.version,
      context: context,
      memory: memory,
      features: features,
      tokens: tokens,
      stats: stats,
    );
  }

  /// [AppSettings] → Markdown 字符串
  static String serialize(AppSettings s) {
    final frontMatter = FrontMatter(version: s.version);

    final sections = <MarkdownSection>[
      MarkdownSection(_sectionContext)
        ..set('策略', s.context.strategy.toMarkdown())
        ..set('最大条数', '${s.context.maxMessages}')
        ..set('摘要长度', '${s.context.summaryMaxChars}'),
      MarkdownSection(_sectionMemory)
        ..set('总开关', _bool(s.memory.injectionEnabled))
        ..set('用户画像', _bool(s.memory.profileEnabled))
        ..set('知识库索引', _bool(s.memory.indexEnabled))
        ..set('近期记忆', _bool(s.memory.shortTermEnabled))
        ..set('用户待办', _bool(s.memory.todosEnabled))
        ..set('短期记忆窗口（天）', '${s.memory.shortTermDays}'),
      MarkdownSection(_sectionTokenBudget)
        ..set('用户画像', '${s.memory.profileBudget}')
        ..set('知识库索引', '${s.memory.indexBudget}')
        ..set('近期记忆', '${s.memory.shortTermBudget}')
        ..set('用户待办', '${s.memory.todosBudget}')
        ..set('对话告警阈值', '${s.tokens.chatTokenThreshold}')
        ..set('Ingest 告警阈值', '${s.tokens.ingestTokenThreshold}'),
      MarkdownSection(_sectionFeatures)
        ..set('自动 Ingest', _bool(s.features.autoIngest))
        ..set('冲突校验', _bool(s.features.autoConflictCheck))
        ..set('自动 Lint', _bool(s.features.autoLint))
        ..set('自动备份', _bool(s.features.autoBackup))
        ..set('自动清理 Raw', _bool(s.features.autoCleanRaw)),
      MarkdownSection(_sectionStats)
        ..set('累计输入 Token', '${s.stats.totalInputTokens}')
        ..set('累计输出 Token', '${s.stats.totalOutputTokens}'),
    ];

    return MarkdownWriter.serialize(
      frontMatter: frontMatter,
      sections: sections,
      title: '应用设置',
    );
  }

  /// 文件首次创建时的默认内容
  static String defaultContent() => serialize(const AppSettings());

  // ── 内部解析辅助 ──

  static ContextSettings _parseContext(MarkdownSection s) {
    return ContextSettings(
      strategy: ContextStrategy.fromMarkdown(s.get('策略')),
      maxMessages: _toInt(s.get('最大条数'), 20),
      summaryMaxChars: _toInt(s.get('摘要长度'), 300),
    );
  }

  static MemorySettings _parseMemory(MarkdownSection s) {
    return MemorySettings(
      injectionEnabled: _toBool(s.get('总开关')),
      profileEnabled: _toBool(s.get('用户画像')),
      indexEnabled: _toBool(s.get('知识库索引')),
      shortTermEnabled: _toBool(s.get('近期记忆')),
      todosEnabled: _toBool(s.get('用户待办')),
      shortTermDays: _toInt(s.get('短期记忆窗口（天）'), 7),
    );
  }

  static MemorySettings _parseMemoryWithTokenBudget(
    MemorySettings base,
    MarkdownSection s,
  ) {
    return base.copyWith(
      profileBudget: _toInt(s.get('用户画像'), base.profileBudget),
      indexBudget: _toInt(s.get('知识库索引'), base.indexBudget),
      shortTermBudget: _toInt(s.get('近期记忆'), base.shortTermBudget),
      todosBudget: _toInt(s.get('用户待办'), base.todosBudget),
    );
  }

  static FeatureSettings _parseFeatures(MarkdownSection s) {
    return FeatureSettings(
      autoIngest: _toBool(s.get('自动 Ingest')),
      autoConflictCheck: _toBool(s.get('冲突校验')),
      autoLint: _toBool(s.get('自动 Lint')),
      autoBackup: _toBool(s.get('自动备份')),
      autoCleanRaw: _toBool(s.get('自动清理 Raw')),
    );
  }

  static StatsSettings _parseStats(MarkdownSection s) {
    return StatsSettings(
      totalInputTokens: _toInt(s.get('累计输入 Token'), 0),
      totalOutputTokens: _toInt(s.get('累计输出 Token'), 0),
    );
  }

  static bool _toBool(String? value) {
    final v = value?.trim().toLowerCase();
    return v == 'on' || v == 'true' || v == 'yes' || v == '1';
  }

  static String _bool(bool v) => v ? 'on' : 'off';

  static int _toInt(String? value, int fallback) {
    return int.tryParse(value?.trim() ?? '') ?? fallback;
  }
}