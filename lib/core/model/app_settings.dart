/// 应用设置数据模型。
///
/// 持久化到 `wiki/context-settings.md`，采用 YAML-like Markdown 格式：
/// ```markdown
/// ## ⚙️ 上下文管理
/// - 策略：truncate
/// - 最大条数：20
/// ```
///
/// 所有可变字段都通过 [copyWith] 生成修改副本，
/// 由 [ContextSettingsParser] 解析后缓存到 [SettingsController] 内存。
library;

/// 上下文策略枚举
enum ContextStrategy {
  /// 仅截断：超出上限时直接丢弃旧消息
  truncate,

  /// 自动压缩：超出上限时调用 LLM 生成滚动摘要
  compress,

  /// 不限制：不做任何截断
  nolimit;

  /// 序列化为 Markdown 中的字符串
  String toMarkdown() {
    switch (this) {
      case ContextStrategy.truncate:
        return 'truncate';
      case ContextStrategy.compress:
        return 'compress';
      case ContextStrategy.nolimit:
        return 'nolimit';
    }
  }

  /// 从 Markdown 字符串反序列化（未知值回退默认）
  static ContextStrategy fromMarkdown(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'compress':
        return ContextStrategy.compress;
      case 'nolimit':
        return ContextStrategy.nolimit;
      case 'truncate':
      default:
        return ContextStrategy.truncate;
    }
  }
}

/// 上下文设置（最大条数、压缩长度、策略）
class ContextSettings {
  const ContextSettings({
    this.strategy = ContextStrategy.truncate,
    this.maxMessages = 20,
    this.summaryMaxChars = 300,
  });

  /// 可选的最大条数（强制使用最接近的预设）
  static const List<int> allowedMaxMessages = [10, 20, 40, 60, 100];

  /// 可选的摘要长度
  static const List<int> allowedSummaryChars = [200, 300, 500];

  final ContextStrategy strategy;
  final int maxMessages;
  final int summaryMaxChars;

  ContextSettings copyWith({
    ContextStrategy? strategy,
    int? maxMessages,
    int? summaryMaxChars,
  }) {
    return ContextSettings(
      strategy: strategy ?? this.strategy,
      maxMessages: _nearest(maxMessages ?? this.maxMessages, allowedMaxMessages),
      summaryMaxChars: _nearest(
        summaryMaxChars ?? this.summaryMaxChars,
        allowedSummaryChars,
      ),
    );
  }

  /// 取最接近预设值的整数（用于校验非法值）
  static int _nearest(int value, List<int> presets) {
    var best = presets.first;
    var bestDelta = (value - best).abs();
    for (final p in presets) {
      final d = (value - p).abs();
      if (d < bestDelta) {
        best = p;
        bestDelta = d;
      }
    }
    return best;
  }
}

/// 记忆注入设置
class MemorySettings {
  const MemorySettings({
    this.injectionEnabled = true,
    this.profileEnabled = true,
    this.indexEnabled = true,
    this.shortTermEnabled = true,
    this.todosEnabled = true,
    this.shortTermDays = 7,
    this.profileBudget = 800,
    this.indexBudget = 500,
    this.shortTermBudget = 600,
    this.todosBudget = 400,
  });

  /// 短期记忆时间窗可选值
  static const List<int> allowedShortTermDays = [3, 7, 14, 30];

  final bool injectionEnabled;
  final bool profileEnabled;
  final bool indexEnabled;
  final bool shortTermEnabled;
  final bool todosEnabled;
  final int shortTermDays;
  final int profileBudget;
  final int indexBudget;
  final int shortTermBudget;
  final int todosBudget;

