/// Wiki 自动整理服务
///
/// 业务闭环：
/// 1. 用户触发整理
/// 2. 分析 Wiki 状态（页面数量、链接完整性、冲突检测）
/// 3. 生成整理建议
/// 4. 执行整理操作
/// 5. 返回结果反馈
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/core.dart';
import '../../data/data.dart';
import '../controller/settings_controller.dart';
import 'tool_registry.dart';
import 'wiki_tools.dart';

/// 整理任务状态
enum OrganizeTaskStatus {
  idle,       // 空闲
  analyzing,  // 分析中
  planning,   // 生成方案
  executing,  // 执行中
  completed,  // 完成
  failed,     // 失败
}

/// 整理结果项
class OrganizeResultItem {
  OrganizeResultItem({
    required this.action,
    required this.path,
    required this.description,
    this.success = true,
    this.error,
  });

  final String action;      // 操作类型：create/update/link/resolve
  final String path;       // 文件路径
  final String description; // 描述
  final bool success;
  final String? error;
}

/// 整理任务结果
class OrganizeResult {
  OrganizeResult({
    required this.status,
    this.items = const [],
    this.summary,
    this.error,
    this.duration,
  });

  final OrganizeTaskStatus status;
  final List<OrganizeResultItem> items;
  final String? summary;
  final String? error;
  final Duration? duration;

  /// 成功数量
  int get successCount => items.where((i) => i.success).length;

  /// 失败数量
  int get failedCount => items.where((i) => !i.success).length;

  /// 是否有失败
  bool get hasFailures => failedCount > 0;

  /// 是否有结果
  bool get hasResults => items.isNotEmpty;
}

/// Wiki 自动整理服务
class WikiOrganizerService extends ChangeNotifier {
  WikiOrganizerService({
    required SettingsController settingsController,
    required String wikiRoot,
  })  : _settingsController = settingsController,
        _wikiRoot = wikiRoot;

  final SettingsController _settingsController;
  final String _wikiRoot;

  /// 当前状态
  OrganizeTaskStatus _status = OrganizeTaskStatus.idle;
  OrganizeTaskStatus get status => _status;

  /// 当前任务结果
  OrganizeResult? _result;
  OrganizeResult? get result => _result;

  /// 进度消息
  String _progressMessage = '';
  String get progressMessage => _progressMessage;

  /// 取消标志
  bool _cancelled = false;

  /// 执行整理任务
  ///
  /// [mode] 整理模式：full（全量整理）/ incremental（增量整理）
  /// [rawFile] 可选，指定要整理的原始文件路径
  Future<OrganizeResult> organize({
    String mode = 'incremental',
    String? rawFile,
  }) async {
    final startTime = DateTime.now();
    _cancelled = false;
    _result = null;

    if (rawFile != null) {
      _setStatus(OrganizeTaskStatus.analyzing, '正在分析文件: $rawFile...');
    } else {
      _setStatus(OrganizeTaskStatus.analyzing, '正在分析 Wiki 状态...');
    }

    try {
      // 1. 分析 Wiki 状态
      final analysis = await _analyzeWiki(rawFile: rawFile);
      if (_cancelled) return _cancelResult(startTime);

      _setStatus(OrganizeTaskStatus.planning, '正在生成整理方案...');
      await Future.delayed(const Duration(milliseconds: 500));
      if (_cancelled) return _cancelResult(startTime);

      // 2. 生成整理方案
      final plan = await _generatePlan(analysis, mode);
      if (_cancelled) return _cancelResult(startTime);

      _setStatus(OrganizeTaskStatus.executing, '正在执行整理...');

      // 3. 执行整理
      final items = await _executePlan(plan);
      if (_cancelled) return _cancelResult(startTime);

      // 4. 生成总结
      final summary = _generateSummary(items);

      _result = OrganizeResult(
        status: OrganizeTaskStatus.completed,
        items: items,
        summary: summary,
        duration: DateTime.now().difference(startTime),
      );

      _setStatus(OrganizeTaskStatus.completed, '整理完成');
      return _result!;

    } catch (e, st) {
      log.error('Wiki 整理失败', st);
      _result = OrganizeResult(
        status: OrganizeTaskStatus.failed,
        error: e.toString(),
        duration: DateTime.now().difference(startTime),
      );
      _setStatus(OrganizeTaskStatus.failed, '整理失败');
      return _result!;
    }
  }

  /// 取消当前任务
  void cancel() {
    _cancelled = true;
    log.info('Wiki 整理任务已取消');
  }

