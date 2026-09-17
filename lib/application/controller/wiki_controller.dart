import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../../core/model/wiki_front_matter.dart';
import '../../data/repository/i_wiki_repository.dart';

/// 不可变的 Wiki 数据快照（每次操作后从磁盘完整重建）
class _WikiSnapshot {
  const _WikiSnapshot({
    this.indexContent = '',
    this.wikiPages = const [],
    this.rawFiles = const [],
    this.todoFiles = const [],
    this.archivedTodoFiles = const [],
    this.metas = const {},
  });

  final String indexContent;
  final List<String> wikiPages;
  final List<String> rawFiles;
  final List<String> todoFiles;
  final List<String> archivedTodoFiles;
  final Map<String, WikiPageMeta> metas;
}

/// Wiki 知识库管理控制器（无缓存版）
///
/// 每次 [refresh] 都从磁盘完整重建 [_WikiSnapshot]。
/// 所有 getter 直接从快照读取，写操作完成后自动 [refresh]。
class WikiController extends ChangeNotifier {
  WikiController(this._ref) {
    refresh();
  }

  final Ref _ref;
  late final IWikiRepository _repo = _ref.read(wikiRepositoryProvider);

  _WikiSnapshot _snapshot = const _WikiSnapshot();

  // ── 同步 Getters（从快照读取） ──

  String get indexContent => _snapshot.indexContent;
  List<String> get wikiPages => _snapshot.wikiPages;
  List<String> get rawFiles => _snapshot.rawFiles;
  List<String> get todoFiles => _snapshot.todoFiles;
  List<String> get archivedTodoFiles => _snapshot.archivedTodoFiles;

  WikiPageMeta? metaOf(String relativePath) => _snapshot.metas[relativePath];

  List<String> get starredPaths => _snapshot.metas.entries
      .where((e) => e.value.starred)
      .map((e) => e.key)
      .toList();

  /// 从磁盘完整重建快照 + 通知 UI
  Future<void> refresh() async {
    try {
      final pages = await _repo.listPages();
      final raw = await _repo.listRawFiles();
      final todos = await _repo.listTodoFiles();
      final allTodos = await _repo.listTodoFiles(includeArchived: true);
      final activeSet = todos.toSet();
      final archived =
          allTodos.where((f) => !activeSet.contains(f)).toList();

      final metaCandidates = <String>[
        ...pages.where((p) => !p.startsWith('todos/')),
        ...todos,
        ...raw,
      ];
      final metas = <String, WikiPageMeta>{};
      await Future.wait(
        metaCandidates.map((p) async {
          final m = await _loadMeta(p);
          if (m != null) metas[p] = m;
        }),
      );

      _snapshot = _WikiSnapshot(
        indexContent: await _repo.readIndex(),
        wikiPages: pages,
        rawFiles: raw,
        todoFiles: todos,
        archivedTodoFiles: archived,
        metas: metas,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('刷新知识库失败：$e');
    }
  }

  /// 读取并解析单个文件的元数据
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

  /// 读取指定 Wiki 页面的内容
  Future<String> readPage(String fileName) async {
    try {
      return await _repo.readPage(fileName);
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
      await refresh();
    } catch (e) {
      debugPrint('保存页面失败：$e');
    }
  }

  /// 删除指定 Wiki 页面
  Future<void> deletePage(String fileName) async {
    try {
      await _repo.deletePage(fileName);
      await refresh();
    } catch (e) {
      debugPrint('删除页面失败：$e');
    }
  }

  /// 重命名 Wiki 页面
  Future<void> renameWikiPage(String oldName, String newName) async {
    if (oldName == newName) return;
    try {
      await _repo.renamePage(oldName, newName);
      await refresh();
    } catch (e) {
      debugPrint('重命名失败：$oldName → $newName / $e');
    }
  }

  /// 切换文件收藏状态
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
      if (current) newExtras.remove('starred_at');

      final updatedFm = fm.copyWith(extras: newExtras);
      if (relativePath.startsWith('todos/')) {
        await _repo.writeTodo(relativePath, body,
            frontMatterExtras: updatedFm.extras);
      } else {
        final newRaw = '${updatedFm.serialize()}\n$body';
        await _repo.writePage(relativePath, newRaw);
      }
      await refresh();
    } catch (e) {
      debugPrint('切换收藏失败：$relativePath / $e');
    }
  }

  // ── Todos API ──

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
      await _repo.writeTodo(fileName, body, frontMatterExtras: fm.extras);
      await refresh();
      return fileName;
    } catch (e) {
      debugPrint('创建 todo 失败：$e');
      return null;
    }
  }

  Future<WikiFrontMatter?> readTodoFrontMatter(String fileName) async {
    try {
      final content = await _repo.readPage(fileName);
      final (fm, _) = WikiFrontMatter.parse(content);
      return fm;
    } catch (_) {
      return null;
    }
  }

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
      await _repo.writeTodo(fileName, body, frontMatterExtras: updated.extras);
      await refresh();
    } catch (e) {
      debugPrint('更新 todo 失败：$e');
    }
  }

  Future<void> archiveTodo(String fileName) async {
    try {
      await _repo.archiveTodo(fileName);
      await refresh();
    } catch (e) {
      debugPrint('归档 todo 失败：$e');
    }
  }

  Future<void> unarchiveTodo(String fileName) async {
    try {
      await _repo.unarchiveTodo(fileName);
      await refresh();
    } catch (e) {
      debugPrint('取消归档 todo 失败：$e');
    }
  }

  Future<void> deleteTodo(String fileName) async {
    try {
      await _repo.deleteTodo(fileName);
      await refresh();
    } catch (e) {
      debugPrint('删除 todo 失败：$e');
    }
  }

  String _genId() {
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final seed = ts.hashCode.abs().toRadixString(36);
    return '$ts-$seed';
  }
}

final wikiControllerProvider = ChangeNotifierProvider<WikiController>(
  (ref) => WikiController(ref),
);

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