  MemorySettings copyWith({
    bool? injectionEnabled,
    bool? profileEnabled,
    bool? indexEnabled,
    bool? shortTermEnabled,
    bool? todosEnabled,
    int? shortTermDays,
    int? profileBudget,
    int? indexBudget,
    int? shortTermBudget,
    int? todosBudget,
  }) {
    return MemorySettings(
      injectionEnabled: injectionEnabled ?? this.injectionEnabled,
      profileEnabled: profileEnabled ?? this.profileEnabled,
      indexEnabled: indexEnabled ?? this.indexEnabled,
      shortTermEnabled: shortTermEnabled ?? this.shortTermEnabled,
      todosEnabled: todosEnabled ?? this.todosEnabled,
      shortTermDays: ContextSettings._nearest(
        shortTermDays ?? this.shortTermDays,
        allowedShortTermDays,
      ),
      profileBudget: _clamp(profileBudget ?? this.profileBudget, 100, 5000),
      indexBudget: _clamp(indexBudget ?? this.indexBudget, 100, 5000),
      shortTermBudget: _clamp(shortTermBudget ?? this.shortTermBudget, 100, 5000),
      todosBudget: _clamp(todosBudget ?? this.todosBudget, 100, 5000),
    );
  }

  static int _clamp(int v, int min, int max) =>
      v < min ? min : (v > max ? max : v);
}

/// 功能开关设置
class FeatureSettings {
  const FeatureSettings({
    this.autoIngest = false,
    this.autoConflictCheck = true,
    this.autoLint = false,
    this.autoBackup = false,
    this.autoCleanRaw = false,
  });

  final bool autoIngest;
  final bool autoConflictCheck;
  final bool autoLint;
  final bool autoBackup;
  final bool autoCleanRaw;

  FeatureSettings copyWith({
    bool? autoIngest,
    bool? autoConflictCheck,
    bool? autoLint,
    bool? autoBackup,
    bool? autoCleanRaw,
  }) {
    return FeatureSettings(
      autoIngest: autoIngest ?? this.autoIngest,
      autoConflictCheck: autoConflictCheck ?? this.autoConflictCheck,
      autoLint: autoLint ?? this.autoLint,
      autoBackup: autoBackup ?? this.autoBackup,
      autoCleanRaw: autoCleanRaw ?? this.autoCleanRaw,
    );
  }
}

/// Token 阈值设置
class TokenSettings {
  const TokenSettings({
    this.chatTokenThreshold = 4096,
    this.ingestTokenThreshold = 8192,
  });

  final int chatTokenThreshold;
  final int ingestTokenThreshold;

  TokenSettings copyWith({
    int? chatTokenThreshold,
    int? ingestTokenThreshold,
  }) {
    return TokenSettings(
      chatTokenThreshold: chatTokenThreshold ?? this.chatTokenThreshold,
      ingestTokenThreshold: ingestTokenThreshold ?? this.ingestTokenThreshold,
    );
  }
}

/// 累计统计（代码自动累加，用户不可手动修改）
class StatsSettings {
  const StatsSettings({
    this.totalInputTokens = 0,
    this.totalOutputTokens = 0,
  });

  final int totalInputTokens;
  final int totalOutputTokens;

  StatsSettings copyWith({int? totalInputTokens, int? totalOutputTokens}) {
    return StatsSettings(
      totalInputTokens: totalInputTokens ?? this.totalInputTokens,
      totalOutputTokens: totalOutputTokens ?? this.totalOutputTokens,
    );
  }

  StatsSettings addUsage({required int input, required int output}) {
    return StatsSettings(
      totalInputTokens: totalInputTokens + input,
      totalOutputTokens: totalOutputTokens + output,
    );
  }
}

/// 应用设置聚合根
///
/// 顶层模型，解析 `wiki/context-settings.md` 后得到的完整设置。
/// 包含 5 个子区块：上下文 / 记忆 / 功能 / Token / 统计。
class AppSettings {
  const AppSettings({
    this.version = 1,
    this.context = const ContextSettings(),
    this.memory = const MemorySettings(),
    this.features = const FeatureSettings(),
    this.tokens = const TokenSettings(),
    this.stats = const StatsSettings(),
  });

  /// 当前 schema 版本（用于未来字段迁移）
  final int version;
  final ContextSettings context;
  final MemorySettings memory;
  final FeatureSettings features;
  final TokenSettings tokens;
  final StatsSettings stats;

  AppSettings copyWith({
    int? version,
    ContextSettings? context,
    MemorySettings? memory,
    FeatureSettings? features,
    TokenSettings? tokens,
    StatsSettings? stats,
  }) {
    return AppSettings(
      version: version ?? this.version,
      context: context ?? this.context,
      memory: memory ?? this.memory,
      features: features ?? this.features,
      tokens: tokens ?? this.tokens,
      stats: stats ?? this.stats,
    );
  }

