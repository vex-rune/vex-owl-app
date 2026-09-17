/// API 配置集合容器。
///
/// 持久化到 `wiki/api-configs.md`，每条配置对应一个 `## ⚙️ 配置 N` 段。
/// 本文件本身只是已有 [ApiConfig] 模型的轻量聚合，
/// 真正的序列化逻辑见 `lib/application/parser/api_configs_parser.dart`。
library;

import 'api_config.dart';

/// API 配置集合。
///
/// 用于在内存中缓存从 `wiki/api-configs.md` 解析出的所有配置，
/// 并提供「获取默认配置」等便捷方法。
class ApiConfigs {
  const ApiConfigs({
    this.version = 1,
    this.configs = const [],
  });

  /// 当前 schema 版本（用于未来字段迁移）
  final int version;

  /// 所有 API 配置（含默认配置）
  final List<ApiConfig> configs;

  /// 获取当前默认配置（`isDefault == true`），无默认则返回第一个，最后返回 null
  ApiConfig? get defaultConfig {
    final defaults = configs.where((c) => c.isDefault).toList();
    if (defaults.isNotEmpty) return defaults.first;
    if (configs.isNotEmpty) return configs.first;
    return null;
  }

  /// 根据 id 查找配置
  ApiConfig? findById(int id) {
    for (final c in configs) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// 复制并替换配置集合
  ApiConfigs copyWith({int? version, List<ApiConfig>? configs}) {
    return ApiConfigs(
      version: version ?? this.version,
      configs: configs ?? this.configs,
    );
  }
}