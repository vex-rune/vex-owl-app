import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../../data/llm/llm.dart';
import '../../data/storage/config_storage.dart';
import '../../data/storage/owl_root.dart';
import '../providers/app_providers.dart';
import 'provider_controller.dart';

/// 设置管理控制器（v6.4）
///
/// v6.4 变更：
/// - 应用设置从 `wiki/context-settings.md` 迁移到 `config/app_settings.jsonl`
/// - Agent 配置从 `wiki/.meta/export-meta.json` 迁移到 `config/api_agents.jsonl`
/// - 不再依赖 WikiRepository 读写配置
class SettingsController extends ChangeNotifier {
  SettingsController(this._ref) {
    _load();
  }

  final Ref _ref;

  late final ConfigStorage _configStorage;

  /// 用户添加的 Agent 列表
  List<ApiConfig> _agents = const [];

  /// 当前默认 Agent
  ApiConfig? _defaultConfig;

  /// 应用设置
  AppSettings _settings = const AppSettings();

  /// 当前活跃的模型名称（用于对话页模型切换）
  /// 与 _defaultConfig 不同，切换模型不会修改默认配置
  String? _activeModelName;

  // ── Getters ──

  List<ApiConfig> get agents => _agents;
  List<ApiConfig> get apiConfigs =>
      _agents.where((a) => a.enabled).toList(growable: false);
  ApiConfig? get defaultConfig => _defaultConfig;
  AppSettings get settings => _settings;

  /// 当前活跃的模型名称（可能与 defaultConfig.modelName 不同）
  String? get activeModelName => _activeModelName;

  // ── 功能开关 ──

  bool get autoIngest => _settings.features.autoIngest;
  bool get autoConflictCheck => _settings.features.autoConflictCheck;
  bool get autoLint => _settings.features.autoLint;
  bool get autoBackup => _settings.features.autoBackup;
  bool get autoCleanRaw => _settings.features.autoCleanRaw;

  // ── Token 阈值 ──

  int get chatTokenThreshold => _settings.tokens.chatTokenThreshold;
  int get ingestTokenThreshold => _settings.tokens.ingestTokenThreshold;

  // ── 上下文管理 / 记忆管理 ──

  ContextSettings get contextSettings => _settings.context;
  MemorySettings get memorySettings => _settings.memory;

  // ── ProviderController 暴露给 UI 层 ──

  ProviderController get providerController =>
      _ref.read(providerControllerProvider);

  // ── 加载流程 ──

  Future<void> _load() async {
    // 初始化 ConfigStorage
    _configStorage = ConfigStorage(owlRoot: OwlRoot.instance.rootPath!);
    log.info('开始加载配置...');
    await Future.wait([loadAgents(), _loadSettings()]);
    log.info('配置加载完成，共 ${_agents.length} 个 Agent');
  }

  /// 从 config/api_agents.jsonl 读取 Agent 列表
  Future<void> loadAgents() async {
    try {
      log.debug('加载 Agent 配置...');
      final stored = await _configStorage.loadAgents();
      final registry = LlmProviderRegistry.instance;

      final agents = <ApiConfig>[];
      for (final m in stored) {
        final pid = m.providerId;
        final provider = registry.byId(pid) ?? OpenAiProvider();
        final modelName = m.modelName;
        final preset = provider.supportedModels
            .whereType<ProviderModelPreset?>()
            .firstWhere(
              (p) => p!.id == modelName,
              orElse: () => null,
            );
        // 合并 preset 默认值（仅当用户未自定义 maxTokens 时使用 preset 值）
        // 使用 -1 表示"未设置"，表示使用 provider 的 preset 值
        final maxTokens = m.maxTokens <= 0 && preset != null
            ? preset.maxOutputTokens
            : m.maxTokens;
        agents.add(m.copyWith(maxTokens: maxTokens));
      }

      _agents = agents;
      _defaultConfig = _resolveDefault(_agents);
      notifyListeners();
      log.debug('加载了 ${_agents.length} 个 Agent');
    } catch (e, st) {
      log.error('加载 Agent 配置失败：$e', st);
    }
  }

  Future<void> _loadSettings() async {
    try {
      log.debug('加载应用设置...');
      _settings = await _configStorage.loadSettings();
      notifyListeners();
      log.debug('应用设置加载完成');
    } catch (e, st) {
      log.error('加载应用设置失败：$e', st);
    }
  }

  // ── Agent 写操作 ──

  /// 新增一个 Agent（从 Registry 预设创建）
  Future<void> addAgent(String providerId, String modelName) async {
    log.info('添加 Agent: $providerId/$modelName');
    final registry = LlmProviderRegistry.instance;
    final provider = registry.byId(providerId);
    if (provider == null) {
      log.error('未找到 Provider: $providerId');
      return;
    }

    if (_agents.any(
        (a) => a.providerId == providerId && a.modelName == modelName)) {
      log.debug('Agent 已存在: $modelName');
      return;
    }

    final preset = provider.supportedModels
        .whereType<ProviderModelPreset?>()
        .firstWhere((p) => p!.id == modelName, orElse: () => null);

    // 使用 -1 表示"使用 preset 默认值"，后续加载时会合并
    final agent = ApiConfig(
      configName: modelName,
      modelName: modelName,
      apiEndpoint: provider.configSchema.endpointDefault,
      apiKey: '',
      temperature: 0.7,
      topP: 1.0,
      maxTokens: -1,  // -1 表示使用 preset 默认值
      maxCompletionTokens: preset?.maxOutputTokens ?? 4096,
      thinkingEnabled: false,
      isDefault: _agents.isEmpty,
      enabled: true,
      providerId: providerId,
    );

    _agents = [..._agents, agent];
    _defaultConfig = _resolveDefault(_agents);
    await _persistAgents();
    notifyListeners();
    log.info('Agent 添加成功，当前共 ${_agents.length} 个');
  }

