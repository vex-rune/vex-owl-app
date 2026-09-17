/// 配置文件存储服务（v6.4）
///
/// 负责 `.owl/config/` 目录下的 JSONL 文件读写：
/// - `app_settings.jsonl` — 应用设置（单行）
/// - `api_agents.jsonl` — Agent/API 配置（每行一个）
///
/// 设计：
/// - 所有操作走 AtomicFileWriter（原子写 + 备份 + 审计）
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/core.dart';
import '../../core/model/app_settings.dart';
import '../../core/model/api_config.dart';
import 'atomic_file_writer.dart';

/// 配置文件存储服务
class ConfigStorage {
  ConfigStorage({
    required String owlRoot,
    AtomicFileWriter? writer,
  })  : _owlRoot = owlRoot,
        _writer = writer ?? AtomicFileWriter(rootPath: owlRoot);

  final String _owlRoot;
  final AtomicFileWriter _writer;

  String get _configDir => p.join(_owlRoot, 'config');

  // ── 应用设置（app_settings.jsonl）────────────────────────────────────

  /// 加载应用设置
  Future<AppSettings> loadSettings() async {
    final path = p.join(_configDir, 'app_settings.jsonl');
    final file = File(path);
    if (!await file.exists()) return const AppSettings();

    try {
      final lines = await file.readAsLines();
      for (final line in lines.reversed) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        if (!trimmed.endsWith('}')) continue;
        final json = jsonDecode(trimmed) as Map<String, dynamic>;
        return AppSettings.fromJsonl(json);
      }
      return const AppSettings();
    } catch (e) {
      log.debug('⚠️ 加载应用设置失败：$e');
      return const AppSettings();
    }
  }

  /// 保存应用设置（全量覆写）
  Future<void> saveSettings(AppSettings settings) async {
    final relativePath = 'config/app_settings.jsonl';
    final content = '${jsonEncode(settings.toJsonl())}\n';
    await _writer.write(relativePath, content);
  }

  // ── Agent 配置（api_agents.jsonl）────────────────────────────────────

  /// 加载 Agent 配置列表
  Future<List<ApiConfig>> loadAgents() async {
    final path = p.join(_configDir, 'api_agents.jsonl');
    final file = File(path);
    if (!await file.exists()) return [];

    try {
      final lines = await file.readAsLines();
      final agents = <ApiConfig>[];
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        if (!trimmed.endsWith('}')) continue;
        try {
          final json = jsonDecode(trimmed) as Map<String, dynamic>;
          agents.add(ApiConfig.fromJsonl(json));
        } catch (_) {
          // 损坏行跳过
        }
      }
      return agents;
    } catch (e) {
      log.debug('⚠️ 加载 Agent 配置失败：$e');
      return [];
    }
  }

  /// 保存 Agent 配置列表（全量覆写）
  Future<void> saveAgents(List<ApiConfig> agents) async {
    final relativePath = 'config/api_agents.jsonl';
    final buffer = StringBuffer();
    for (final agent in agents) {
      buffer.writeln(jsonEncode(agent.toJsonl()));
    }
    await _writer.write(relativePath, buffer.toString());
  }

  /// 追加单个 Agent（新增时用）
  Future<void> appendAgent(ApiConfig agent) async {
    final relativePath = 'config/api_agents.jsonl';
    await _writer.appendLine(relativePath, jsonEncode(agent.toJsonl()));
  }
}
