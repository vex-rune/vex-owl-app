import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../../application/parser/context_settings_parser.dart';
import '../../data/llm/llm.dart';
import '../../data/repository/i_wiki_repository.dart';
import '../providers/app_providers.dart';
import 'provider_controller.dart';

/// 设置管理控制器（基于 ChangeNotifier + Riverpod）。
///
/// v6.3 设计变更：
/// - **逐个添加**：Agent 不再自动铺平所有 Provider 预设。
///   用户在 Settings UI 选择某个 Provider → 选模型 → 点"添加"创建一个 Agent。
/// - Agent 列表仅包含用户已添加并持久化的条目（`export-meta.json.api_agents`）。
/// - 用户在 Settings UI 上：调整每个 Agent 的 endpoint / key / 温度 / topP /
///   max_tokens / thinking 开关，并标记"哪个 Agent 是默认"；也可删除 Agent。
/// - 持久化：全部写到 `.meta/export-meta.json.api_agents`。
///
/// 对外暴露：
/// - `agents`：用户添加的全部 Agent（含 enabled=false）。
/// - `apiConfigs`：所有 enabled 的 Agent，供对话页模型选择器使用。
/// - `defaultConfig`：当前默认 Agent（`isDefault == true`）；不存在则取
///   第一个 enabled 的 Agent；都没有则返回 null。
/// - `addAgent(providerId, modelName)`：从 Registry 预设创建新 Agent。
/// - `deleteAgent(providerId, modelName)`：删除一个 Agent。
class SettingsController extends ChangeNotifier {
  SettingsController(this._ref) {
    _load();
  }

  final Ref _ref;

  late final IWikiRepository _wiki = _ref.read(wikiRepositoryProvider);

  /// 用户添加的 Agent 列表（仅包含已持久化的条目）
  List<ApiConfig> _agents = const [];

  /// 当前默认 Agent
  ApiConfig? _defaultConfig;

  /// 应用设置（与 Agent 配置分离存储）
  AppSettings _settings = const AppSettings();

  // ── Getters ──

  /// 全量 Agent（含 enabled=false）
  List<ApiConfig> get agents => _agents;

  /// 兼容旧 API：返回 enabled 的 Agent
  List<ApiConfig> get apiConfigs =>
      _agents.where((a) => a.enabled).toList(growable: false);

  /// 默认 Agent（兼容旧 API）
  ApiConfig? get defaultConfig => _defaultConfig;

  /// 应用设置
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

  // ── 上下文管理 / 记忆管理 ──

  ContextSettings get contextSettings => _settings.context;
  MemorySettings get memorySettings => _settings.memory;

  // ── ProviderController 暴露给 UI 层 ──

  ProviderController get providerController =>
      _ref.read(providerControllerProvider);

  // ── 加载流程 ──

  Future<void> _load() async {
    await Future.wait([loadAgents(), _loadSettings()]);
  }

  /// 从 export-meta.json 读取用户已添加的 Agent 列表。
  ///
  /// 不再自动铺平 Registry 预设——只有用户主动添加的 Agent 才会出现。
  /// Registry 中过期的 Agent 仍保留（enabled=false 即可）。
  Future<void> loadAgents() async {
    try {
      final stored = await _wiki.readAgentConfigsJson();
      final registry = LlmProviderRegistry.instance;

      final agents = <ApiConfig>[];
      for (final m in stored) {
        final pid = m['providerId'] as String? ?? 'openai';
        final provider = registry.byId(pid) ?? OpenAiProvider();
        // 找对应 preset（用于 maxOutputTokens 等默认值回退）
        final modelName = m['modelName'] as String? ?? '';
        final preset = provider.supportedModels
            .cast<ProviderModelPreset?>()
            .firstWhere(
              (p) => p!.id == modelName,
              orElse: () => null,
            );
        agents.add(_decodeAgent(
          provider: provider,
          preset: preset,
          stored: m,
        ));
      }

      _agents = agents;
      _defaultConfig = _resolveDefault(_agents);
      notifyListeners();
    } catch (e) {
      debugPrint('加载 Agent 配置失败：$e');
    }
  }

  Future<void> _loadSettings() async {
    try {
      final raw = await _wiki.readContextSettings();
      _settings = raw == null
          ? const AppSettings()
          : ContextSettingsParser.parse(raw);
      notifyListeners();
    } catch (e) {
      debugPrint('加载应用设置失败：$e');
    }
  }

  // ── Agent 写操作 ──

  /// 新增一个 Agent（从 Registry 预设创建）。
  ///
  /// 若该 providerId::modelName 已存在则静默返回。
  /// 第一个添加的 Agent 自动成为默认。
  Future<void> addAgent(String providerId, String modelName) async {
    final registry = LlmProviderRegistry.instance;
    final provider = registry.byId(providerId);
    if (provider == null) return;
    // 已存在 → 不重复添加
    if (_agents.any(
        (a) => a.providerId == providerId && a.modelName == modelName)) {
      return;
    }
    final preset = provider.supportedModels
        .cast<ProviderModelPreset?>()
        .firstWhere((p) => p!.id == modelName, orElse: () => null);
    final agent = _decodeAgent(
      provider: provider,
      preset: preset,
      stored: null,
    );
    // 第一个添加的 Agent 自动成为默认
    final isFirst = _agents.isEmpty;
    final toSave = isFirst ? agent.copyWith(isDefault: true) : agent;
    _agents = [..._agents, toSave];
    _defaultConfig = _resolveDefault(_agents);
    await _persistAgents();
    notifyListeners();
  }

