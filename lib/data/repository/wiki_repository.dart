import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../application/parser/api_configs_parser.dart';
import '../../application/parser/context_settings_parser.dart';
import '../../application/service/wiki_file_writer.dart';
import '../../application/service/wiki_lock_service.dart';
import '../../core/model/wiki_file.dart';
import '../../core/model/wiki_front_matter.dart';
import '../../core/util/talker_service.dart';
import 'i_wiki_repository.dart';

/// Wiki 知识库仓库的文件系统实现（v5.0）
///
/// 目录结构（跨平台）：
/// - **Android**：`<手机存储根目录>/.owl/wiki/`
///   （即 `/storage/emulated/0/.owl/wiki/`，与 `Documents/` 等系统目录平级；
///    Android 11+ 需要 `MANAGE_EXTERNAL_STORAGE` 权限并引导用户去设置手动授权）
/// - **iOS**：应用沙盒 `<AppDocuments>/.owl/wiki/`
///   （iOS 沙盒限制无法写到公共目录，路径仍为应用专属）
/// - **Windows / macOS / Linux**：用户主目录 `~/Documents/Owl/.owl/wiki/`
///   （跨平台统一的"我的文档"路径，桌面平台无权限问题）
///
/// 子目录：
/// - `.meta/`（私有：锁+元数据+审计日志）
/// - `.backup/`（自动备份）
/// - `todos/` / `sessions/` / `concepts/` / `raw/`
///
/// 主要职责：
/// - 初始化目录结构、默认 schema/index/profile
/// - 旧 `llm-wiki/` → 当前 `.owl/wiki/` 一次性迁移
/// - 旧 `todos.md` 单文件 → `todos/todo-{uuid}.md` 多文件拆分
/// - 旧 `sessions/{date}-{name}.md` → `sessions/{sessionId}.md`
/// - 写入走 WikiFileWriter（加锁+原子+备份+审计）
class WikiRepository implements IWikiRepository {
  /// 桌面平台下的应用目录名（用于 ~/Documents/<name>/.owl/wiki/）
  static const _appDirName = 'Owl';

  /// v5 根目录名（隐藏 `.owl/` + 知识容器 `wiki/`）
  static const _owlRoot = '.owl';
  static const _wikiDir = 'wiki';

  /// v4 及以前使用的根目录（迁移时检测）
  static const _legacyWikiRoot = 'llm-wiki';

  /// 默认 Schema 规则内容（给 LLM 的 Wiki 编写规范，v5）
  static const _defaultSchema = '''# LLM-Wiki Schema 编写规范（v5）

你是专业的Wiki知识编辑助手，严格遵循以下规则，将新摄入的素材结构化更新到Wiki中。

## 0. 文件结构

所有 Wiki 文件位于 `.owl/wiki/` 目录下，按类型分目录：

- `profile.md` — 用户画像（仅 1 个）
- `todos/todo-{uuid}.md` — 待办（每条 1 个文件，UUID 全局唯一）
- `sessions/{sessionId}.md` — 短期记忆 + 摘要（文件名稳定，便于引用）
- `concepts/{entityId}.md` — 长期知识（entityId 由 Ingest 生成）

## 1. front-matter 规范

每个 Wiki 文件以 YAML 块声明元数据：

```
---
title: 页面标题
description: 一句话摘要（≤ 200 字）
weight: 10                  # 排序权重，UI 按升序展示
updated_at: 2026-09-17T10:00:00Z
# --- 类型专属字段（按需填写）---
status: pending            # todos 专属
priority: high
todo_id: a3f7e9b1-2c4d-4e5f-8a9b-1c2d3e4f5a6b
---
```

写入流程由程序自动维护 `updated_at`，LLM 不要手动修改。

## 2. 页面命名规范

- 文件名使用英文小写、中划线、下划线、UUID，不允许有空格、中文
- todos 强制 `todo-{uuid}.md`
- sessions 强制 `{sessionId}.md`（sessionId 为 UUID）
- concepts 强制 `{entityId}.md`（如 `concept-iot`、`project-vex`）

## 3. 内容创作规范

- 单个页面仅描述**单一实体/概念/会话/待办**，不得混合无关内容
- 页面结构固定：
  1. front-matter（强制）
  2. 一级 Markdown 标题（与 title 一致）
  3. 摘要（1-2 句话，与 description 一致）
  4. 核心内容（分二级/三级标题，结构化整理事实、数据、结论）
  5. 关联模块：`[[文件名|显示文本]]` 格式的双向内链
  6. 溯源模块：`> 来源：[raw文件相对路径] | 摄入时间：[yyyy-MM-dd HH:mm:ss]`
  7. 冲突模块：若有新旧知识冲突，用引用块标记差异

## 4. 链接规范

- 必须为所有关联实体、项目、会话添加双向内链
- 内链引用**完整文件名**（含 `.md` 后缀），如 `[[profile.md|用户画像]]`
- 禁止使用无效链接、外链地址

## 5. 知识更新规范

- 检查现有 Wiki 页面，若新素材补充旧内容，生成变更列表
- 若与旧内容冲突，**不得直接覆盖**，在页面末尾增加「冲突记录」模块

## 6. 索引更新（程序自动处理，LLM 不要直接改 index.md）

`index.md` 是人类可读展示目录，由 Ingest/Lint 自动增量 append。
LLM 创建新页面后，仅在正文与 front-matter 中维护内容，索引追加由程序完成。
''';