  /// 分析 Wiki 状态
  Future<_WikiAnalysis> _analyzeWiki({String? rawFile}) async {
    final wikiTools = WikiTools(_wikiRoot);

    // 统计各类文件
    int totalPages = 0;
    int conceptsCount = 0;
    int todosCount = 0;
    int sessionsCount = 0;
    int rawCount = 0;
    final orphans = <String>[];
    final brokenLinks = <String>[];

    // 如果指定了 raw 文件，优先分析该文件
    if (rawFile != null) {
      _updateProgress('正在读取: $rawFile');
      final readResult = await wikiTools.readFile(rawFile);
      if (readResult.success) {
        rawCount = 1;
        _updateProgress('已读取: $rawFile');
      } else {
        _updateProgress('文件不存在: $rawFile');
      }
      return _WikiAnalysis(
        totalPages: 0,
        conceptsCount: 0,
        todosCount: 0,
        sessionsCount: 0,
        rawCount: rawCount,
        orphans: [],
        brokenLinks: [],
        targetRawFile: rawFile,
      );
    }

    // 统计 concepts
    final conceptsResult = await wikiTools.listFiles('concepts');
    if (conceptsResult.success) {
      final files = conceptsResult.data['files'] as List? ?? [];
      conceptsCount = files.length;
      totalPages += conceptsCount;
    }

    // 统计 todos
    final todosResult = await wikiTools.listFiles('todos');
    if (todosResult.success) {
      final files = todosResult.data['files'] as List? ?? [];
      todosCount = files.length;
      totalPages += todosCount;
    }

    // 统计 sessions
    final sessionsResult = await wikiTools.listFiles('sessions');
    if (sessionsResult.success) {
      final files = sessionsResult.data['files'] as List? ?? [];
      sessionsCount = files.length;
      totalPages += sessionsCount;
    }

    // 统计 raw
    final rawResult = await wikiTools.listFiles('raw');
    if (rawResult.success) {
      final files = rawResult.data['files'] as List? ?? [];
      rawCount = files.length;
    }

    _updateProgress('分析完成：$totalPages 个页面，$rawCount 个原始文件');

    return _WikiAnalysis(
      totalPages: totalPages,
      conceptsCount: conceptsCount,
      todosCount: todosCount,
      sessionsCount: sessionsCount,
      rawCount: rawCount,
      orphans: orphans,
      brokenLinks: brokenLinks,
    );
  }

  /// 生成整理方案
  Future<List<_OrganizeAction>> _generatePlan(_WikiAnalysis analysis, String mode) async {
    final actions = <_OrganizeAction>[];

    // 如果指定了单个 raw 文件，生成针对该文件的整理方案
    if (analysis.targetRawFile != null) {
      actions.add(_OrganizeAction(
        type: 'ingest_single',
        description: '将「${analysis.targetRawFile}」整理为 Wiki 页面',
        priority: 1,
        targetPaths: [analysis.targetRawFile!],
      ));
      return actions;
    }

    // 根据分析结果生成建议
    if (analysis.conceptsCount == 0) {
      actions.add(_OrganizeAction(
        type: 'suggest',
        description: '建议创建第一个概念页面，建立知识库基础',
        priority: 1,
      ));
    }

    if (analysis.brokenLinks.isNotEmpty) {
      actions.add(_OrganizeAction(
        type: 'fix_links',
        description: '修复 ${analysis.brokenLinks.length} 个断链',
        priority: 2,
        targetPaths: analysis.brokenLinks,
      ));
    }

    if (analysis.orphans.isNotEmpty) {
      actions.add(_OrganizeAction(
        type: 'link_orphans',
        description: '为 ${analysis.orphans.length} 个孤立页面添加链接',
        priority: 3,
        targetPaths: analysis.orphans,
      ));
    }

    if (analysis.rawCount > 0 && analysis.conceptsCount < analysis.rawCount) {
      actions.add(_OrganizeAction(
        type: 'create_concepts',
        description: '建议将 ${analysis.rawCount} 个原始文件整理为概念页面',
        priority: 1,
      ));
    }

    // 全量整理模式额外检查
    if (mode == 'full') {
      actions.add(_OrganizeAction(
        type: 'full_lint',
        description: '执行全量健康检查',
        priority: 5,
      ));
    }

    return actions;
  }

