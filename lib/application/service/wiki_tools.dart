/// Wiki 知识库专用工具
///
/// 在代码层面强制执行 Wiki 规范：
/// - 写入操作限制在 .owl/wiki/ 目录下
/// - 读取操作支持 .owl 下的所有文件
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/core.dart';
import '../../data/data.dart';
import 'wiki_file_writer.dart';
import 'wiki_lock_service.dart';

/// Wiki 工具执行结果
class WikiToolResult {
  WikiToolResult({
    required this.success,
    this.data,
    this.error,
    this.warnings = const [],
  });

  final bool success;
  final dynamic data;
  final String? error;
  final List<String> warnings;  // 警告信息（如自动修正）

  factory WikiToolResult.ok(dynamic data, {List<String>? warnings}) =>
      WikiToolResult(success: true, data: data, warnings: warnings ?? []);

  factory WikiToolResult.err(String error) =>
      WikiToolResult(success: false, error: error);
}

/// Wiki 页面创建/更新参数
class WikiPageParams {
  WikiPageParams({
    required this.title,
    required this.content,
    this.description = '',
    this.entityType = 'concept',
    this.sources = const [],
    this.weight = 10,
    this.status = 'active',
    this.contradictions = const [],
    this.parentLinks = const [],  // 关联的父页面
  });

  /// 显示名称（中文）
  final String title;

  /// 内容摘要（≤ 200 字）
  final String description;

  /// 实体类型：concept/person/product/process/event
  final String entityType;

  /// 引用来源列表（raw 文件路径）
  final List<String> sources;

  /// 排序权重
  final int weight;

  /// 状态：active/archived/pending_review
  final String status;

  /// 冲突关联页面
  final List<String> contradictions;

  /// 关联的父页面（用于生成双向链接）
  final List<String> parentLinks;

  /// 正文内容
  final String content;
}

/// Wiki 知识库工具
///
/// 提供规范化、安全的 Wiki 操作接口
class WikiTools {
  WikiTools(this._root);

  /// .owl 根目录路径
  final String _root;

  /// .owl/wiki/ 目录路径（写入限制）
  String get _wikiRoot => p.join(_root, 'wiki');

  /// 验证并转换路径为 wiki/ 相对路径
  ///
  /// 写入操作必须限制在 wiki/ 目录下
  String? _toWikiPath(String path) {
    // 如果路径已包含 wiki/ 前缀，直接使用相对路径
    if (path.startsWith('wiki/')) {
      return path;
    }
    // 否则添加 wiki/ 前缀
    return 'wiki/$path';
  }

  /// 检查路径是否为 wiki/ 目录下的路径
  bool _isWikiPath(String path) {
    return path.startsWith('wiki/') || path == 'wiki';
  }

  /// 读取文件并返回带显示名称的结果
  ///
  /// 读取操作支持 .owl 下的所有文件（wiki/、raw/、sessions/、config/ 等）
  Future<WikiToolResult> readFile(String path) async {
    try {
      // 解析路径，确定是哪个子目录
      final resolvedPath = _resolveOwlPath(path);
      if (resolvedPath == null) {
        return WikiToolResult.err('文件路径无效: $path');
      }

      final file = File(resolvedPath);
      if (!await file.exists()) {
        return WikiToolResult.err('文件不存在: $path');
      }

      final content = await file.readAsString();
      final fileName = p.basename(path);
      final extension = p.extension(path).toLowerCase();
      final relativePath = p.relative(resolvedPath, from: _root);

      // 根据文件类型返回不同的显示信息
      final data = <String, dynamic>{
        'path': path,
        'relativePath': relativePath,
        'fileName': fileName,
        'displayName': fileName,
        'extension': extension,
        'size': await file.length(),
        'content': content,
      };

      // 对于 Wiki 文件（.owl/wiki/），尝试解析 front-matter
      if (relativePath.startsWith('wiki/') && extension == '.md') {
        try {
          final wikiFile = await _readWikiFile(relativePath);
          data['displayName'] = wikiFile.frontMatter.title;
          data['title'] = wikiFile.frontMatter.title;
          data['description'] = wikiFile.frontMatter.description;
          data['content'] = wikiFile.body;
          data['frontMatter'] = {
            'title': wikiFile.frontMatter.title,
            'description': wikiFile.frontMatter.description,
            'weight': wikiFile.frontMatter.weight,
            'updatedAt': wikiFile.frontMatter.updatedAt.toIso8601String(),
            'entityType': wikiFile.frontMatter.extras['entity_type'],
            'sources': wikiFile.frontMatter.extras['sources'],
            'status': wikiFile.frontMatter.extras['status'],
          };
        } catch (_) {
          // 非标准 Wiki 文件，返回基本信息
          data['displayName'] = fileName;
        }
      }

      log.info('读取文件: $relativePath');
      return WikiToolResult.ok(data);

    } catch (e) {
      log.error('读取文件失败: $path', StackTrace.current);
      return WikiToolResult.err('读取失败: $e');
    }
  }