  /// 默认索引内容（人类可读展示用）
  static const _defaultIndex = '''# Wiki 全局目录

> 本文件由程序自动维护，展示用。每次 Ingest/Lint 增量追加，不删除历史。
> 主索引逻辑走 SQLite metadata（如 concepts/todos 的列表查询）。

---

## profile（用户画像）

- [[profile]] · 用户画像 · 个人基础信息与偏好

---

## concepts（长期知识）

（暂无）

---

## sessions（短期记忆摘要）

（暂无）

---

## todos（待办）

<!-- todos 增量小，不在此展示，详见 todos/ 目录 -->
共 0 项活跃 · 0 项已归档
''';

  /// 默认用户画像页面（带 v5 front-matter）
  static String get _defaultProfile {
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final fm = WikiFrontMatter(
      title: '用户画像',
      description: '个人基础信息与偏好',
      weight: 1,
      updatedAt: DateTime.now().toUtc(),
    );
    return '${fm.serialize()}\n'
        '# 用户画像\n\n'
        '> 此文件由 AI 与用户共同维护，记录用户的个人基础信息与偏好。\n\n'
        '## 基础信息\n\n'
        '（请在对话中逐步完善）\n\n'
        '## 偏好设定\n\n'
        '- 编程语言：待补充\n'
        '- 工具栈：待补充\n'
        '- 工作领域：待补充\n\n'
        '## 关联\n\n'
        '（暂无）\n\n'
        '> 来源：系统初始化 | 摄入时间：$timestamp\n';
  }

  /// Wiki 根目录的绝对路径（惰性初始化）
  String? _rootPath;
  String? _appDocsPath;

  /// 获取应用文档目录（缓存）
  ///
  /// Android：`<手机存储根目录>`（即 `/storage/emulated/0/`，与 Documents 平级）
  /// iOS / 其他：应用专属目录（沙盒内）
  Future<String> get _appDocs async {
    if (_appDocsPath != null) return _appDocsPath!;
    if (Platform.isAndroid) {
      // Android：使用公共存储根目录（与 Documents 平级）
      // Android 11+ 需要 MANAGE_EXTERNAL_STORAGE 权限
      _appDocsPath = '/storage/emulated/0';
    } else if (Platform.isIOS) {
      // iOS：沙盒限制，只能用应用专属目录
      _appDocsPath = (await getApplicationDocumentsDirectory()).path;
    } else {
      // 桌面平台：~/Documents/Owl/（跨平台统一"我的文档"）
      final docs = await getApplicationDocumentsDirectory();
      _appDocsPath = p.join(docs.path, _appDirName);
    }
    return _appDocsPath!;
  }

