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

  /// 把用户输入的相对路径（wiki/{profile,todos,concepts,...}/*.md）
  /// 解析为绝对路径，并校验白名单。
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

    // 统一前缀 wiki/
    String normalized = input.trim().replaceAll(RegExp(r'\\'), '/');
    if (!normalized.startsWith('wiki/') && normalized != 'wiki') {
      throw FileToolException('路径必须以 `wiki/` 开头', code: 'outside_wiki');
    }
    final relative = normalized.substring('wiki/'.length);

    // 检查黑名单（敏感文件）
    final blacklisted = _alwaysBlacklisted(relative);
    if (blacklisted) {
      throw FileToolException('不允许操作此文件', code: 'blacklisted');
    }

    // 检查写操作白名单（profile / todos / concepts）
    if (op == FileOp.write || op == FileOp.append || op == FileOp.edit) {
      if (!_writable(relative)) {
        throw FileToolException(
          '此路径不允许写入（仅允许 wiki/profile.md、wiki/todos/todo-{uuid}.md 与 wiki/concepts/*.md）',
          code: 'not_writable',
        );
      }
    }
    // 读操作白名单：wiki 下所有非黑名单 .md
    if (op == FileOp.read || op == FileOp.list) {
      if (!_readable(relative)) {
        throw FileToolException(
          '此路径不允许读取',
          code: 'not_readable',
        );
      }
    }

    // 拼绝对路径（root 已是 .owl/wiki/，normalized 含 wiki/ 前缀需去掉）
    final root = await _ensureRootPath();
    if (root == null || root.isEmpty) {
      throw FileToolException(
        'FileTools 未设置根目录，且 WikiRepository 无法获取根路径',
        code: 'no_root',
      );
    }
    final absolute = p.normalize(p.join(root, relative));
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
    } catch (_) {
      // ignore
    }
    return _rootPath;
  }

  /// 设置 Wiki 根目录绝对路径（由 ChatController 启动时注入）
  void setRootPath(String path) {
    _rootPath = path;
  }

  // ───────────────────────── 路径白名单 ─────────────────────────

  /// 读写全黑名单（绝对敏感：API Key / 应用设置 / 会话历史 / 私有目录）
  /// 这些文件 LLM 既不能读也不能写
  bool _alwaysBlacklisted(String relative) {
    return relative == 'context-settings.md' ||
        relative == 'api-configs.md' ||
        relative.startsWith('sessions/') ||
        relative.startsWith('sessions\\') ||
        relative.startsWith('.archive') ||
        relative.startsWith('.meta') ||
        relative.startsWith('.backup');
  }

  /// 写入黑名单（在读黑名单基础上额外禁止覆盖 index/schema）
/// index/schema 是知识库骨架。
/// profile.md 允许写入（AI 根据对话维护用户画像）。
/// todos/todo-{uuid}.md / concepts/*.md 允许写入。
bool _writeBlacklisted(String relative) {
  if (_alwaysBlacklisted(relative)) return true;
  return relative == 'index.md' || relative == 'schema.md';
}

/// 读操作白名单：除绝对黑名单外的所有 wiki/* 子路径
/// （profile.md / index.md / schema.md / todos/* / concepts/* 均可读）
bool _readable(String relative) {
  if (relative.isEmpty) return true; // list_files("wiki")
  return !_alwaysBlacklisted(relative);
}

/// 写操作白名单（v5）：
/// - profile.md（用户画像）
/// - todos/todo-{uuid}.md（多文件待办）
/// - concepts/*.md（长期知识）
bool _writable(String relative) {
  if (_writeBlacklisted(relative)) return false;
  if (relative == 'profile.md') return true;
  if (relative.startsWith('todos/') &&
      RegExp(r'^todos/todo-[a-f0-9-]+\.md$').hasMatch(relative)) {
    return true;
  }
  if (relative.startsWith('concepts/') && relative.endsWith('.md')) return true;
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

  /// list_files：列出 wiki 下某子目录的 .md 文件
  Future<String> listFiles(String dir) async {
    final normalized = dir.trim().replaceAll(RegExp(r'\\'), '/');

    // 仍要校验是否在白名单子目录内
    final rel = normalized.startsWith('wiki/')
        ? normalized.substring('wiki/'.length)
        : normalized;
    if (!_readable(rel) && rel.isNotEmpty) {
      throw FileToolException('不允许列出此目录', code: 'not_readable');
    }

    final root = await _ensureRootPath();
    if (root == null || root.isEmpty) {
      throw FileToolException('FileTools 根目录未设置', code: 'no_root');
    }
    final absolute = p.normalize(p.join(root, normalized));

    final dirFile = Directory(absolute);
    if (!await dirFile.exists()) return '[]';
    final files = await dirFile
        .list(recursive: rel.isEmpty ? false : false)
        .where((e) => e is File && e.path.endsWith('.md'))
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