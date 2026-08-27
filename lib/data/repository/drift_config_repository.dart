import 'dart:async';
import 'dart:convert';

import '../../core/model/owl_config.dart';
import '../../core/repository/config_repository.dart';
import '../storage/database/app_database.dart';

/// Drift 持久化的 ConfigRepository 实现。
///
/// OwlConfig 以 JSON 字符串形式存储在 app_settings 单行中(key='owl_config')。
/// 其它单独配置项(如 theme / memoryCompression 等)走 key 拆分,
/// 便于细粒度观察与迁移。
class DriftConfigRepository implements ConfigRepository {
  DriftConfigRepository(this.db);

  final AppDatabase db;

  static const String _kConfigKey = 'owl_config';

  OwlConfig? _cached;

  @override
  Future<OwlConfig> load() async {
    if (_cached != null) return _cached!;
    final raw = await db.settingsStore.get(_kConfigKey);
    if (raw == null) {
      // 首次启动:写默认
      final empty = OwlConfig.empty();
      await save(empty);
      _cached = empty;
      return empty;
    }
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final cfg = OwlConfig.fromJson(map);
    _cached = cfg;
    return cfg;
  }

  @override
  Future<void> save(OwlConfig config) async {
    _cached = config;
    // 持久化必须走"非脱敏"通道 —— [OwlConfig.toJson] 会把 apiKey redact 成
    // `sk-****1234`,若直接落库,下次 load 时会被当真实 key 用,导致 API 401。
    await db.settingsStore.set(_kConfigKey, jsonEncode(_toStorageMap(config)));
  }

  /// 持久化专用:原样保留 [OwlConfig] 所有字段(包含 apiKey 明文)。
  Map<String, dynamic> _toStorageMap(OwlConfig config) =>
      <String, dynamic>{
        'apiKey': config.apiKey,
        'baseUrl': config.baseUrl,
        'model': config.model,
        'maxRounds': config.maxRounds,
        'theme': config.theme,
        'memoryCompression': config.memoryCompression,
        'bochaApiKey': config.bochaApiKey,
        'temperature': config.temperature,
      };

  @override
  OwlConfig? get current => _cached;
}