  /// Wiki 根目录
  ///
  /// - Android：`<手机存储>/.owl/wiki/`
  /// - iOS：`<AppDocuments>/.owl/wiki/`
  /// - 桌面：`<Documents>/Owl/.owl/wiki/`
  Future<String> get _root async {
    if (_rootPath != null) return _rootPath!;
    final appDocs = await _appDocs;
    _rootPath = p.join(appDocs, _owlRoot, _wikiDir);
    return _rootPath!;
  }

  WikiLockService? _lockService;
  WikiFileWriter? _writer;

  Future<WikiLockService> get _lock async {
    if (_lockService != null) return _lockService!;
    final root = await _root;
    _lockService = WikiLockService(root);
    return _lockService!;
  }

  Future<WikiFileWriter> get _fileWriter async {
    if (_writer != null) return _writer!;
    final root = await _root;
    _writer = WikiFileWriter(wikiRoot: root, lockService: await _lock);
    return _writer!;
  }

  @override
  Future<void> initialize() async {
    final root = await _root;

    // 0. 旧版迁移：`llm-wiki/` → `.owl/wiki/`
    await _migrateLegacyIfNeeded();

    // 1. 创建完整目录结构
    final directories = [
      root,
      p.join(root, '.meta'),
      p.join(root, '.backup'),
      p.join(root, 'raw', 'chat'),
      p.join(root, 'raw', 'docs'),
      p.join(root, 'todos'),
      p.join(root, 'todos', '.archive'),
      p.join(root, 'sessions'),
      p.join(root, 'sessions', '.archive'),
      p.join(root, 'concepts'),
      p.join(root, 'concepts', '.archive'),
    ];
    for (final dirPath in directories) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }

    // 2. schema.md（不可变，仅首次写入）
    final schemaFile = File(p.join(root, 'schema.md'));
    if (!await schemaFile.exists()) {
      await schemaFile.writeAsString(_defaultSchema);
    }

    // 3. index.md（人类可读展示目录）
    final indexFile = File(p.join(root, 'index.md'));
    if (!await indexFile.exists()) {
      await indexFile.writeAsString(_defaultIndex);
    }

    // 4. profile.md
    final profileFile = File(p.join(root, 'profile.md'));
    if (!await profileFile.exists()) {
      await profileFile.writeAsString(_defaultProfile);
    }

    // 5. 兼容旧版 context-settings.md / api-configs.md
    final settingsFile = File(p.join(root, 'context-settings.md'));
    if (!await settingsFile.exists()) {
      await settingsFile.writeAsString(ContextSettingsParser.defaultContent());
    }
    final apiConfigsFile = File(p.join(root, 'api-configs.md'));
    if (!await apiConfigsFile.exists()) {
      await apiConfigsFile.writeAsString(ApiConfigsParser.defaultContent());
    }

    // 6. 清理过期锁
    try {
      (await _lock).cleanupExpired();
    } catch (_) {
      // ignore
    }

