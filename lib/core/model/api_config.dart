/// API 配置数据模型。
///
/// 采用不可变设计，通过 [copyWith] 创建修改后的副本。
/// 管理不同 AI 模型的 API 连接配置，支持多配置切换与默认配置标记。
library;

/// API 配置数据模型。
///
/// 不可变对象，使用 [copyWith] 生成修改后的副本。
/// 每个配置对应一个 AI 模型的 API 端点信息和推理参数。
class ApiConfig {
  const ApiConfig({
    this.id,
    required this.configName,
    required this.modelName,
    required this.apiEndpoint,
    required this.apiKey,
    this.temperature = 0.7,
    this.topP = 1.0,
    this.maxTokens = 4096,
    this.maxCompletionTokens = 4096,
    this.thinkingEnabled = false,
    this.isDefault = false,
    this.providerId = 'auto',
  });

  /// 配置 ID（数据库主键，新建时为 null）
  final int? id;

  /// 配置名称（用户自定义，如 "GPT-4o"）
  final String configName;

  /// 模型名称（API 请求中使用的模型标识）
  final String modelName;

  /// API 端点地址
  final String apiEndpoint;

  /// API 密钥
  final String apiKey;

  /// 温度参数（控制生成随机性，0.0 ~ 2.0）
  final double temperature;

  /// Top-P 采样参数（0.0 ~ 1.0）
  final double topP;

  /// 最大生成 token 数
  final int maxTokens;

  /// 最大生成 token 数（MINIMAX 用 max_completion_tokens）
  final int maxCompletionTokens;

  /// 是否启用 MINIMAX thinking 模式（自适应思考）
  final bool thinkingEnabled;

  /// 是否为默认配置
  final bool isDefault;

  /// Provider 标识（'auto' / 'minimax' / 'openai' / 自定义）
  final String providerId;

  /// 创建当前配置的修改副本。
  ///
  /// 未指定的参数保持原值不变。
  ApiConfig copyWith({
    int? id,
    String? configName,
    String? modelName,
    String? apiEndpoint,
    String? apiKey,
    double? temperature,
    double? topP,
    int? maxTokens,
    int? maxCompletionTokens,
    bool? thinkingEnabled,
    bool? isDefault,
    String? providerId,
  }) {
    return ApiConfig(
      id: id ?? this.id,
      configName: configName ?? this.configName,
      modelName: modelName ?? this.modelName,
      apiEndpoint: apiEndpoint ?? this.apiEndpoint,
      apiKey: apiKey ?? this.apiKey,
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      maxTokens: maxTokens ?? this.maxTokens,
      maxCompletionTokens: maxCompletionTokens ?? this.maxCompletionTokens,
      thinkingEnabled: thinkingEnabled ?? this.thinkingEnabled,
      isDefault: isDefault ?? this.isDefault,
      providerId: providerId ?? this.providerId,
    );
  }

  /// 返回脱敏后的 API Key（仅展示前 3 位和后 4 位）
  String get redactedApiKey {
    if (apiKey.length <= 8) return '****';
    return '${apiKey.substring(0, 3)}****${apiKey.substring(apiKey.length - 4)}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApiConfig &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          configName == other.configName &&
          modelName == other.modelName &&
          apiEndpoint == other.apiEndpoint &&
          apiKey == other.apiKey &&
          temperature == other.temperature &&
          topP == other.topP &&
          maxTokens == other.maxTokens &&
          maxCompletionTokens == other.maxCompletionTokens &&
          thinkingEnabled == other.thinkingEnabled &&
          isDefault == other.isDefault &&
          providerId == other.providerId;

  @override
  int get hashCode => Object.hash(
        id,
        configName,
        modelName,
        apiEndpoint,
        apiKey,
        temperature,
        topP,
        maxTokens,
        maxCompletionTokens,
        thinkingEnabled,
        isDefault,
        providerId,
      );

  @override
  String toString() =>
      'ApiConfig(id: $id, configName: $configName, modelName: $modelName, '
      'provider: $providerId, endpoint: $apiEndpoint, isDefault: $isDefault, '
      'maxCompletionTokens: $maxCompletionTokens, thinkingEnabled: $thinkingEnabled)';
}
