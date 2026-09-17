/// Owl 根目录路径管理器（v6.4）
///
/// 统一管理 `.owl/` 下的所有子目录路径：
/// - sessionsDir: `.owl/sessions/`
/// - configDir: `.owl/config/`
/// - wikiDir: `.owl/wiki/`
/// - metaDir: `.owl/.meta/`
/// - backupDir: `.owl/.backup/`
///
/// 跨平台策略：
/// - Android: `/storage/emulated/0/.owl/`
/// - iOS: `<AppDocuments>/.owl/`
/// - 桌面: `<Documents>/Owl/.owl/`
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/core.dart';


/// Owl 根目录管理器
///
/// 单例，在 App 启动时初始化一次。
class OwlRoot {
  OwlRoot._();

  static final OwlRoot instance = OwlRoot._();

  /// 应用文档目录（跨平台根）
  static const String _appDirName = 'Owl';

  /// Owl 根目录名（隐藏目录）
  static const String _owlRoot = '.owl';

  /// ── 惰性初始化的路径缓存 ──

  String? _appDocsPath;
  String? _rootPath;

  /// 应用文档目录绝对路径
  String? get appDocsPath => _appDocsPath;

  /// `.owl/` 根目录绝对路径
  String? get rootPath => _rootPath;

  /// `.owl/.meta/` 绝对路径
  String get metaDir => p.join(_rootPath!, '.meta');

  /// `.owl/.backup/` 绝对路径
  String get backupDir => p.join(_rootPath!, '.backup');

  /// `.owl/sessions/` 绝对路径
  String get sessionsDir => p.join(_rootPath!, 'sessions');

  /// `.owl/sessions/.archive/` 绝对路径
  String get sessionsArchiveDir => p.join(sessionsDir, '.archive');

  /// `.owl/config/` 绝对路径
  String get configDir => p.join(_rootPath!, 'config');

  /// `.owl/wiki/` 绝对路径
  String get wikiDir => p.join(_rootPath!, 'wiki');

  // ── 初始化 ─────────────────────────────────────────────────────────────

  /// 初始化 Owl 根目录
  ///
  /// 1. 确定应用文档目录（跨平台）
  /// 2. 创建 `.owl/` 及其所有子目录
  /// 3. 若检测到旧目录结构，执行迁移
  Future<void> initialize() async {
    await _initAppDocs();
    await _initRoot();
    await _createDirectories();
    await _migrateLegacyIfNeeded();
    log.debug('✅ OwlRoot 初始化完成：$_rootPath');
  }

  Future<void> _initAppDocs() async {
    if (_appDocsPath != null) return;

    if (Platform.isAndroid) {
      // Android: 公共存储根目录（与 Documents 平级）
      _appDocsPath = '/storage/emulated/0';
    } else if (Platform.isIOS) {
      // iOS: 沙盒限制，只能用应用专属目录
      _appDocsPath = (await getApplicationDocumentsDirectory()).path;
    } else {
      // 桌面平台: ~/Documents/Owl/
      final docs = await getApplicationDocumentsDirectory();
      _appDocsPath = p.join(docs.path, _appDirName);
    }
  }

  Future<void> _initRoot() async {
    if (_rootPath != null) return;
    _rootPath = p.join(_appDocsPath!, _owlRoot);
  }

  /// 创建完整目录结构
  Future<void> _createDirectories() async {
    final dirs = [
      _rootPath!,
      metaDir,
      backupDir,
      sessionsDir,
      sessionsArchiveDir,
      configDir,
      wikiDir,
      p.join(wikiDir, '.meta'),
      p.join(wikiDir, '.backup'),
      p.join(wikiDir, 'raw', 'chat'),
      p.join(wikiDir, 'raw', 'docs'),
      p.join(wikiDir, 'todos'),
      p.join(wikiDir, 'todos', '.archive'),
      p.join(wikiDir, 'sessions'),
      p.join(wikiDir, 'sessions', '.archive'),
      p.join(wikiDir, 'concepts'),
      p.join(wikiDir, 'concepts', '.archive'),
    ];

    for (final dirPath in dirs) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }
  }

  /// 迁移旧目录结构
  ///
  /// 旧: `{appDocs}/llm-wiki/`
  /// 新: `{appDocs}/.owl/wiki/`
  Future<void> _migrateLegacyIfNeeded() async {
    final legacyCandidates = <String>[];

    if (Platform.isAndroid) {
      legacyCandidates.add('/storage/emulated/0/llm-wiki');
      legacyCandidates.add(
          '/storage/emulated/0/Android/data/com.vex.owl/files/llm-wiki');
    }

    try {
      final appFiles = await getApplicationDocumentsDirectory();
      legacyCandidates.add(p.join(appFiles.path, 'llm-wiki'));
    } catch (_) {}

    Directory? legacyDir;
    for (final c in legacyCandidates) {
      final d = Directory(c);
      if (await d.exists()) {
        legacyDir = d;
        break;
      }
    }
    if (legacyDir == null) return;

    // 检查新目录是否已有内容
    final newDir = Directory(p.join(_rootPath!, 'wiki'));
    if (await newDir.exists()) {
      final hasContent = await _dirHasContent(newDir);
      if (hasContent) {
        log.debug(
          '⚠️ 检测到旧 llm-wiki/ 但新 .owl/wiki/ 已有内容，跳过迁移',
        );
        return;
      }
    }

    log.debug('📦 迁移旧目录：${legacyDir.path} → $newDir');
    await _copyDir(legacyDir, newDir);

    // 旧目录改名保留
    final ts = DateTime.now().millisecondsSinceEpoch;
    try {
      await legacyDir.rename('${legacyDir.path}.backup-$ts');
      log.debug('✅ 旧 llm-wiki/ 已迁移备份');
    } catch (e) {
      log.debug('⚠️ 旧目录备份失败：$e');
    }
  }

  Future<bool> _dirHasContent(Directory dir) async {
    await for (final entity in dir.list(followLinks: false)) {
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

  // ── 便捷路径生成 ───────────────────────────────────────────────────────

  /// 获取会话目录路径
  String sessionDir(String sessionId) =>
      p.join(sessionsDir, sessionId);

  /// 获取会话 session.jsonl 路径
  String sessionJsonlPath(String sessionId) =>
      p.join(sessionDir(sessionId), 'session.jsonl');

  /// 获取会话 messages.jsonl 路径
  String messagesJsonlPath(String sessionId) =>
      p.join(sessionDir(sessionId), 'messages.jsonl');

  /// 获取会话 summary.md 路径
  String summaryMdPath(String sessionId) =>
      p.join(sessionDir(sessionId), 'summary.md');

  /// 获取归档会话目录路径
  String archiveSessionDir(String sessionId) =>
      p.join(sessionsArchiveDir, sessionId);

  /// 获取配置路径
  String configPath(String filename) => p.join(configDir, filename);
}
