import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../../core/model/wiki_front_matter.dart';
import '../../data/repository/i_wiki_repository.dart';

/// Wiki 知识库管理控制器（基于 ChangeNotifier + Riverpod）
///
/// 负责 Wiki 页面的读写、索引管理、页面列表维护等操作。
/// 通过构造函数注入 [Ref]，再从 `app_providers` 中获取 [IWikiRepository]。
class WikiController extends ChangeNotifier {
  WikiController(this._ref) {
    loadWiki();
  }

  final Ref _ref;

  late final IWikiRepository _repo = _ref.read(wikiRepositoryProvider);

  // ── 内部可变状态 ──

  String _indexContent = '';
  List<String> _wikiPages = const [];
  List<String> _rawFiles = const [];
  String? _currentPage;
  List<String> _todoFiles = const [];
  List<String> _archivedTodoFiles = const [];

  /// 每个 wiki 页面的元数据缓存（updatedAt / title / description / starred）
  /// key 是相对路径（wikiPages / rawFiles / todoFiles 中的元素）。
  final Map<String, WikiPageMeta> _pageMetas = {};

  // ── Getters ──

  String get indexContent => _indexContent;
  List<String> get wikiPages => _wikiPages;
  List<String> get rawFiles => _rawFiles;
  String? get currentPage => _currentPage;
  List<String> get todoFiles => _todoFiles;
  List<String> get archivedTodoFiles => _archivedTodoFiles;

  /// 取指定文件的元数据（懒加载：首次访问触发读取）
  WikiPageMeta? metaOf(String relativePath) => _pageMetas[relativePath];

  /// 已收藏的文件相对路径列表（todos / wiki pages / raw files）
  List<String> get starredPaths => _pageMetas.entries
      .where((e) => e.value.starred)
      .map((e) => e.key)
      .toList();

  /// 加载 Wiki 数据
  Future<void> loadWiki() async {
    try {
      _indexContent = await _repo.readIndex();
      _wikiPages = await _repo.listPages();
      _rawFiles = await _repo.listRawFiles();
      _todoFiles = await _repo.listTodoFiles();
      _archivedTodoFiles = await _repo.listTodoFiles(includeArchived: true)
        ..removeWhere((f) => _todoFiles.contains(f));

      // 清空旧元数据缓存并异步刷新
      _pageMetas.clear();
      await _refreshAllMetas();
      notifyListeners();
    } catch (e) {
      debugPrint('加载知识库失败：$e');
    }
  }

  /// 异步解析所有可见文件的元数据（front-matter + 文件 mtime）。
  Future<void> _refreshAllMetas() async {
    final candidates = <String>[
      ..._wikiPages.where((p) => !p.startsWith('todos/')),
      ..._todoFiles,
      ..._rawFiles,
    ];
    await Future.wait(
      candidates.map((p) async {
        final m = await _loadMeta(p);
        if (m != null) _pageMetas[p] = m;
      }),
    );
  }

  /// 读取并解析单个文件的元数据（容错：失败时仅返回基于 mtime 的占位值）
  Future<WikiPageMeta?> _loadMeta(String relativePath) async {
    try {
      final raw = await _repo.readPage(relativePath);
      final (fm, _) = WikiFrontMatter.parse(raw);
      return WikiPageMeta(
        title: fm.title.isNotEmpty
            ? fm.title
            : relativePath.split('/').last.replaceAll('.md', ''),
        description: fm.description,
        updatedAt: fm.updatedAt,
        starred: fm.extras['starred'] == true,
      );
    } catch (e) {
      debugPrint('解析 front-matter 失败：$relativePath / $e');
      return null;
    }
  }

  /// 主动刷新单个文件元数据（写入 / 删除 / 收藏切换后调用）
  Future<void> refreshMetaOf(String relativePath) async {
    final m = await _loadMeta(relativePath);
    if (m != null) {
      _pageMetas[relativePath] = m;
      notifyListeners();
    }
  }

  /// 读取指定 Wiki 页面的内容
  Future<String> readPage(String fileName) async {
    try {
      final content = await _repo.readPage(fileName);
      _currentPage = fileName;
      notifyListeners();
      return content;
    } catch (e) {
      debugPrint('读取页面失败：$e');
      return '';
    }
  }