  /// 解析 .owl 下的文件路径
  ///
  /// 支持以下格式：
  /// - `wiki/xxx.md` → `.owl/wiki/xxx.md`
  /// - `raw/xxx.pdf` → `.owl/raw/xxx.pdf`
  /// - `sessions/xxx.jsonl` → `.owl/sessions/xxx.jsonl`
  /// - `config/xxx.json` → `.owl/config/xxx.json`
  String? _resolveOwlPath(String path) {
    // 清理路径
    String cleanPath = path.replaceAll(RegExp(r'^/+'), '');

    // 检查是否已经是 .owl 下的路径
    if (cleanPath.startsWith('wiki/') ||
        cleanPath.startsWith('raw/') ||
        cleanPath.startsWith('sessions/') ||
        cleanPath.startsWith('config/') ||
        cleanPath.startsWith('agents/')) {
      return p.join(_root, cleanPath);
    }

    // 没有子目录前缀，默认添加到 wiki/
    return p.join(_root, 'wiki', cleanPath);
  }

  /// 读取原始文件（支持整个手机存储）
  ///
  /// 用于 LLM 分析外部原始资料，可以读取 Wiki 目录之外的文件
  Future<WikiToolResult> readRawFile(String path) async {
    try {
      // 支持绝对路径和相对路径
      String filePath = path;
      if (!p.isAbsolute(path)) {
        // 如果是相对路径，尝试多个基础路径
        final candidates = [
          path,
          p.join(_root, 'raw', path),
          p.join(_root, path),
          '/storage/emulated/0/$path',  // Android 公共存储
          '/storage/emulated/0/Download/$path',  // 下载目录
          '/storage/emulated/0/Documents/$path',  // 文档目录
        ];

        for (final candidate in candidates) {
          if (await File(candidate).exists()) {
            filePath = candidate;
            break;
          }
        }
      }

      final file = File(filePath);
      if (!await file.exists()) {
        return WikiToolResult.err('文件不存在: $path');
      }

      // 检查文件大小（限制 10MB）
      final stat = await file.stat();
      if (stat.size > 10 * 1024 * 1024) {
        return WikiToolResult.err('文件过大（> 10MB）: ${stat.size ~/ (1024 * 1024)} MB');
      }

      final content = await file.readAsString();
      final fileName = p.basename(path);
      final extension = p.extension(path).toLowerCase();

      // 根据文件类型返回不同的显示信息
      final result = <String, dynamic>{
        'path': path,
        'fileName': fileName,
        'displayName': fileName,
        'extension': extension,
        'size': stat.size,
        'content': content,
        'contentPreview': _truncate(content, 500),
      };

      // 对于 Markdown 文件，尝试提取标题
      if (extension == '.md') {
        final firstLine = content.split('\n').firstWhere(
          (line) => line.trim().isNotEmpty,
          orElse: () => '',
        );
        if (firstLine.startsWith('#')) {
          result['title'] = firstLine.replaceFirst(RegExp(r'^#+\s*'), '').trim();
        }
      }

      log.info('读取原始文件: $path (${stat.size} bytes)');
      return WikiToolResult.ok(result);

    } catch (e) {
      log.error('读取原始文件失败: $path', StackTrace.current);
      return WikiToolResult.err('读取失败: $e');
    }
  }

