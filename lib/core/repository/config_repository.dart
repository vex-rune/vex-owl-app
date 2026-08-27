import '../model/owl_config.dart';

/// 配置仓储抽象。
///
/// 启动时若不存在 → 写入默认配置;UI 在用户点保存时调用 [save]。
abstract class ConfigRepository {
  Future<OwlConfig> load();
  Future<void> save(OwlConfig config);
  OwlConfig? get current;
}