  /// 写入指定 Wiki 页面的内容
  Future<void> writePage(
    String fileName,
    String content, {
    String? sourceRawPath,
  }) async {
    try {
      await _repo.writePage(fileName, content, sourceRawPath: sourceRawPath);

      // 如果是新页面，刷新页面列表
      if (!_wikiPages.contains(fileName)) {
        await loadWiki();
        return;
      }

      // 如果写入的是索引页面，同步更新缓存
      if (fileName == 'index.md') {
        _indexContent = content;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('保存页面失败：$e');
    }
  }

  /// 删除指定 Wiki 页面
  Future<void> deletePage(String fileName) async {
    try {
      await _repo.deletePage(fileName);
      _wikiPages = [..._wikiPages]..remove(fileName);

      if (_currentPage == fileName) {
        _currentPage = null;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('删除页面失败：$e');
    }
  }

  // ── Todos 多文件 API（v5） ──

  /// 创建新 todo（生成 UUID 文件名）
  ///
  /// 返回新 todo 的相对路径（如 `todos/todo-{uuid}.md`），失败返回 null。
  Future<String?> createTodo({
    required String title,
    required String description,
    String priority = 'medium',
    String? dueAt,
    List<String> tags = const [],
  }) async {
    try {
      final todoId = _genId();
      final fileName = 'todos/todo-$todoId.md';
      final fm = WikiFrontMatter(
        title: title,
        description: description,
        weight: 100,
        extras: {
          'status': 'pending',
          'priority': priority,
          if (dueAt != null) 'due_at': dueAt,
          if (tags.isNotEmpty) 'tags': tags,
          'todo_id': todoId,
        },
      );
      final body = '# $title\n\n'
          '## 描述\n\n'
          '$description\n\n'
          '## 关联\n\n（暂无）\n\n'
          '## 备注\n\n> 创建：${DateTime.now().toUtc().toIso8601String()}\n';
      await _repo.writeTodo(
        fileName,
        body,
        frontMatterExtras: fm.extras,
      );
      _todoFiles = await _repo.listTodoFiles();
      notifyListeners();
      return fileName;
    } catch (e) {
      debugPrint('创建 todo 失败：$e');
      return null;
    }
  }

  /// 读取单个 todo 文件的 front-matter
  Future<WikiFrontMatter?> readTodoFrontMatter(String fileName) async {
    try {
      final content = await _repo.readPage(fileName);
      final (fm, _) = WikiFrontMatter.parse(content);
      return fm;
    } catch (_) {
      return null;
    }
  }

  /// 更新 todo 状态（如 pending → done）
  Future<void> updateTodoStatus(
    String fileName,
    String status, {
    String? priority,
  }) async {
    try {
      final content = await _repo.readPage(fileName);
      final (fm, body) = WikiFrontMatter.parse(content);
      final extras = <String, dynamic>{
        ...fm.extras,
        'status': status,
        if (priority != null) 'priority': priority,
        if (status == 'done')
          'completed_at': DateTime.now().toUtc().toIso8601String(),
      };
      final updated = fm.copyWith(extras: extras);
      await _repo.writeTodo(
        fileName,
        body,
        frontMatterExtras: updated.extras,
      );
      notifyListeners();
      await refreshMetaOf(fileName);
    } catch (e) {
      debugPrint('更新 todo 失败：$e');
    }
  }

  /// 归档 todo（移动到 todos/.archive/）
  Future<void> archiveTodo(String fileName) async {
    try {
      await _repo.archiveTodo(fileName);
      _todoFiles = await _repo.listTodoFiles();
      _archivedTodoFiles = await _repo.listTodoFiles(includeArchived: true)
        ..removeWhere((f) => _todoFiles.contains(f));
      notifyListeners();
    } catch (e) {
      debugPrint('归档 todo 失败：$e');
    }
  }

  /// 取消归档 todo
  Future<void> unarchiveTodo(String fileName) async {
    try {
      await _repo.unarchiveTodo(fileName);
      _todoFiles = await _repo.listTodoFiles();
      _archivedTodoFiles = await _repo.listTodoFiles(includeArchived: true)
        ..removeWhere((f) => _todoFiles.contains(f));
      notifyListeners();
    } catch (e) {
      debugPrint('取消归档 todo 失败：$e');
    }
  }

  /// 删除 todo
  Future<void> deleteTodo(String fileName) async {
    try {
      await _repo.deleteTodo(fileName);
      _todoFiles = await _repo.listTodoFiles();
      _archivedTodoFiles = await _repo.listTodoFiles(includeArchived: true)
        ..removeWhere((f) => _todoFiles.contains(f));
      notifyListeners();
    } catch (e) {
      debugPrint('删除 todo 失败：$e');
    }
  }

  /// 简易 UUID（用于 todo 文件名）
  String _genId() {
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final seed = ts.hashCode.abs().toRadixString(36);
    return '$ts-$seed';
  }

  // ── 收藏 / 重命名（v6.1 新增） ──

  /// 切换文件收藏状态（在 front-matter extras 中写入 starred）
  Future<void> toggleStarred(String relativePath) async {
    try {
      final raw = await _repo.readPage(relativePath);
      final (fm, body) = WikiFrontMatter.parse(raw);
      final current = fm.extras['starred'] == true;
      final newExtras = <String, dynamic>{
        ...fm.extras,
        'starred': !current,
        if (!current) 'starred_at': DateTime.now().toUtc().toIso8601String(),
      };
      // 取消收藏时移除 starred_at，便于以后扩展
      if (current) newExtras.remove('starred_at');

      final updatedFm = fm.copyWith(extras: newExtras);
      await _writeBack(relativePath, updatedFm, body);
      await refreshMetaOf(relativePath);
    } catch (e) {
      debugPrint('切换收藏失败：$relativePath / $e');
    }
  }

  /// 重命名 Wiki 页面（同步刷新内部索引与元数据缓存）
  Future<void> renameWikiPage(String oldName, String newName) async {
    if (oldName == newName) return;
    try {
      await _repo.renamePage(oldName, newName);
      // 同步更新本地缓存
      _wikiPages = [
        for (final p in _wikiPages) p == oldName ? newName : p,
      ];
      if (_pageMetas.containsKey(oldName)) {
        final m = _pageMetas.remove(oldName)!;
        _pageMetas[newName] = m;
      }
      if (_currentPage == oldName) _currentPage = newName;
      notifyListeners();
    } catch (e) {
      debugPrint('重命名失败：$oldName → $newName / $e');
    }
  }

  /// 按路径把更新后的 front-matter 写回文件（区分 todo / 普通 wiki）
  Future<void> _writeBack(
    String relativePath,
    WikiFrontMatter fm,
    String body,
  ) async {
    if (relativePath.startsWith('todos/')) {
      await _repo.writeTodo(relativePath, body, frontMatterExtras: fm.extras);
    } else {
      final newRaw = '${fm.serialize()}\n$body';
      await _repo.writePage(relativePath, newRaw);
    }
  }
}

/// Riverpod Provider：暴露 [WikiController]
final wikiControllerProvider = ChangeNotifierProvider<WikiController>(
  (ref) => WikiController(ref),
);

/// Wiki 文件元数据快照（v6.1 新增）
///
/// 由 [WikiController] 在 `loadWiki` 时统一从 front-matter 解析后缓存，
/// 供 UI 层在不重新读盘的前提下展示标题 / 摘要 / 更新时间 / 收藏状态。
class WikiPageMeta {
  const WikiPageMeta({
    required this.title,
    required this.description,
    required this.updatedAt,
    required this.starred,
  });

  final String title;
  final String description;
  final DateTime updatedAt;
  final bool starred;

  WikiPageMeta copyWith({
    String? title,
    String? description,
    DateTime? updatedAt,
    bool? starred,
  }) {
    return WikiPageMeta(
      title: title ?? this.title,
      description: description ?? this.description,
      updatedAt: updatedAt ?? this.updatedAt,
      starred: starred ?? this.starred,
    );
  }
}