  /// 列出手机存储中的文件（用于选择原始资料）
  Future<WikiToolResult> listRawDirectory(String path) async {
    try {
      // 支持的搜索目录
      final searchDirs = <String>[];

      if (path.isEmpty || path == '/') {
        // 根目录，显示可用的存储位置
        searchDirs.addAll([
          p.join(_root, 'raw'),
          '/storage/emulated/0/Download',
          '/storage/emulated/0/Documents',
          '/storage/emulated/0',
        ]);
      } else {
        searchDirs.add(path);
      }

      final allFiles = <Map<String, dynamic>>[];

      for (final dirPath in searchDirs) {
        final dir = Directory(dirPath);
        if (!await dir.exists()) continue;

        await for (final entity in dir.list()) {
          if (entity is File) {
            final ext = p.extension(entity.path).toLowerCase();
            // 只显示可读的文件类型
            if (_isReadableFile(ext)) {
              final stat = await entity.stat();
              allFiles.add({
                'path': entity.path,
                'name': p.basename(entity.path),
                'extension': ext,
                'size': stat.size,
                'modifiedAt': stat.modified.toIso8601String(),
              });
            }
          }
        }
      }

      // 按修改时间排序
      allFiles.sort((a, b) {
        final aTime = DateTime.tryParse(a['modifiedAt'] ?? '') ?? DateTime(1970);
        final bTime = DateTime.tryParse(b['modifiedAt'] ?? '') ?? DateTime(1970);
        return bTime.compareTo(aTime);
      });

      return WikiToolResult.ok({
        'files': allFiles.take(100).toList(),  // 最多返回 100 个文件
        'count': allFiles.length,
        'searchDirs': searchDirs,
      });

    } catch (e) {
      log.error('列出目录失败: $path', StackTrace.current);
      return WikiToolResult.err('列出目录失败: $e');
    }
  }

  /// 检查文件是否可读
  bool _isReadableFile(String ext) {
    const readableExtensions = [
      '.md', '.txt', '.pdf', '.doc', '.docx',
      '.json', '.yaml', '.yml', '.xml',
      '.csv', '.log', '.html', '.htm',
      '.java', '.kt', '.swift', '.py', '.js', '.ts',
      '.dart', '.go', '.rs', '.c', '.cpp', '.h',
    ];
    return readableExtensions.contains(ext) || ext.isEmpty;
  }

