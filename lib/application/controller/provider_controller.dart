import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../../data/llm/llm.dart';

/// Provider 管理控制器
///
/// 暴露 LlmProviderRegistry，让 UI 层能：
/// 1. 枚举所有可用 Provider（用于"添加 API 配置"对话框的供应商下拉）
/// 2. 根据 ApiConfig 自动解析 Provider
/// 3. 测试连接
/// 4. 获取 Provider 的模型预设列表
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