    TalkerService.instance.wiki('✅ Wiki 根目录初始化完成：$root');
  }

  @override
  Future<String> getRootPath() async => await _root;

  @override
  Future<String> readIndex() async {
    final root = await _root;
    final file = File(p.join(root, 'index.md'));
    if (!await file.exists()) return _defaultIndex;
    return file.readAsString();
  }

  @override
  Future<void> writeIndex(String content) async {
    final writer = await _fileWriter;
    // index.md 不走 front-matter（v5 文档约定），但写入仍走加锁 + 原子写
    await writer.writeRaw(
      kind: WikiFileKind.indexFile,
      relativePath: 'index.md',
      rawContent: content,
    );
  }

  @override
  Future<String> readPage(String fileName) async {
    final root = await _root;
    final file = File(p.join(root, fileName));
    if (!await file.exists()) {
      throw FileSystemException('Wiki 页面不存在', file.path);
    }
    return file.readAsString();
  }

  @override
  Future<void> writePage(
    String fileName,
    String content, {
    String? sourceRawPath,
  }) async {
    final writer = await _fileWriter;
    final kind = _inferKind(fileName);

    // 解析可能已存在的 front-matter，合并溯源引用
    String finalContent = content;
    if (sourceRawPath != null && sourceRawPath.isNotEmpty) {
      final timestamp = DateTime.now().toIso8601String().substring(0, 19);
      finalContent += '\n\n> 来源引用：$sourceRawPath | 写入时间：$timestamp';
    }

    final existing = await readPage(fileName).catchError((_) => '');
    WikiFrontMatter fm;
    String body;
    if (existing.isNotEmpty) {
      final (existingFm, existingBody) = WikiFrontMatter.parse(existing);
      fm = existingFm;
      body = finalContent;
    } else {
      fm = WikiFrontMatter(
        title: fileName.split('/').last.replaceAll('.md', ''),
        description: '',
      );
      body = finalContent;
    }

    await writer.write(
      kind,
      WikiFile(frontMatter: fm, body: body, relativePath: fileName),
    );
  }

  @override
  Future<List<String>> listPages() async {
    final root = await _root;
    final wikiDir = Directory(root);
    if (!await wikiDir.exists()) return [];

    final pages = <String>[];
    await _collectMarkdownFiles(wikiDir, '', pages);

    pages.sort((a, b) {
      if (a == 'profile.md') return -1;
      if (b == 'profile.md') return 1;
      return a.compareTo(b);
    });

    return pages;
  }

  @override
  Future<List<String>> listRawFiles() async {
    final root = await _root;
    final rawDir = Directory(p.join(root, 'raw'));
    if (!await rawDir.exists()) return [];
    final files = <String>[];
    await _collectMarkdownFiles(rawDir, 'raw', files);
    return files;
  }

  @override
  Future<void> deletePage(String fileName) async {
    final writer = await _fileWriter;
    final kind = _inferKind(fileName);
    await writer.delete(kind, fileName);
  }

  @override
  Future<void> renamePage(String oldName, String newName) async {
    final root = await _root;
    final oldFile = File(p.join(root, oldName));
    final newFile = File(p.join(root, newName));
    if (!await oldFile.exists()) {
      throw FileSystemException('要重命名的 Wiki 页面不存在', oldFile.path);
    }
    final parent = newFile.parent;
    if (!await parent.exists()) await parent.create(recursive: true);
    await oldFile.rename(newFile.path);
    await _updateWikiLinks(oldName, newName);
  }

  @override
  Future<bool> pageExists(String fileName) async {
    final root = await _root;
    final file = File(p.join(root, fileName));
    return file.exists();
  }

  // ───────────────────────── 应用设置文件 ─────────────────────────

  Future<File> _contextSettingsFile() async {
    final root = await _root;
    return File(p.join(root, 'context-settings.md'));
  }

  @override
  Future<String?> readContextSettings() async {
    final file = await _contextSettingsFile();
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<void> writeContextSettings(String content) async {
    final file = await _contextSettingsFile();
    final parent = file.parent;
    if (!await parent.exists()) await parent.create(recursive: true);
    await file.writeAsString(content, flush: true);
  }

  @override
  Future<bool> contextSettingsExists() async {
    final file = await _contextSettingsFile();
    return file.exists();
  }

  // ───────────────────────── API 配置文件 ─────────────────────────

  Future<File> _apiConfigsFile() async {
    final root = await _root;
    return File(p.join(root, 'api-configs.md'));
  }

  @override
  Future<String?> readApiConfigs() async {
    final file = await _apiConfigsFile();
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<void> writeApiConfigs(String content) async {
    final file = await _apiConfigsFile();
    final parent = file.parent;
    if (!await parent.exists()) await parent.create(recursive: true);
    await file.writeAsString(content, flush: true);
  }

  @override
  Future<bool> apiConfigsExists() async {
    final file = await _apiConfigsFile();
    return file.exists();
  }

  // ───────────────────────── Todos 多文件 API ─────────────────────────

  @override
  Future<List<String>> listTodoFiles({bool includeArchived = false}) async {
    final root = await _root;
    final result = <String>[];
    final todosDir = Directory(p.join(root, 'todos'));
    if (await todosDir.exists()) {
      await for (final entity in todosDir.list(followLinks: false)) {
        if (entity is File && entity.path.endsWith('.md')) {
          result.add('todos/${p.basename(entity.path)}');
        }
      }
    }
    if (includeArchived) {
      final archiveDir = Directory(p.join(root, 'todos', '.archive'));
      if (await archiveDir.exists()) {
        await for (final entity in archiveDir.list(followLinks: false)) {
          if (entity is File && entity.path.endsWith('.md')) {
            result.add('todos/.archive/${p.basename(entity.path)}');
          }
        }
      }
    }
    result.sort();
    return result;
  }

  @override
  Future<String> readTodo(String fileName) async {
    final content = await readPage(fileName);
    final (_, body) = WikiFrontMatter.parse(content);
    return body.trim();
  }

  @override
  Future<void> writeTodo(
    String fileName,
    String content, {
    Map<String, dynamic>? frontMatterExtras,
  }) async {
    final writer = await _fileWriter;

    // 解析现有 front-matter
    Map<String, dynamic> extras = frontMatterExtras ?? <String, dynamic>{};
    String body = content;
    String title = fileName.split('/').last.replaceAll('.md', '');

    final existing = await readPage(fileName).catchError((_) => '');
    if (existing.isNotEmpty) {
      final (fm, existingBody) = WikiFrontMatter.parse(existing);
      title = fm.title;
      // 合并 extras：调用方提供的优先
      extras = {...fm.extras, ...extras};
      // 如果调用方没传 body，用现有 body
      if (content.isEmpty) body = existingBody;
    }

    final fm = WikiFrontMatter(
      title: title,
      description: (extras['description'] as String?) ?? '',
      weight: (extras['weight'] as int?) ?? 100,
      extras: extras,
    );

    await writer.write(
      WikiFileKind.todo,
      WikiFile(frontMatter: fm, body: body, relativePath: fileName),
    );
  }

  @override
  Future<void> archiveTodo(String fileName) async {
    final root = await _root;
    final src = File(p.join(root, fileName));
    if (!await src.exists()) return;
    final archiveDir = Directory(p.join(root, 'todos', '.archive'));
    if (!await archiveDir.exists()) await archiveDir.create(recursive: true);
    final dst = File(p.join(archiveDir.path, p.basename(fileName)));
    if (await dst.exists()) await dst.delete();
    await src.rename(dst.path);

    // 写 front-matter 加 archived_at
    final (fm, body) = WikiFrontMatter.parse(await dst.readAsString());
    final updatedFm = fm.copyWith(
      extras: {
        ...fm.extras,
        'archived': true,
        'archived_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
    final finalContent = '${updatedFm.serialize()}\n$body';
    await dst.writeAsString(finalContent, flush: true);
  }

  @override
  Future<void> unarchiveTodo(String fileName) async {
    final root = await _root;
    final archivedPath = p.join(root, 'todos', '.archive', p.basename(fileName));
    final src = File(archivedPath);
    if (!await src.exists()) return;
    final dst = File(p.join(root, fileName));
    if (await dst.exists()) await dst.delete();
    await src.rename(dst.path);

    // 去掉 archived 标记
    final (fm, body) = WikiFrontMatter.parse(await dst.readAsString());
    final cleanedExtras = Map<String, dynamic>.from(fm.extras)
      ..remove('archived')
      ..remove('archived_at');
    final updatedFm = fm.copyWith(extras: cleanedExtras);
    final finalContent = '${updatedFm.serialize()}\n$body';
    await dst.writeAsString(finalContent, flush: true);
  }

  @override
  Future<void> deleteTodo(String fileName) async {
    final writer = await _fileWriter;
    await writer.delete(WikiFileKind.todo, fileName);
  }

  // ───────────────────────── 元数据 API ─────────────────────────

  @override
  Future<Map<String, dynamic>?> readExportMeta() async {
    final root = await _root;
    final file = File(p.join(root, '.meta', 'export-meta.json'));
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeExportMeta(Map<String, dynamic> meta) async {
    final root = await _root;
    final metaDir = Directory(p.join(root, '.meta'));
    if (!await metaDir.exists()) await metaDir.create(recursive: true);
    final file = File(p.join(metaDir.path, 'export-meta.json'));
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(meta), flush: true);
    if (await file.exists()) await file.delete();
    await tmp.rename(file.path);
  }

  // ───────────────────────── 内部工具 ─────────────────────────

  /// 从文件路径推断文件类型
  WikiFileKind _inferKind(String relativePath) {
    if (relativePath == 'profile.md') return WikiFileKind.profile;
    if (relativePath == 'index.md') return WikiFileKind.indexFile;
    if (relativePath == 'schema.md') return WikiFileKind.schema;
    if (relativePath.startsWith('todos/')) return WikiFileKind.todo;
    if (relativePath.startsWith('sessions/')) return WikiFileKind.session;
    if (relativePath.startsWith('concepts/')) return WikiFileKind.concept;
    return WikiFileKind.unknown;
  }

  Future<void> _collectMarkdownFiles(
    Directory dir,
    String prefix,
    List<String> files,
  ) async {
    await for (final entity in dir.list(followLinks: false)) {
      final name = p.basename(entity.path);
      // 跳过私有/备份目录
      if (name.startsWith('.') || name == 'raw' || name == '.backup') {
        continue;
      }
      if (entity is File && entity.path.endsWith('.md')) {
        final relativePath = prefix.isEmpty ? name : p.join(prefix, name);
        files.add(relativePath);
      } else if (entity is Directory) {
        final subPrefix = prefix.isEmpty ? name : p.join(prefix, name);
        await _collectMarkdownFiles(entity, subPrefix, files);
      }
    }
  }

  Future<void> _updateWikiLinks(String oldName, String newName) async {
    final pages = await listPages();
    final root = await _root;
    for (final pagePath in pages) {
      final file = File(p.join(root, pagePath));
      if (!await file.exists()) continue;
      var content = await file.readAsString();
      final linkPattern1 = '[[${_escapeRegex(oldName)}]]';
      final linkPattern2 =
          RegExp(r'\[\[' + _escapeRegex(oldName) + r'\|([^\]]+)\]\]');
      if (content.contains(linkPattern1) || linkPattern2.hasMatch(content)) {
        content = content.replaceAll(linkPattern1, '[[$newName]]');
        content = content.replaceAllMapped(linkPattern2, (match) {
          final displayText = match.group(1);
          return '[[$newName|$displayText]]';
        });
        await file.writeAsString(content);
      }
    }
  }

  String _escapeRegex(String input) {
    return input.replaceAllMapped(
      RegExp(r'[.*+?^${}()|[\]\\]'),
      (match) => '\\${match.group(0)}',
    );
  }

  // ───────────────────────── 旧版迁移 ─────────────────────────

  /// 检测并迁移旧 `llm-wiki/` 目录到 `.owl/wiki/`
  ///
  /// 一次性：复制所有文件后，将旧目录改名为 `.llm-wiki.backup-{ts}`
  /// 会尝试多个可能的旧位置（应用沙盒、旧 Android 公共文档目录等）。
  Future<void> _migrateLegacyIfNeeded() async {
    // 候选旧目录：当前新位置之前可能存在过的所有可能路径
    final candidates = await _candidateLegacyRoots();
    Directory? legacyDir;
    for (final c in candidates) {
      final d = Directory(c);
      if (await d.exists()) {
        legacyDir = d;
        break;
      }
    }
    if (legacyDir == null) return;

    final newRoot = p.join(await _appDocs, _owlRoot, _wikiDir);
    final newDir = Directory(newRoot);

    // 如果新目录已经存在数据，说明之前已迁移过，跳过
    if (await newDir.exists()) {
      final hasContent = await _dirHasContent(newDir);
      if (hasContent) {
        TalkerService.instance.wiki(
          '⚠️ 检测到旧 llm-wiki/ 但新 .owl/wiki/ 已有内容，跳过迁移',
        );
        return;
      }
    }

    TalkerService.instance.wiki(
      '📦 开始迁移旧 ${legacyDir.path} → $newRoot',
    );
    await _copyDir(legacyDir, newDir);
    await _migrateLegacyContent(newDir);

    // 旧目录改名保留
    final ts = DateTime.now().millisecondsSinceEpoch;
    try {
      await legacyDir.rename('${legacyDir.path}.backup-$ts');
      TalkerService.instance.wiki('✅ 旧 llm-wiki/ 已重命名为 .backup');
    } catch (e) {
      TalkerService.instance.wiki('⚠️ 旧目录重命名失败：$e');
    }
  }

  /// 返回可能的旧版 llm-wiki 候选根目录列表
  Future<List<String>> _candidateLegacyRoots() async {
    final roots = <String>[];
    if (Platform.isAndroid) {
      // 旧 v4 可能在这些位置
      roots.add('/storage/emulated/0/llm-wiki');        // 手机存储根目录（v4.5）
      roots.add('/storage/emulated/0/Android/data/com.vex.owl/files/llm-wiki'); // 应用沙盒
      try {
        final appFiles = await getApplicationDocumentsDirectory();
        roots.add(p.join(appFiles.path, 'llm-wiki'));  // path_provider 给的位置
      } catch (_) {}
    } else {
      // iOS / 桌面：旧版就只在应用文档目录
      try {
        final appFiles = await getApplicationDocumentsDirectory();
        roots.add(p.join(appFiles.path, 'llm-wiki'));
        // 桌面旧位置：~/Documents/llm-wiki（未带 Owl 子目录）
        if (!Platform.isIOS) {
          roots.add(p.join(appFiles.path, 'llm-wiki'));
        }
      } catch (_) {}
    }
    return roots;
  }

  Future<bool> _dirHasContent(Directory dir) async {
    await for (final entity in dir.list(followLinks: false)) {
      // 忽略 .meta / .backup
      final basename = p.basename(entity.path);
      if (basename.startsWith('.')) continue;
      return true;
    }
    return false;
  }

  Future<void> _copyDir(Directory src, Directory dst) async {
    if (!await dst.exists()) await dst.create(recursive: true);
    await for (final entity in src.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;
      if (entity is File) {
        await entity.copy(p.join(dst.path, name));
      } else if (entity is Directory) {
        await _copyDir(entity, Directory(p.join(dst.path, name)));
      }
    }
  }

  /// 迁移旧内容到 v5 格式
  ///
  /// 1. `todos.md`（单文件）→ `todos/todo-{uuid}.md`（多文件）
  /// 2. `sessions/{date}-{name}.md` → 重命名为 `{sessionId}.md`，加 front-matter
  Future<void> _migrateLegacyContent(Directory root) async {
    // 1. 旧 todos.md → todos/ 多文件
    final oldTodos = File(p.join(root.path, 'todos.md'));
    if (await oldTodos.exists()) {
      await _splitLegacyTodos(oldTodos, root);
      try {
        await oldTodos.delete();
      } catch (_) {}
    }

    // 2. 旧 sessions/{date}-{name}.md → {sessionId}.md
    final sessionsDir = Directory(p.join(root.path, 'sessions'));
    if (await sessionsDir.exists()) {
      await _renameLegacySessions(sessionsDir);
    }

    // 3. profile.md 加 front-matter（若没有）
    final profile = File(p.join(root.path, 'profile.md'));
    if (await profile.exists()) {
      final content = await profile.readAsString();
      if (!content.trimLeft().startsWith('---')) {
        final fm = WikiFrontMatter(
          title: '用户画像',
          description: '个人基础信息与偏好',
          weight: 1,
        );
        await profile.writeAsString('${fm.serialize()}\n$content', flush: true);
      }
    }

    // 4. index.md：若仍为 v4 主索引格式（每行 `- [[xxx]]｜...`），改写为 v5 展示格式
    final index = File(p.join(root.path, 'index.md'));
    if (await index.exists()) {
      final content = await index.readAsString();
      if (!content.startsWith('# Wiki 全局目录')) {
        await index.writeAsString(_defaultIndex, flush: true);
      }
    }
  }

  /// 拆分旧 todos.md（`- [ ] 任务 | ...` 列表）为多文件
  Future<void> _splitLegacyTodos(File oldTodos, Directory root) async {
    final todosDir = Directory(p.join(root.path, 'todos'));
    if (!await todosDir.exists()) await todosDir.create(recursive: true);

    final content = await oldTodos.readAsString();
    final lines = const LineSplitter().convert(content);
    var todoCount = 0;
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty || !line.startsWith('- ')) continue;
      final match = RegExp(r'^-\s+\[(?: |x)?\]\s+(.+)$').firstMatch(line);
      if (match == null) continue;
      final title = match.group(1)!.trim();
      // 解析 `｜...` 分隔的元数据（兼容旧格式）
      final parts = title.split('｜').map((s) => s.trim()).toList();
      final cleanTitle = parts.first;
      String? dueAt;
      String? priority;
      String? createdAt;
      for (final part in parts.skip(1)) {
        final kv = part.split('：');
        if (kv.length < 2) continue;
        final k = kv[0].trim();
        final v = kv.sublist(1).join('：').trim();
        if (k.contains('截止')) dueAt = v;
        if (k.contains('优先级')) priority = v;
        if (k.contains('创建')) createdAt = v;
      }

      final todoId = _uuid();
      final fileName = 'todos/todo-$todoId.md';
      final file = File(p.join(root.path, fileName));
      final fm = WikiFrontMatter(
        title: cleanTitle,
        description: '',
        weight: 100,
        extras: {
          'status': 'pending',
          'priority': priority ?? 'medium',
          if (dueAt != null) 'due_at': dueAt,
          if (createdAt != null) 'created_at': createdAt,
          'todo_id': todoId,
        },
      );
      final body = '\n# $cleanTitle\n\n'
          '## 备注\n\n'
          '> 从旧 todos.md 迁移而来\n';
      await file.writeAsString('${fm.serialize()}\n$body', flush: true);
      todoCount++;
    }

    if (todoCount > 0) {
      TalkerService.instance.wiki('📋 旧 todos.md 拆分完成：$todoCount 条');
    }
  }

  /// 重命名旧 sessions/{date}-{name}.md → {sessionId}.md
  Future<void> _renameLegacySessions(Directory sessionsDir) async {
    await for (final entity in sessionsDir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;
      // 旧格式：2026-09-16-xxx.md 或 2026-09-16_xxx.md
      final legacyPattern = RegExp(r'^\d{4}-\d{2}-\d{2}[-_].+\.md$');
      if (!legacyPattern.hasMatch(name)) continue;

      // 读 front-matter 中的 session-id（v3/v4 写过）
      String? sessionId;
      try {
        final content = await entity.readAsString();
        final m = RegExp(r'session-id:\s*(\S+)').firstMatch(content);
        if (m != null) sessionId = m.group(1);
        if (sessionId == null) {
          final m2 = RegExp(r'session_id:\s*(\S+)').firstMatch(content);
          if (m2 != null) sessionId = m2.group(1);
        }
      } catch (_) {}
      sessionId ??= _uuid();

      final newName = '$sessionId.md';
      final dst = File(p.join(sessionsDir.path, newName));
      if (await dst.exists()) {
        // 已存在同名文件，覆盖旧文件
        try {
          await dst.delete();
        } catch (_) {}
      }
      try {
        await entity.rename(dst.path);
      } catch (_) {
        continue;
      }

      // 补充 session_id front-matter（若没有）
      try {
        final content = await dst.readAsString();
        if (!content.contains('session_id:')) {
          final (fm, body) = WikiFrontMatter.parse(content);
          final updatedFm = fm.copyWith(
            extras: {...fm.extras, 'session_id': sessionId},
          );
          await dst.writeAsString('${updatedFm.serialize()}\n$body', flush: true);
        }
      } catch (_) {}
    }
  }

  String _uuid() {
    // 简化版 UUID v4（足够用于文件名唯一性）
    final r = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final s = (r.hashCode).abs().toRadixString(36);
    return '$r-$s';
  }
}

/// LineSplitter 复用 dart:convert
class LineSplitter {
  const LineSplitter();
  List<String> convert(String input) =>
      input.split(RegExp(r'\r\n|\r|\n'));
}