  /// 创建/更新 Wiki 页面
  ///
  /// 写入操作限制在 .owl/wiki/ 目录下
  Future<WikiToolResult> writeFile(String path, WikiPageParams params) async {
    try {
      // 1. 标准化路径：去除 wiki/ 前缀用于验证
      String fileName = path;
      if (path.startsWith('wiki/')) {
        fileName = path.substring('wiki/'.length);
      }

      // 2. 验证文件名规范
      final validatedPath = _validatePath(fileName);
      if (validatedPath == null) {
        return WikiToolResult.err(
          '文件名不规范：必须使用英文小写、中划线、.md 后缀\n'
          '例如：ai-assistant.md, project-management.md'
        );
      }

      // 3. 强制添加 wiki/ 前缀（写入限制）
      final wikiPath = 'wiki/$validatedPath';

      // 4. 生成 front-matter（强制规范）
      final frontMatter = WikiFrontMatter(
        title: params.title,
        description: params.description.isNotEmpty
            ? params.description
            : _truncate(params.content, 200),
        weight: params.weight,
        updatedAt: DateTime.now().toUtc(),
        extras: {
          'entity_type': params.entityType,
          'sources': params.sources,
          'status': params.status,
          'contradictions': params.contradictions,
        },
      );

      // 4. 组装页面内容
      final wikiFile = WikiFile(
        frontMatter: frontMatter,
        body: _buildBody(
          title: params.title,
          content: params.content,
          sources: params.sources,
          parentLinks: params.parentLinks,
        ),
        relativePath: wikiPath,
      );

      // 5. 写入文件（使用 WikiFileWriter 保证原子性）
      final lockService = WikiLockService(_root);
      final writer = WikiFileWriter(
        wikiRoot: _root,
        lockService: lockService,
      );
      final kind = _inferKind(wikiPath);
      await writer.write(kind, wikiFile);

      log.info('Wiki 页面已更新: $validatedPath (title: ${params.title})');

      return WikiToolResult.ok({
        'path': validatedPath,
        'displayName': params.title,
        'frontMatter': frontMatter.serialize(),
      }, warnings: _checkLinks(wikiFile.body));

    } catch (e) {
      log.error('写入 Wiki 文件失败: $path', StackTrace.current);
      return WikiToolResult.err('写入失败: $e');
    }
  }

