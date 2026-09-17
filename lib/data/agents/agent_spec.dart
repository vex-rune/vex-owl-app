/// Agent 规格抽象层
///
/// 定义了本地的 AgentSpec、ModelRoute、OpenAIProvider 抽象类。
/// 当前为轻量级本地实现，后续可替换为 agentlib 或其他 Agent 框架。

/// AI 模型提供商配置
class ModelProvider {
  const ModelProvider({
    required this.apiKey,
    this.baseUrl = 'https://api.openai.com/v1',
  });

  final String apiKey;
  final String baseUrl;
}

/// 模型路由策略
///
/// 定义了 Agent 使用模型的优先级策略。
class ModelRoute {
  const ModelRoute._({required this.providers, this.preferLocal = false});

  /// 仅使用云端模型
  factory ModelRoute.cloudOnly(List<ModelProvider> providers) {
    return ModelRoute._(providers: providers, preferLocal: false);
  }

  /// 优先使用本地/端侧模型，不可用时 fallback 到云端
  factory ModelRoute.preferOnDevice({
    required List<ModelProvider> onDevice,
    required List<ModelProvider> fallback,
  }) {
    return ModelRoute._(
      providers: [...onDevice, ...fallback],
      preferLocal: true,
    );
  }

  final List<ModelProvider> providers;
  final bool preferLocal;

  /// 获取默认（第一个）提供商
  ModelProvider? get defaultProvider =>
      providers.isNotEmpty ? providers.first : null;
}

/// Agent 规格定义
///
/// 描述一个 Agent 的名称、系统提示词、模型路由和可用工具。
/// 这是创建和配置 Agent 的核心数据类。
class AgentSpec {
  const AgentSpec({
    required this.name,
    this.instructions = '',
    required this.model,
    this.tools = const [],
    this.maxTurns = 10,
  });

  /// Agent 唯一标识名
  final String name;

  /// 系统提示词/指令
  final String instructions;

  /// 模型路由（决定使用哪个 AI 模型）
  final ModelRoute model;

  /// 可用工具列表（预留扩展）
  final List<String> tools;

  /// 最大对话轮次
  final int maxTurns;
}
