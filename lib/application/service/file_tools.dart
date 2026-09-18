/// 文件工具服务（LLM 可调用的文件操作集合）。
///
/// 职责：
/// - 提供 5 个工具：`read_file` / `write_file` / `append_file` / `edit_file` / `list_files`
/// - 强制路径白名单（只允许 `.owl/wiki/` 下的特定子目录）
/// - 原子写入（写 .tmp → rename）+ 1MB 限制
/// - 失败时抛出结构化异常（[FileToolException]）
///
/// 安全原则：
/// - 黑名单优先：任何含 `..` / 绝对路径 / 非法字符的输入一律拒绝
/// - 不允许写入敏感文件（settings/api/profile/sessions）
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../data/repository/i_wiki_repository.dart';

/// 文件工具执行异常
class FileToolException implements Exception {
  FileToolException(this.message, {this.code = 'file_tool_error'});

  final String message;
  final String code;

  @override
  String toString() => '[$code] $message';
}

/// 文件工具集
///
/// 通过 [execute] 入口按 name 分发到对应实现。
/// 每个工具的入参 schema 由 [ToolRegistry] 维护。
class FileTools {
  FileTools(this._wiki);

  final IWikiRepository _wiki;

  /// 工具目录根（绝对路径）
  String? _rootPath;

  // ───────────────────────── 路径校验 ─────────────────────────

  /// 把用户输入的相对路径解析为绝对路径
  ///
  /// 支持整个 .owl 目录的操作：
  /// - wiki/ - Wiki 知识库页面
  /// - raw/ - 原始文件
  /// - sessions/ - 会话数据
  /// - config/ - 配置数据
  ///
  /// 不做任何限制，仅保留黑名单保护（API Key、敏感配置）
  Future<File> _resolveAllowedPath(String input, FileOp op) async {
    if (input.isEmpty) {
      throw FileToolException('路径不能为空', code: 'empty_path');
    }
    if (input.contains('..')) {
      throw FileToolException('路径不允许包含 `..`', code: 'parent_dir');
    }
    if (p.isAbsolute(input)) {
      throw FileToolException('不允许使用绝对路径', code: 'absolute_path');
    }

    // 标准化路径
    String normalized = input.trim().replaceAll(RegExp(r'\\'), '/');

    // 检查黑名单（敏感文件：API Key、应用配置等）
    final blacklisted = _alwaysBlacklisted(normalized);
    if (blacklisted) {
      throw FileToolException('不允许操作此文件', code: 'blacklisted');
    }

    // 拼绝对路径（基于 .owl 根目录）
    final root = await _ensureRootPath();
    if (root == null || root.isEmpty) {
      throw FileToolException(
        'FileTools 未设置根目录，且 WikiRepository 无法获取根路径',
        code: 'no_root',
      );
    }

    // 如果路径已包含子目录前缀（wiki/、raw/ 等），直接使用
    // 否则默认添加到 wiki/
    String absolute;
    if (normalized.startsWith('wiki/') ||
        normalized.startsWith('raw/') ||
        normalized.startsWith('sessions/') ||
        normalized.startsWith('config/') ||
        normalized.startsWith('agents/')) {
      absolute = p.normalize(p.join(root, normalized));
    } else {
      // 默认添加到 wiki/
      absolute = p.normalize(p.join(root, 'wiki', normalized));
    }

    return File(absolute);
  }

  /// 确保根路径已设置。优先使用外部注入（[setRootPath]），否则从 WikiRepository 异步获取。
  Future<String?> _ensureRootPath() async {
    if (_rootPath != null && _rootPath!.isNotEmpty) return _rootPath;
    try {
      final root = await _wiki.getRootPath();
      if (root.isNotEmpty) {
        _rootPath = root;
      }
    } catch (e) {
      // 获取根路径失败，将在后续操作中处理
    }
    return _rootPath;
  }

  /// 设置 Wiki 根目录绝对路径（由 ChatController 启动时注入）
  void setRootPath(String path) {
    _rootPath = path;
  }

  // ───────────────────────── 路径黑名单 ─────────────────────────

  /// 读写全黑名单（绝对敏感：API Key / 应用设置 / 私有目录）
  /// 这些文件 LLM 既不能读也不能写
  bool _alwaysBlacklisted(String relative) {
    // 清理路径
    String clean = relative.replaceAll(RegExp(r'^/+'), '');

    // 检查 .owl 下的敏感文件
    if (clean == 'config/api-configs.jsonl') return true;
    if (clean == 'config/settings.jsonl') return true;
    if (clean == '.archive') return true;
    if (clean.startsWith('.archive/')) return true;
    if (clean == '.meta') return true;
    if (clean.startsWith('.meta/')) return true;
    if (clean == '.backup') return true;
    if (clean.startsWith('.backup/')) return true;
    if (clean == '.lock') return true;

    return false;
  }

  // ───────────────────────── 工具实现 ─────────────────────────

  /// read_file：读取 wiki 路径文件（自动容错：文件不存在时自动创建空文件）
  Future<String> readFile(String path) async {
    final file = await _resolveAllowedPath(path, FileOp.read);
    if (!await file.exists()) {
      // 容错：自动创建空文件（带默认模板），让 LLM 知道文件存在但内容为空
      await _autoCreateEmptyFile(file, path);
      return _defaultContentFor(path);
    }
    if (await file.length() > _maxBytes) {
      throw FileToolException(
        '文件超过 ${_maxBytes ~/ 1024}KB 限制',
        code: 'too_large',
      );
    }
    return file.readAsString();
  }

