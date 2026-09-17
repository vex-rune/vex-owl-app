import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../../application/parser/api_configs_parser.dart';
import '../../application/parser/context_settings_parser.dart';
import '../../data/repository/i_wiki_repository.dart';
import '../providers/app_providers.dart';
import 'provider_controller.dart';

/// 设置管理控制器（基于 ChangeNotifier + Riverpod）。
///
/// 负责：
/// - API 配置（多套，含默认标记）
/// - 上下文策略 / 最大条数 / 摘要长度
/// - 记忆注入开关与 Token 预算
/// - 功能开关（自动 Ingest、冲突校验、自动 Lint 等）
/// - Token 告警阈值
/// - 累计 Token 统计
///
/// 持久化：所有数据存到 `wiki/api-configs.md` 和 `wiki/context-settings.md`，
/// 通过 [IWikiRepository] 读写。内存缓存 + 修改后异步写回文件。
///
/// 公开 API 兼容旧版（List<ApiConfig> / defaultConfig / 各类 getter / toggle 方法），
/// UI 层无需修改。
class SettingsController extends ChangeNotifier {
  SettingsController(this._ref) {
    // 启动时异步加载（不阻塞构造函数）
    _load();
  }

  final Ref _ref;

  late final IWikiRepository _wiki = _ref.read(wikiRepositoryProvider);

  // ── 内部缓存 ──

  List<ApiConfig> _apiConfigs = const [];
  ApiConfig? _defaultConfig;

  // ── 应用设置（拆分自原内存态字段） ──

  AppSettings _settings = const AppSettings();

  // ── Getters（保持旧 API 不变） ──

  List<ApiConfig> get apiConfigs => _apiConfigs;
  ApiConfig? get defaultConfig => _defaultConfig;

  /// 当前完整 AppSettings（含上下文、记忆、功能、Token、统计）
  AppSettings get settings => _settings;

  // ── 功能开关 ──
  bool get autoIngest => _settings.features.autoIngest;
  bool get autoConflictCheck => _settings.features.autoConflictCheck;
  bool get autoLint => _settings.features.autoLint;
  bool get autoBackup => _settings.features.autoBackup;
  bool get autoCleanRaw => _settings.features.autoCleanRaw;

  // ── Token 阈值 ──
  int get chatTokenThreshold => _settings.tokens.chatTokenThreshold;
  int get ingestTokenThreshold => _settings.tokens.ingestTokenThreshold;

  // ── 新增（Phase 3/4 注入使用，本 Phase 暂不持久化对应 UI） ──
  ContextSettings get contextSettings => _settings.context;
  MemorySettings get memorySettings => _settings.memory;

  /// 访问 ProviderController（用于 UI 层枚举 Provider / 模型预设）
  ProviderController get providerController =>
      _ref.read(providerControllerProvider);

  /// 加载所有配置（启动时调用一次）
  Future<void> _load() async {
    await Future.wait([loadConfigs(), _loadSettings()]);
  }