  /// 删除一个 Agent
  Future<void> deleteAgent(String providerId, String modelName) async {
    log.info('删除 Agent: $providerId/$modelName');
    _agents =
        _agents.where((a) => !(a.providerId == providerId && a.modelName == modelName)).toList();
    _defaultConfig = _resolveDefault(_agents);
    await _persistAgents();
    notifyListeners();
    log.info('Agent 删除成功，当前共 ${_agents.length} 个');
  }

  /// 保存单个 Agent
  Future<void> saveAgent(ApiConfig agent) async {
    try {
      log.debug('保存 Agent: ${agent.providerId}/${agent.modelName}');
      final list = [..._agents];
      final idx = list.indexWhere((a) => _agentKeyOf(a) == _agentKeyOf(agent));
      if (idx >= 0) {
        list[idx] = agent;
        log.debug('更新已有 Agent');
      } else {
        list.add(agent);
        log.debug('新增 Agent');
      }
      if (agent.isDefault) {
        for (var i = 0; i < list.length; i++) {
          if (_agentKeyOf(list[i]) != _agentKeyOf(agent)) {
            list[i] = list[i].copyWith(isDefault: false);
          }
        }
      }
      _agents = list;
      _defaultConfig = _resolveDefault(_agents);
      await _persistAgents();
      notifyListeners();
      log.info('Agent 保存成功');
    } catch (e, st) {
      log.error('保存 Agent 失败：$e', st);
    }
  }

  /// 把指定 Agent 设为默认
  Future<void> setDefaultAgent(String providerId, String modelName) async {
    log.info('设置默认 Agent: $providerId/$modelName');
    final list = _agents.map((a) {
      final isThis = a.providerId == providerId && a.modelName == modelName;
      return a.copyWith(isDefault: isThis);
    }).toList();
    _agents = list;
    _defaultConfig = _resolveDefault(_agents);
    await _persistAgents();
    notifyListeners();
  }

  /// 启用 / 停用某个 Agent
  Future<void> setAgentEnabled(
    String providerId,
    String modelName, {
    required bool enabled,
  }) async {
    final list = _agents.map((a) {
      if (a.providerId == providerId && a.modelName == modelName) {
        return a.copyWith(isDefault: a.isDefault && enabled, enabled: enabled);
      }
      return a;
    }).toList();
    _agents = list;
    _defaultConfig = _resolveDefault(_agents);
    await _persistAgents();
    notifyListeners();
  }

  /// 对话页模型切换（仅切换活跃模型，不修改默认配置）
  Future<void> setActiveModel(String modelName) async {
    // 检查目标模型是否存在且启用
    final targetAgent = _agents.firstWhere(
      (a) => a.providerId == _defaultConfig?.providerId && a.modelName == modelName,
      orElse: () => throw Exception('未找到指定的模型'),
    );

    if (!targetAgent.enabled) {
      debugPrint('指定的模型未启用');
      return;
    }

    _activeModelName = modelName;
    notifyListeners();
  }

  // ── 功能开关 / Token / 上下文 ──

  Future<void> toggleAutoIngest() async {
    _settings = _settings.copyWith(
      features: _settings.features
          .copyWith(autoIngest: !_settings.features.autoIngest),
    );
    await _persistSettings();
    notifyListeners();
  }

  Future<void> toggleAutoConflictCheck() async {
    _settings = _settings.copyWith(
      features: _settings.features
          .copyWith(autoConflictCheck: !_settings.features.autoConflictCheck),
    );
    await _persistSettings();
    notifyListeners();
  }

  Future<void> toggleAutoLint() async {
    _settings = _settings.copyWith(
      features:
          _settings.features.copyWith(autoLint: !_settings.features.autoLint),
    );
    await _persistSettings();
    notifyListeners();
  }

  Future<void> toggleAutoBackup() async {
    _settings = _settings.copyWith(
      features: _settings.features
          .copyWith(autoBackup: !_settings.features.autoBackup),
    );
    await _persistSettings();
    notifyListeners();
  }

  Future<void> toggleAutoCleanRaw() async {
    _settings = _settings.copyWith(
      features: _settings.features
          .copyWith(autoCleanRaw: !_settings.features.autoCleanRaw),
    );
    await _persistSettings();
    notifyListeners();
  }

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

  String _agentKeyOf(ApiConfig a) => '${a.providerId}::${a.modelName}';

  ApiConfig? _resolveDefault(List<ApiConfig> list) {
    if (list.isEmpty) return null;
    final defs = list.where((c) => c.isDefault && c.enabled).toList();
    if (defs.isNotEmpty) return defs.first;
    final enabled = list.where((c) => c.enabled).toList();
    return enabled.isNotEmpty ? enabled.first : list.first;
  }

  Future<void> _persistAgents() async {
    try {
      await _configStorage.saveAgents(_agents);
    } catch (e) {
      debugPrint('持久化 Agent 配置失败：$e');
    }
  }

  Future<void> _persistSettings() async {
    try {
      await _configStorage.saveSettings(_settings);
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