  /// write_file：完整覆盖写入
  Future<String> writeFile(String path, String content) async {
    final file = await _resolveAllowedPath(path, FileOp.write);
    if (content.length > _maxBytes) {
      throw FileToolException(
        '内容超过 ${_maxBytes ~/ 1024}KB 限制',
        code: 'content_too_large',
      );
    }
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    // 原子写入：写 .tmp 后 rename
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await tmp.rename(file.path);
    return '已写入 ${content.length} 字节到 ${path}';
  }

  /// append_file：追加内容
  Future<String> appendFile(String path, String content) async {
    final file = await _resolveAllowedPath(path, FileOp.append);
    final exists = await file.exists();
    final current = exists ? await file.readAsString() : '';
    final combined = current + content;
    if (combined.length > _maxBytes) {
      throw FileToolException(
        '追加后超过 ${_maxBytes ~/ 1024}KB 限制',
        code: 'content_too_large',
      );
    }
    if (!exists) {
      final parent = file.parent;
      if (!await parent.exists()) await parent.create(recursive: true);
    }
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(combined, flush: true);
    if (exists) await file.delete();
    await tmp.rename(file.path);
    return '已追加 ${content.length} 字节到 ${path}（当前 ${combined.length} 字节）';
  }

  /// edit_file：基于 search/replace 的精确替换
  ///
  /// 容错：文件不存在时自动创建空文件（等同于 append_file）。
  Future<String> editFile(String path, String search, String replace) async {
    final file = await _resolveAllowedPath(path, FileOp.edit);
    if (!await file.exists()) {
      // 容错：文件不存在 → 先创建再追加新内容
      await _autoCreateEmptyFile(file, path);
      final combined = '$replace\n';
      if (combined.length > _maxBytes) {
        throw FileToolException(
          '内容超过 ${_maxBytes ~/ 1024}KB 限制',
          code: 'content_too_large',
        );
      }
      await file.writeAsString(combined, flush: true);
      return '文件不存在已自动创建，并写入 ${replace.length} 字节';
    }
    final current = await file.readAsString();
    if (!current.contains(search)) {
      throw FileToolException(
        '未找到要替换的内容。请先 read_file 查看原文。',
        code: 'search_not_found',
      );
    }
    final updated = current.replaceFirst(search, replace);
    if (updated.length > _maxBytes) {
      throw FileToolException(
        '编辑后超过 ${_maxBytes ~/ 1024}KB 限制',
        code: 'content_too_large',
      );
    }
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(updated, flush: true);
    await file.delete();
    await tmp.rename(file.path);
    return '已替换 1 处（${search.length} → ${replace.length} 字节）';
  }

  /// list_files：列出 .owl 目录下指定子目录的文件
  ///
  /// 支持列出 wiki/、raw/、sessions/、config/ 等子目录
  Future<String> listFiles(String dir) async {
    final normalized = dir.trim().replaceAll(RegExp(r'\\'), '/');

    // 标准化路径：添加子目录前缀或默认到 wiki/
    String searchPath;
    if (normalized.isEmpty || normalized == '/') {
      searchPath = '';
    } else if (normalized.startsWith('wiki/') ||
               normalized.startsWith('raw/') ||
               normalized.startsWith('sessions/') ||
               normalized.startsWith('config/')) {
      searchPath = normalized;
    } else {
      searchPath = 'wiki/$normalized';
    }

    final root = await _ensureRootPath();
    if (root == null || root.isEmpty) {
      throw FileToolException('FileTools 根目录未设置', code: 'no_root');
    }
    final absolute = p.normalize(p.join(root, searchPath));

    final dirFile = Directory(absolute);
    if (!await dirFile.exists()) return '[]';

    // 如果是列出根目录，返回子目录列表
    if (searchPath.isEmpty) {
      final subDirs = <String>[];
      await for (final entity in dirFile.list()) {
        if (entity is Directory) {
          final name = p.basename(entity.path);
          if (!name.startsWith('.')) {
            subDirs.add(name);
          }
        }
      }
      subDirs.sort();
      return subDirs.toString();
    }

    // 否则列出目录下的文件（不递归）
    final files = await dirFile
        .list(recursive: false)
        .where((e) => e is File)
        .map((e) => p.relative(e.path, from: root))
        .toList();
    files.sort();
    return files.toString();
  }

  // ───────────────────────── 限制 ─────────────────────────

  static const int _maxBytes = 1024 * 1024; // 1MB

  // ───────────────────────── 容错辅助 ─────────────────────────

  /// 自动创建空文件（带默认模板），让 LLM 后续 append/edit 有起点
  Future<void> _autoCreateEmptyFile(File file, String originalPath) async {
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    final tpl = _defaultContentFor(originalPath);
    if (tpl.trim().isNotEmpty) {
      await file.writeAsString(tpl, flush: true);
    }
  }

  /// 根据路径返回默认模板内容（仅初始化时用一次，后续 append/edit 由 LLM 主导）
  String _defaultContentFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('profile.md')) {
      return '# 用户画像\n\n'
          '> 此文件由 AI 根据对话自动维护，记录用户的个人基础信息与偏好。\n\n'
          '## 基础信息\n\n'
          '- 姓名：\n'
          '- 称呼：\n\n'
          '## 偏好设定\n\n'
          '- 沟通风格：\n'
          '- 关注领域：\n\n';
    }
    if (RegExp(r'todos/todo-[a-f0-9-]+\.md').hasMatch(lower)) {
      // 单个 todo 文件：返回最小可写 body（不含 front-matter 块）
      return '# 待办\n\n'
          '## 背景\n\n（待补充）\n\n'
          '## 子任务\n\n- [ ] 待办\n';
    }
    if (lower.contains('/concepts/')) {
      final name = path.split('/').last.replaceAll('.md', '');
      return '# ${name.isEmpty ? '未命名' : name}\n\n'
          '> 这里是一个知识页面，主题：${name}。\n\n';
    }
    return '';
  }
}

enum FileOp { read, write, append, edit, list }