  /// 列出目录文件
  ///
  /// 支持列出 .owl 下各个子目录：
  /// - `wiki/` - Wiki 知识库页面
  /// - `raw/` - 原始文件
  /// - `sessions/` - 会话数据
  /// - `config/` - 配置数据
  Future<WikiToolResult> listFiles(String path) async {
    try {
      // 解析路径
      String dirPath;
      if (path.isEmpty || path == '/') {
        // 列出 .owl 根目录下的所有子目录
        final dirs = <Map<String, dynamic>>[];
        for (final subDir in ['wiki', 'raw', 'sessions', 'config']) {
          final fullPath = p.join(_root, subDir);
          if (await Directory(fullPath).exists()) {
            final count = await Directory(fullPath).list().length;
            dirs.add({
              'path': subDir,
              'name': subDir,
              'type': 'directory',
              'count': count,
            });
          }
        }
        return WikiToolResult.ok({'items': dirs, 'type': 'directories'});
      }

      // 列出指定子目录的文件
      dirPath = p.join(_root, path);
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        return WikiToolResult.ok({'items': [], 'count': 0, 'type': 'files'});
      }

      final entities = await dir.list().toList();
      final files = <Map<String, dynamic>>[];

      for (final entity in entities) {
        if (entity is File) {
          final relativePath = p.relative(entity.path, from: _root);
          final ext = p.extension(entity.path).toLowerCase();

          if (path == 'wiki' && ext == '.md') {
            // Wiki 目录，尝试解析 front-matter
            try {
              final file = await _readWikiFile(relativePath);
              files.add({
                'path': relativePath,
                'displayName': file.frontMatter.title,
                'description': file.frontMatter.description,
                'weight': file.frontMatter.weight,
                'updatedAt': file.frontMatter.updatedAt.toIso8601String(),
                'type': 'file',
              });
            } catch (_) {
              files.add({
                'path': relativePath,
                'displayName': p.basenameWithoutExtension(relativePath),
                'type': 'file',
              });
            }
          } else {
            // 其他目录，返回基本信息
            files.add({
              'path': relativePath,
              'displayName': p.basename(entity.path),
              'name': p.basename(entity.path),
              'extension': ext,
              'type': 'file',
            });
          }
        } else if (entity is Directory) {
          // 子目录
          final relativePath = p.relative(entity.path, from: _root);
          final count = await entity.list().length;
          files.add({
            'path': relativePath,
            'name': p.basename(entity.path),
            'type': 'directory',
            'count': count,
          });
        }
      }

      return WikiToolResult.ok({
        'items': files,
        'count': files.length,
        'type': 'files',
        'currentPath': path,
      });
    } catch (e) {
      log.error('列出文件失败: $path', StackTrace.current);
      return WikiToolResult.err('列出文件失败: $e');
    }
  }

  /// 搜索文件内容
  ///
  /// 在 .owl 目录下搜索，支持 wiki/、raw/ 等子目录
  Future<WikiToolResult> searchFiles(String query, {String? path}) async {
    try {
      // 确定搜索路径
      String searchPath;
      if (path == null || path.isEmpty) {
        // 搜索整个 .owl 目录
        searchPath = _root;
      } else if (path.startsWith('/')) {
        // 绝对路径
        searchPath = path;
      } else {
        // 相对路径
        searchPath = p.join(_root, path);
      }

      final results = <Map<String, dynamic>>[];

      await for (final entity in Directory(searchPath).list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.md')) {
          final content = await entity.readAsString();
          if (content.toLowerCase().contains(query.toLowerCase())) {
            final relativePath = p.relative(entity.path, from: _root);
            results.add({
              'path': relativePath,
              'snippet': _extractSnippet(content, query),
            });
          }
        }
      }

      return WikiToolResult.ok({'results': results, 'count': results.length});
    } catch (e) {
      return WikiToolResult.err('搜索失败: $e');
    }
  }

  // ─────────────────────────────────────────────
  // 私有辅助方法
  // ─────────────────────────────────────────────

  String? _validatePath(String path) {
    if (!path.endsWith('.md')) return null;
    if (RegExp(r'[\s\u4e00-\u9fff]').hasMatch(path)) return null;
    if (path.startsWith('/') || path.contains('..')) return null;
    return path;
  }

  WikiFileKind _inferKind(String path) {
    if (path.startsWith('todos/')) return WikiFileKind.todo;
    if (path.startsWith('sessions/')) return WikiFileKind.session;
    if (path.startsWith('concepts/')) return WikiFileKind.concept;
    if (path == 'profile.md') return WikiFileKind.profile;
    return WikiFileKind.unknown;
  }

  String _buildBody({
    required String title,
    required String content,
    required List<String> sources,
    required List<String> parentLinks,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('# $title\n');
    buffer.writeln(content);
    buffer.writeln();

    if (parentLinks.isNotEmpty) {
      buffer.writeln('## 相关页面\n');
      for (final link in parentLinks) {
        buffer.writeln('- [[$link]]');
      }
      buffer.writeln();
    }

    if (sources.isNotEmpty) {
      buffer.writeln('## 溯源\n');
      for (final source in sources) {
        final time = DateTime.now().toIso8601String().substring(0, 19);
        buffer.writeln('> 来源：$source | 摄入时间：$time');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  String _truncate(String text, int maxLen) {
    if (text.length <= maxLen) return text;
    return '${text.substring(0, maxLen)}...';
  }

  List<String> _checkLinks(String content) {
    final warnings = <String>[];
    final links = RegExp(r'\[\[([^\]|]+)\]\]').allMatches(content);
    for (final link in links) {
      final target = link.group(1)!;
      if (!target.endsWith('.md')) {
        warnings.add('链接应使用完整文件名（含 .md 后缀）: [[$target]]');
      }
    }
    return warnings;
  }

  Future<WikiFile> _readWikiFile(String path) async {
    final absPath = p.join(_root, path);
    final file = File(absPath);
    if (!await file.exists()) {
      throw Exception('文件不存在: $path');
    }
    final content = await file.readAsString();
    return WikiFile.fromMarkdown(content, path);
  }

  String _extractSnippet(String content, String query) {
    final idx = content.toLowerCase().indexOf(query.toLowerCase());
    if (idx < 0) return '';
    final start = (idx - 50).clamp(0, content.length);
    final end = (idx + query.length + 100).clamp(0, content.length);
    return '...${content.substring(start, end)}...';
  }
}