  /// 删除一个 Agent（按 providerId + modelName）
  Future<void> deleteAgent(String providerId, String modelName) async {
    _agents =
        _agents.where((a) => !(a.providerId == providerId && a.modelName == modelName)).toList();
    _defaultConfig = _resolveDefault(_agents);
    await _persistAgents();
    notifyListeners();
  }

  /// 保存单个 Agent（覆盖）。key = providerId::modelName
  Future<void> saveAgent(ApiConfig agent) async {
    try {
      final list = [..._agents];
      final idx = list.indexWhere((a) => _agentKeyOf(a) == _agentKeyOf(agent));
      if (idx >= 0) {
        list[idx] = agent;
      } else {
        list.add(agent);
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
    } catch (e) {
      debugPrint('保存 Agent 失败：$e');
    }
  }

  /// 把指定 Agent 设为默认（确保其他 Agent 都 isDefault=false）
  Future<void> setDefaultAgent(String providerId, String modelName) async {
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

  /// 「对话页模型切换」：用 modelName 替换默认 Agent 的 modelName（同 provider）
  ///
  /// 若当前默认 Agent 已存在同 modelName，则不变；
  /// 若用户在 UI 切换到了 Registry 内尚未启用的预设，则启用之。
  Future<void> setActiveModel(String modelName) async {
    final def = _defaultConfig;
    if (def == null) return;
    if (def.modelName == modelName) return;
    try {
      final next = def.copyWith(modelName: modelName);
      await saveAgent(next);
    } catch (e) {
      debugPrint('更新默认模型失败：$e');
    }
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

  /// 从已有持久化 JSON + Provider/Preset 信息构造一个 ApiConfig
  ApiConfig _decodeAgent({
    required LlmProvider provider,
    ProviderModelPreset? preset,
    required Map<String, dynamic>? stored,
  }) {
    final schema = provider.configSchema;
    final s = stored;
    final providerId = provider.id;
    final modelName =
        (s?['modelName'] as String?) ?? preset?.id ?? schema.modelDefault;
    final endpoint =
        (s?['apiEndpoint'] as String?) ?? schema.endpointDefault;
    final apiKey = (s?['apiKey'] as String?) ?? '';
    final temperature = (s?['temperature'] as num?)?.toDouble() ?? 0.7;
    final topP = (s?['topP'] as num?)?.toDouble() ?? 1.0;
    final maxTokens = (s?['maxTokens'] as num?)?.toInt() ??
        preset?.maxOutputTokens ??
        4096;
    final maxCompletionTokens =
        (s?['maxCompletionTokens'] as num?)?.toInt() ?? 4096;
    final thinkingEnabled = (s?['thinkingEnabled'] as bool?) ?? false;
    final isDefault = (s?['isDefault'] as bool?) ?? false;
    final enabled = (s?['enabled'] as bool?) ?? true;

    return ApiConfig(
      id: (s?['id'] as num?)?.toInt(),
      configName: modelName,
      modelName: modelName,
      apiEndpoint: endpoint,
      apiKey: apiKey,
      temperature: temperature,
      topP: topP,
      maxTokens: maxTokens,
      maxCompletionTokens: maxCompletionTokens,
      thinkingEnabled: thinkingEnabled,
      isDefault: isDefault,
      enabled: enabled,
      providerId: providerId,
    );
  }

  Map<String, dynamic> _encodeAgent(ApiConfig a) => {
        'id': a.id,
        'configName': a.configName,
        'providerId': a.providerId,
        'modelName': a.modelName,
        'apiEndpoint': a.apiEndpoint,
        'apiKey': a.apiKey,
        'temperature': a.temperature,
        'topP': a.topP,
        'maxTokens': a.maxTokens,
        'maxCompletionTokens': a.maxCompletionTokens,
        'thinkingEnabled': a.thinkingEnabled,
        'isDefault': a.isDefault,
        'enabled': a.enabled,
      };

  ApiConfig? _resolveDefault(List<ApiConfig> list) {
    if (list.isEmpty) return null;
    final defs = list.where((c) => c.isDefault && c.enabled).toList();
    if (defs.isNotEmpty) return defs.first;
    final enabled = list.where((c) => c.enabled).toList();
    return enabled.isNotEmpty ? enabled.first : list.first;
  }

  Future<void> _persistAgents() async {
    try {
      final list = _agents.map(_encodeAgent).toList();
      await _wiki.writeAgentConfigsJson(list);
    } catch (e) {
      debugPrint('持久化 Agent 配置失败：$e');
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