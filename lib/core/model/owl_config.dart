/// 应用配置。
///
/// 字段命名与 docs §3.1 / §3.2 对齐。
/// 默认值由 ConfigRepository 初始化时注入。
class OwlConfig {
  const OwlConfig({
    required this.apiKey,
    required this.baseUrl,
    required this.model,
    required this.maxRounds,
    required this.theme,
    required this.memoryCompression,
    this.bochaApiKey = '',
    this.temperature = 0.7,
  });

  /// OpenAI 兼容端点的 API Key。
  ///
  /// **敏感字段**:不应进入日志 / 不应在 UI 明文展示;
  /// 序列化到 [toJson] 时已自动脱敏。
  final String apiKey;

  /// OpenAI 兼容端点 baseUrl。
  /// 默认 `https://api.minimax.chat/v1`。
  final String baseUrl;

  /// 模型名。默认 `minimax-M3`。
  final String model;

  /// 工具调用最大跳数(默认 5)。
  final int maxRounds;

  /// UI 主题:`light` / `dark` / `system`。
  final String theme;

  /// 记忆压缩策略:`off` / `recent_n` / `summarize`(v1.x 仅占位)。
  final String memoryCompression;

  /// 博查 Web Search API Key(用于联网搜索 tool)。
  ///
  /// **可选**:用户未配置时 [BochaSearchTool] 返回"请先配置 API Key",
  /// 而不是抛异常。留空串 = 该功能关闭。
  final String bochaApiKey;

  /// 采样温度(0.0 - 2.0),默认 0.7。
  ///
  /// 供 [ChatOpenAI.defaultOptions] 与 Agent 构造时使用,
  /// 保证用户在 Settings 修改后立即生效。
  final double temperature;

  OwlConfig copyWith({
    String? apiKey,
    String? baseUrl,
    String? model,
    int? maxRounds,
    String? theme,
    String? memoryCompression,
    String? bochaApiKey,
    double? temperature,
  }) =>
      OwlConfig(
        apiKey: apiKey ?? this.apiKey,
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
        maxRounds: maxRounds ?? this.maxRounds,
        theme: theme ?? this.theme,
        memoryCompression: memoryCompression ?? this.memoryCompression,
        bochaApiKey: bochaApiKey ?? this.bochaApiKey,
        temperature: temperature ?? this.temperature,
      );

  /// 序列化:**apiKey / bochaApiKey 字段已脱敏**,可安全写入 settings_page 调试 / 日志。
  Map<String, dynamic> toJson() => <String, dynamic>{
        'apiKey': _redactKey(apiKey),
        'baseUrl': baseUrl,
        'model': model,
        'maxRounds': maxRounds,
        'theme': theme,
        'memoryCompression': memoryCompression,
        'bochaApiKey': _redactKey(bochaApiKey),
        'temperature': temperature,
      };

  factory OwlConfig.fromJson(Map<String, dynamic> json) => OwlConfig(
        // 检测"已被 [toJson] redact 的历史 apiKey"——
        // 形如 `sk-****1234`,直接当无效,提示用户重输。
        apiKey: _sanitizeApiKey(json['apiKey'] as String?),
        baseUrl: (json['baseUrl'] as String?) ??
            'https://api.minimax.chat/v1',
        model: (json['model'] as String?) ?? 'minimax-M3',
        maxRounds: (json['maxRounds'] as int?) ?? 5,
        theme: (json['theme'] as String?) ?? 'system',
        memoryCompression: (json['memoryCompression'] as String?) ?? 'off',
        bochaApiKey: _sanitizeApiKey(json['bochaApiKey'] as String?),
        temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
      );

  /// 若 apiKey 形如"被 [toJson] 脱敏过的"(`xxx****xxx`),返回空串,
  /// 让 SettingsPage 走"API Key 与 Base URL 不能为空"提示路径,
  /// 引导用户重新输入(避免升级后一直拿 `sk-****xxxx` 调 API 401)。
  static String _sanitizeApiKey(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    if (raw.contains('****')) return '';
    return raw;
  }

  factory OwlConfig.empty() => OwlConfig(
        apiKey: '????',
        baseUrl: 'https://api.minimax.chat/v1',
        model: 'minimax-M3',
        maxRounds: 5,
        theme: 'system',
        memoryCompression: 'off',
      );

  /// 把 apiKey 脱敏成 `sk-****1234` 形式 —— 只保留首 3 + 末 4 字符。
  static String _redactKey(String key) {
    if (key.length <= 8) return '****';
    return '${key.substring(0, 3)}****${key.substring(key.length - 4)}';
  }

  /// 脱敏后的 apiKey(便于 UI 显示)。
  String get redactedApiKey => _redactKey(apiKey);

  /// 是否已完成有效配置(apiKey 非空且非占位、baseUrl 非空)。
  ///
  /// 用于发送前守卫:未配置时提示用户去设置页,避免空配置发起请求后
  /// 模型静默失败(异常被 QuickAgent 包成 AgentFinish(error),再被
  /// orchestrator 的 serialize 跳过,表现为"发出去没回答")。
  bool get isConfigured =>
      apiKey.trim().isNotEmpty &&
      apiKey != '????' &&
      baseUrl.trim().isNotEmpty;
}