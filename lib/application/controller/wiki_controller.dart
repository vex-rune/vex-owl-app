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

  // ── Getters ──

  String get indexContent => _indexContent;
  List<String> get wikiPages => _wikiPages;
  List<String> get rawFiles => _rawFiles;
  String? get currentPage => _currentPage;
  List<String> get todoFiles => _todoFiles;
  List<String> get archivedTodoFiles => _archivedTodoFiles;

  /// 加载 Wiki 数据
  Future<void> loadWiki() async {
    try {
      _indexContent = await _repo.readIndex();
      _wikiPages = await _repo.listPages();
      _rawFiles = await _repo.listRawFiles();
      _todoFiles = await _repo.listTodoFiles();
      _archivedTodoFiles = await _repo.listTodoFiles(includeArchived: true)
        ..removeWhere((f) => _todoFiles.contains(f));
      notifyListeners();
    } catch (e) {
      debugPrint('加载知识库失败：$e');
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
}

/// Riverpod Provider：暴露 [WikiController]
final wikiControllerProvider = ChangeNotifierProvider<WikiController>(
  (ref) => WikiController(ref),
);