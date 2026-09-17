import '../../core/core.dart';
import 'llm_provider.dart';
import 'providers/deepseek_provider.dart';
import 'providers/minimax_provider.dart';
import 'providers/mimo_provider.dart';
import 'providers/openai_provider.dart';

/// LLM Provider 注册中心
///
/// 根据 ApiConfig 自动匹配最合适的 Provider 实现。
/// 后续添加新供应商时只需：1) 实现 LlmProvider 2) 加入 _providers 列表
///
/// 解析顺序：
/// 1. 显式 providerId（非 'auto'）→ 查找匹配的 Provider
/// 2. 各 Provider.supports() 判断 endpoint / modelName 特征
/// 3. fallback 到最后一个 Provider（OpenAI 兼容）
class LlmProviderRegistry {
  static final LlmProviderRegistry instance = LlmProviderRegistry._();
  LlmProviderRegistry._() {
    _providers.addAll([
      MinimaxProvider(),
      DeepSeekProvider(),
      MimoProvider(),
      OpenAiProvider(),
    ]);
  }

  final List<LlmProvider> _providers = [];

  /// 所有可用 Provider（用于 UI 选择器）
  List<LlmProvider> get all => List.unmodifiable(_providers);

  /// 根据 ApiConfig 选择最匹配的 Provider
  ///
  /// 解析顺序：
  /// 1. 显式 providerId（非 'auto'）→ 查找匹配
  /// 2. 第一个 supports()==true 的 Provider
  /// 3. fallback 到最后一个（OpenAI 兼容）
  LlmProvider resolve(ApiConfig config) {
    if (config.providerId.isNotEmpty && config.providerId != 'auto') {
      final p = byId(config.providerId);
      if (p != null) return p;
    }
    for (final p in _providers) {
      if (p.supports(config)) return p;
    }
    return _providers.last; // OpenAI 兼容 fallback
  }

  /// 通过 id 获取 Provider
  LlmProvider? byId(String id) {
    for (final p in _providers) {
      if (p.id == id) return p;
    }
    return null;
  }
}

/// 为指定 Provider 创建默认 ApiConfig（应用 schema 的默认值）
///
/// [providerId] 若找不到对应 Provider，会回退到一个 OpenAI 兼容默认值。
ApiConfig defaultConfigFor(
  String providerId, {
  required String apiKey,
  String configName = '',
}) {
  final registry = LlmProviderRegistry.instance;
  final provider = registry.byId(providerId);
  if (provider == null) {
    return ApiConfig(
      configName: configName.isEmpty ? 'New Config' : configName,
      modelName: 'gpt-4o',
      apiEndpoint: 'https://api.openai.com/v1',
      apiKey: apiKey,
      providerId: providerId,
    );
  }
  final schema = provider.configSchema;
  return ApiConfig(
    configName: configName.isEmpty ? '${provider.displayName} 配置' : configName,
    modelName: schema.modelDefault,
    apiEndpoint: schema.endpointDefault,
    apiKey: apiKey,
    providerId: providerId,
  );
}
