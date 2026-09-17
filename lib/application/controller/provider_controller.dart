import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../../data/llm/llm.dart';

/// Provider / Agent 路由控制器（v6.2）
///
/// 主要职责：
/// 1. 暴露 [LlmProviderRegistry] 全部 Provider，便于 Settings UI 按 Provider
///    分组展示所有 Agent。
/// 2. 根据 [ApiConfig] 解析 Provider（仍在 `chatStream / chatComplete` 之前用）
/// 3. 测试连接
/// 4. 提供每个 Provider 暴露的模型预设列表
///
/// 设计取向：每个 `ProviderModelPreset` 就是一个独立的 Agent。
/// 用户无需自己添加 / 删除 Agent，只能编辑 Provider 内置 Agent 的具体参数。
class ProviderController extends ChangeNotifier {
  ProviderController() : _registry = LlmProviderRegistry.instance;

  final LlmProviderRegistry _registry;

  /// 所有可用 Provider
  List<LlmProvider> get providers => _registry.all;

  /// 解析 ApiConfig 对应的 Provider
  LlmProvider resolveProvider(ApiConfig config) => _registry.resolve(config);

  /// 通过 ID 获取 Provider
  LlmProvider? providerById(String id) => _registry.byId(id);

  /// 获取 Provider 的模型预设列表
  List<ProviderModelPreset> presetsFor(String providerId) {
    final p = _registry.byId(providerId);
    return p?.supportedModels ?? const [];
  }

  /// 测试连接（包装 Provider.testConnection）
  Future<bool> testConnection(ApiConfig config) async {
    final provider = _registry.resolve(config);
    return provider.testConnection(config);
  }
}

final providerControllerProvider =
    ChangeNotifierProvider<ProviderController>(
  (ref) => ProviderController(),
);