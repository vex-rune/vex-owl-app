/// 配置文件迁移器（v6.4）
///
/// 将旧版配置迁移到新版 JSONL 格式：
/// - `wiki/context-settings.md` → `config/app_settings.jsonl`
/// - `wiki/.meta/export-meta.json` → `config/api_agents.jsonl`
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/model/app_settings.dart';
import '../../../core/model/api_config.dart';
import '../../../core/core.dart';
import '../../../application/parser/context_settings_parser.dart';
import '../config_storage.dart';

/// 配置文件迁移器
class V2ConfigMigration {
  V2ConfigMigration({
    required String owlRoot,
  })  : _owlRoot = owlRoot,
        _configStorage = ConfigStorage(owlRoot: owlRoot);

  final String _owlRoot;
  final ConfigStorage _configStorage;

  /// 执行迁移
  ///
  /// 返回是否执行了迁移。
  Future<bool> migrate() async {
    // 检查是否已迁移过（config 文件已存在且有内容）
    final agentsFile = File(p.join(_owlRoot, 'config', 'api_agents.jsonl'));
    if (await agentsFile.exists()) {
      final content = await agentsFile.readAsString();
      if (content.trim().isNotEmpty) {
        log.debug('📦 配置迁移：api_agents.jsonl 已存在，跳过');
        return false;
      }
    }

    bool migrated = false;

    // 迁移 context-settings.md → app_settings.jsonl
    await _migrateSettings();

    // 迁移 export-meta.json → api_agents.jsonl
    await _migrateAgents();

    log.debug('✅ 配置迁移完成');
    return migrated;
  }

  Future<void> _migrateSettings() async {
    final settingsFile = File(p.join(_owlRoot, 'wiki', 'context-settings.md'));
    if (!await settingsFile.exists()) {
      log.debug('📦 配置迁移：context-settings.md 不存在，跳过');
      return;
    }

    try {
      final content = await settingsFile.readAsString();
      final settings = ContextSettingsParser.parse(content);
      await _configStorage.saveSettings(settings);
      log.debug('📦 迁移应用设置：context-settings.md → app_settings.jsonl');
    } catch (e) {
      log.debug('⚠️ 迁移应用设置失败：$e');
    }
  }

  Future<void> _migrateAgents() async {
    final metaFile = File(p.join(_owlRoot, 'wiki', '.meta', 'export-meta.json'));
    if (!await metaFile.exists()) {
      log.debug('📦 配置迁移：export-meta.json 不存在，跳过');
      return;
    }

    try {
      final raw = await metaFile.readAsString();
      if (raw.trim().isEmpty) return;

      final meta = jsonDecode(raw) as Map<String, dynamic>;
      final agentsList = meta['api_agents'] as List<dynamic>? ?? [];

      final agents = <ApiConfig>[];
      for (final item in agentsList) {
        if (item is Map<String, dynamic>) {
          agents.add(ApiConfig.fromJsonl(item));
        }
      }

      if (agents.isNotEmpty) {
        await _configStorage.saveAgents(agents);
        log.debug('📦 迁移 Agent 配置：${agents.length} 个');
      }
    } catch (e) {
      log.debug('⚠️ 迁移 Agent 配置失败：$e');
    }
  }
}