  /// 加载 API 配置
  Future<void> loadConfigs() async {
    try {
      final raw = await _wiki.readApiConfigs();
      if (raw == null) {
        _apiConfigs = const [];
        _defaultConfig = null;
      } else {
        final data = ApiConfigsParser.parse(raw);
        _apiConfigs = data.configs;
        _defaultConfig = data.defaultConfig;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('加载 API 配置失败：$e');
    }
  }

  /// 加载应用设置
  Future<void> _loadSettings() async {
    try {
      final raw = await _wiki.readContextSettings();
      if (raw == null) {
        _settings = const AppSettings();
      } else {
        _settings = ContextSettingsParser.parse(raw);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('加载应用设置失败：$e');
    }
  }

  /// 保存 API 配置（新增或更新）
  ///
  /// [config] API 配置对象。如果 [config.id] 为 null 则新增（自动分配 id），
  /// 否则按 id 更新。
  Future<void> saveConfig(ApiConfig config) async {
    try {
      final list = [..._apiConfigs];
      if (config.id == null) {
        // 新增：分配下一个 id
        final nextId = _nextId(list);
        list.add(config.copyWith(id: nextId));
      } else {
        final idx = list.indexWhere((c) => c.id == config.id);
        if (idx >= 0) {
          list[idx] = config;
        } else {
          list.add(config);
        }
      }
      // 如果设为默认，先取消其他默认标记
      if (config.isDefault) {
        for (var i = 0; i < list.length; i++) {
          if (list[i].id != config.id) {
            list[i] = list[i].copyWith(isDefault: false);
          }
        }
      }
      _apiConfigs = list;
      _defaultConfig = _resolveDefault(list);

      await _persistConfigs();
      notifyListeners();
    } catch (e) {
      debugPrint('保存配置失败：$e');
    }
  }

  /// 删除指定 API 配置
  Future<void> deleteConfig(int id) async {
    try {
      final list = _apiConfigs.where((c) => c.id != id).toList();
      // 如果删的是默认配置，重新指定第一个为默认
      if (_defaultConfig?.id == id && list.isNotEmpty) {
        list[0] = list[0].copyWith(isDefault: true);
      }
      _apiConfigs = list;
      _defaultConfig = _resolveDefault(list);
      await _persistConfigs();
      notifyListeners();
    } catch (e) {
      debugPrint('删除配置失败：$e');
    }
  }

  /// 将指定配置设为默认
  Future<void> setDefaultConfig(int id) async {
    try {
      final list = _apiConfigs
          .map((c) => c.id == id ? c.copyWith(isDefault: true) : c.copyWith(isDefault: false))
          .toList();
      _apiConfigs = list;
      _defaultConfig = list.firstWhere((c) => c.id == id);
      await _persistConfigs();
      notifyListeners();
    } catch (e) {
      debugPrint('设置默认配置失败：$e');
    }
  }

  /// 更新配置的 Provider 类型
  Future<void> updateConfigProvider(int id, String providerId) async {
    try {
      final idx = _apiConfigs.indexWhere((c) => c.id == id);
      if (idx < 0) return;
      await saveConfig(_apiConfigs[idx].copyWith(providerId: providerId));
    } catch (e) {
      debugPrint('更新 Provider 失败：$e');
    }
  }

  // ── 功能开关 ──

  Future<void> toggleAutoIngest() async {
    _settings = _settings.copyWith(
      features: _settings.features.copyWith(autoIngest: !_settings.features.autoIngest),
    );
    await _persistSettings();
    notifyListeners();
  }

  Future<void> toggleAutoConflictCheck() async {
    _settings = _settings.copyWith(
      features: _settings.features.copyWith(autoConflictCheck: !_settings.features.autoConflictCheck),
    );
    await _persistSettings();
    notifyListeners();
  }

  Future<void> toggleAutoLint() async {
    _settings = _settings.copyWith(
      features: _settings.features.copyWith(autoLint: !_settings.features.autoLint),
    );
    await _persistSettings();
    notifyListeners();
  }

  Future<void> toggleAutoBackup() async {
    _settings = _settings.copyWith(
      features: _settings.features.copyWith(autoBackup: !_settings.features.autoBackup),
    );
    await _persistSettings();
    notifyListeners();
  }

  Future<void> toggleAutoCleanRaw() async {
    _settings = _settings.copyWith(
      features: _settings.features.copyWith(autoCleanRaw: !_settings.features.autoCleanRaw),
    );
    await _persistSettings();
    notifyListeners();
  }

  // ── Token 阈值 ──

  Future<void> setChatTokenThreshold(int value) async {
    _settings = _settings.copyWith(
      tokens: _settings.tokens.copyWith(chatTokenThreshold: value),
    );
    await _persistSettings();
    notifyListeners();
  }

  Future<void> setIngestTokenThreshold(int value) async {
    _settings = _settings.copyWith(
      tokens: _settings.tokens.copyWith(ingestTokenThreshold: value),
    );
    await _persistSettings();
    notifyListeners();
  }

  // ── 上下文管理（Phase 3 新增） ──

  Future<void> setContextStrategy(ContextStrategy strategy) async {
    _settings = _settings.copyWith(
      context: _settings.context.copyWith(strategy: strategy),
    );
    await _persistSettings();
    notifyListeners();
  }

  Future<void> setMaxMessages(int value) async {
    _settings = _settings.copyWith(
      context: _settings.context.copyWith(maxMessages: value),
    );
    await _persistSettings();
    notifyListeners();
  }

  Future<void> setSummaryMaxChars(int value) async {
    _settings = _settings.copyWith(
      context: _settings.context.copyWith(summaryMaxChars: value),
    );
    await _persistSettings();
    notifyListeners();
  }

  // ── 内部辅助 ──

  int _nextId(List<ApiConfig> list) {
    if (list.isEmpty) return 1;
    return list.map((c) => c.id ?? 0).reduce((a, b) => a > b ? a : b) + 1;
  }

  /// 在候选列表中找出默认配置（优先 isDefault=true，否则取第一个，空则 null）
  ApiConfig? _resolveDefault(List<ApiConfig> list) {
    if (list.isEmpty) return null;
    final defs = list.where((c) => c.isDefault).toList();
    return defs.isNotEmpty ? defs.first : list.first;
  }

  Future<void> _persistConfigs() async {
    try {
      final md = ApiConfigsParser.serialize(ApiConfigs(
        version: 1,
        configs: _apiConfigs,
      ));
      await _wiki.writeApiConfigs(md);
    } catch (e) {
      debugPrint('持久化 API 配置失败：$e');
    }
  }

  Future<void> _persistSettings() async {
    try {
      final md = ContextSettingsParser.serialize(_settings);
      await _wiki.writeContextSettings(md);
    } catch (e) {
      debugPrint('持久化应用设置失败：$e');
    }
  }
}

/// Riverpod Provider：暴露 [SettingsController]
final settingsControllerProvider =
    ChangeNotifierProvider<SettingsController>(
  (ref) => SettingsController(ref),
);