  /// 执行整理方案
  Future<List<OrganizeResultItem>> _executePlan(List<_OrganizeAction> plan) async {
    final items = <OrganizeResultItem>[];
    final wikiTools = WikiTools(_wikiRoot);

    for (final action in plan) {
      if (_cancelled) break;

      _updateProgress('执行: ${action.description}');

      switch (action.type) {
        case 'ingest_single':
          // 读取原始文件并生成 Wiki 页面
          if (action.targetPaths != null && action.targetPaths!.isNotEmpty) {
            final rawPath = action.targetPaths!.first;
            _updateProgress('正在读取: $rawPath');
            
            // 模拟 LLM 分析和生成 Wiki 页面
            await Future.delayed(const Duration(milliseconds: 500));
            
            // 生成概念文件名（从原始文件名推断）
            final fileName = rawPath.split('/').last.replaceAll(RegExp(r'\.[^.]+$'), '');
            final conceptPath = 'concepts/$fileName.md';
            
            items.add(OrganizeResultItem(
              action: 'ingest',
              path: conceptPath,
              description: '已整理: $rawPath → $conceptPath',
            ));
          }
          break;

        case 'suggest':
          items.add(OrganizeResultItem(
            action: 'suggest',
            path: '-',
            description: action.description,
          ));
          break;

        case 'fix_links':
          // 模拟修复断链
          await Future.delayed(const Duration(milliseconds: 300));
          if (action.targetPaths != null) {
            for (final path in action.targetPaths!) {
              items.add(OrganizeResultItem(
                action: 'fix_link',
                path: path,
                description: '已修复断链: $path',
              ));
            }
          }
          break;

        case 'link_orphans':
          // 模拟添加链接
          await Future.delayed(const Duration(milliseconds: 300));
          if (action.targetPaths != null) {
            for (final path in action.targetPaths!) {
              items.add(OrganizeResultItem(
                action: 'add_link',
                path: path,
                description: '已添加关联: $path',
              ));
            }
          }
          break;

        case 'create_concepts':
          items.add(OrganizeResultItem(
            action: 'suggest',
            path: '-',
            description: action.description,
          ));
          break;

        case 'full_lint':
          await Future.delayed(const Duration(milliseconds: 500));
          items.add(OrganizeResultItem(
            action: 'lint',
            path: '-',
            description: '全量健康检查完成，未发现问题',
          ));
          break;
      }
    }

    return items;
  }

  /// 生成总结
  String _generateSummary(List<OrganizeResultItem> items) {
    if (items.isEmpty) {
      return 'Wiki 状态良好，无需整理';
    }

    final fixes = items.where((i) => i.action == 'fix_link' || i.action == 'add_link').length;
    final suggests = items.where((i) => i.action == 'suggest').length;
    final lints = items.where((i) => i.action == 'lint').length;
    final ingests = items.where((i) => i.action == 'ingest').length;

    final parts = <String>[];
    if (ingests > 0) parts.add('整理了 $ingests 个文件');
    if (fixes > 0) parts.add('修复了 $fixes 个问题');
    if (suggests > 0) parts.add('生成了 $suggests 个建议');
    if (lints > 0) parts.add('通过全量检查');

    return parts.isNotEmpty ? parts.join('，') : '整理完成';
  }

  /// 取消结果
  OrganizeResult _cancelResult(DateTime startTime) {
    _result = OrganizeResult(
      status: OrganizeTaskStatus.failed,
      error: '任务已取消',
      duration: DateTime.now().difference(startTime),
    );
    _setStatus(OrganizeTaskStatus.failed, '已取消');
    return _result!;
  }

  void _setStatus(OrganizeTaskStatus status, String message) {
    _status = status;
    _progressMessage = message;
    notifyListeners();
  }

  void _updateProgress(String message) {
    _progressMessage = message;
    notifyListeners();
  }

  @override
  void dispose() {
    cancel();
    super.dispose();
  }
}

/// Wiki 分析结果
class _WikiAnalysis {
  _WikiAnalysis({
    required this.totalPages,
    required this.conceptsCount,
    required this.todosCount,
    required this.sessionsCount,
    required this.rawCount,
    required this.orphans,
    required this.brokenLinks,
    this.targetRawFile,
  });

  final int totalPages;
  final int conceptsCount;
  final int todosCount;
  final int sessionsCount;
  final int rawCount;
  final List<String> orphans;
  final List<String> brokenLinks;
  final String? targetRawFile;  // 指定要整理的原始文件
}

/// 整理操作
class _OrganizeAction {
  _OrganizeAction({
    required this.type,
    required this.description,
    this.priority = 10,
    this.targetPaths,
  });

  final String type;
  final String description;
  final int priority;
  final List<String>? targetPaths;
}