  // ── JSONL 序列化 ─────────────────────────────────────────────────────

  /// 序列化为 JSON Map（用于 app_settings.jsonl）
  Map<String, dynamic> toJsonl() => {
        'version': version,
        'context': {
          'strategy': context.strategy.name,
          'maxMessages': context.maxMessages,
          'summaryMaxChars': context.summaryMaxChars,
        },
        'memory': {
          'injectionEnabled': memory.injectionEnabled,
          'profileEnabled': memory.profileEnabled,
          'indexEnabled': memory.indexEnabled,
          'shortTermEnabled': memory.shortTermEnabled,
          'todosEnabled': memory.todosEnabled,
          'shortTermDays': memory.shortTermDays,
          'profileBudget': memory.profileBudget,
          'indexBudget': memory.indexBudget,
          'shortTermBudget': memory.shortTermBudget,
          'todosBudget': memory.todosBudget,
        },
        'features': {
          'autoIngest': features.autoIngest,
          'autoConflictCheck': features.autoConflictCheck,
          'autoLint': features.autoLint,
          'autoBackup': features.autoBackup,
          'autoCleanRaw': features.autoCleanRaw,
        },
        'tokens': {
          'chatTokenThreshold': tokens.chatTokenThreshold,
          'ingestTokenThreshold': tokens.ingestTokenThreshold,
        },
        'stats': {
          'totalInputTokens': stats.totalInputTokens,
          'totalOutputTokens': stats.totalOutputTokens,
        },
      };

  /// 从 JSON Map 反序列化
  factory AppSettings.fromJsonl(Map<String, dynamic> json) {
    final ctx = json['context'] as Map<String, dynamic>? ?? {};
    final mem = json['memory'] as Map<String, dynamic>? ?? {};
    final feat = json['features'] as Map<String, dynamic>? ?? {};
    final tok = json['tokens'] as Map<String, dynamic>? ?? {};
    final st = json['stats'] as Map<String, dynamic>? ?? {};

    return AppSettings(
      version: json['version'] as int? ?? 1,
      context: ContextSettings(
        strategy: ContextStrategy.values.firstWhere(
          (s) => s.name == (ctx['strategy'] as String? ?? 'truncate'),
          orElse: () => ContextStrategy.truncate,
        ),
        maxMessages: ctx['maxMessages'] as int? ?? 20,
        summaryMaxChars: ctx['summaryMaxChars'] as int? ?? 300,
      ),
      memory: MemorySettings(
        injectionEnabled: mem['injectionEnabled'] as bool? ?? true,
        profileEnabled: mem['profileEnabled'] as bool? ?? true,
        indexEnabled: mem['indexEnabled'] as bool? ?? true,
        shortTermEnabled: mem['shortTermEnabled'] as bool? ?? true,
        todosEnabled: mem['todosEnabled'] as bool? ?? true,
        shortTermDays: mem['shortTermDays'] as int? ?? 7,
        profileBudget: mem['profileBudget'] as int? ?? 800,
        indexBudget: mem['indexBudget'] as int? ?? 500,
        shortTermBudget: mem['shortTermBudget'] as int? ?? 600,
        todosBudget: mem['todosBudget'] as int? ?? 400,
      ),
      features: FeatureSettings(
        autoIngest: feat['autoIngest'] as bool? ?? false,
        autoConflictCheck: feat['autoConflictCheck'] as bool? ?? true,
        autoLint: feat['autoLint'] as bool? ?? false,
        autoBackup: feat['autoBackup'] as bool? ?? false,
        autoCleanRaw: feat['autoCleanRaw'] as bool? ?? false,
      ),
      tokens: TokenSettings(
        chatTokenThreshold: tok['chatTokenThreshold'] as int? ?? 4096,
        ingestTokenThreshold: tok['ingestTokenThreshold'] as int? ?? 8192,
      ),
      stats: StatsSettings(
        totalInputTokens: st['totalInputTokens'] as int? ?? 0,
        totalOutputTokens: st['totalOutputTokens'] as int? ?? 0,
      ),
    );
  }
}