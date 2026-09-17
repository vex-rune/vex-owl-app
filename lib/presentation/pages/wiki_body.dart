import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/controller/wiki_controller.dart';
import '../../core/model/wiki_front_matter.dart';
import '../../design_system/design_system.dart';
import '../widgets/widgets.dart';

/// Wiki 浏览器 Body 内容（v6.2）
///
/// 基于 Riverpod ChangeNotifierProvider，数据绑定到 [WikiController]。
/// 不包含 Scaffold/AppBar，由 HomePage Shell 统一管理。
///
/// v6.2 变更：
/// - 「浏览」改为文件管理器风格：所有顶层文件夹直接内联展开在该屏上，
///   每个文件夹卡片下显示其下的 Wiki 文件列表。点文件夹不需要跳到二级页，
///   直接在卡片内展开（类似 macOS Finder 列表视图）。
/// - 文件类型筛选从根视图的 2x2 Grid 改为顶部一行 chip，可组合文件夹视图。
/// - 文件夹排序按 updatedAt 最近；文件也按 updatedAt 倒序。
/// - 「最近」：按真实 `WikiPageMeta.updatedAt` 分组（今天 / 昨天 / 本周 / 更早）。
/// - 「收藏」：渲染 [WikiController.starredPaths]；空态展示引导。
/// - 「搜索」：三种视图都按搜索词过滤（标题 / 描述 / 文件名）。
/// - 长按菜单：收藏 / 取消收藏 / 删除 / 重命名。
class WikiBody extends ConsumerStatefulWidget {
  const WikiBody({super.key});

  @override
  ConsumerState<WikiBody> createState() => _WikiBodyState();
}

enum _WikiView { browse, recent, favorites }

class _WikiBodyState extends ConsumerState<WikiBody> {
  String _searchQuery = '';
  _WikiView _view = _WikiView.browse;

  /// 显式标记为「已展开」的文件夹名集合（默认全部展开；点标题可切换）。
  /// 若文件夹名不在此集合且默认状态为收起，则视为收起。
  final Set<String> _explicitlyExpanded = <String>{};

  /// 显式标记为「已收起」的文件夹名集合。
  final Set<String> _explicitlyCollapsed = <String>{};

  /// 默认行为：true = 默认全部展开；false = 默认全部收起。
  bool _defaultExpanded = true;

  /// 当前文件类型过滤：'all' / 'doc' / 'img' / 'video' / 'music'
  String _fileKindFilter = 'all';

  @override
  void initState() {
    super.initState();
    // 每次进入知识库页面，立即从文件系统刷新最新数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(wikiControllerProvider).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(wikiControllerProvider);
    final c = AppSemanticColors.of(context);

    final hasContent = controller.wikiPages.isNotEmpty ||
        controller.rawFiles.isNotEmpty ||
        controller.todoFiles.isNotEmpty;

    if (!hasContent) {
      return EmptyState(
        icon: Icons.library_books_outlined,
        title: '知识库为空',
        description: '通过对话或导入文档开始构建你的 LLM-Wiki',
        actionLabel: '导入知识',
        onAction: () => _showCreateMenu(context, controller),
      );
    }

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 100),
          children: [
            _buildTopBar(c),
            const SizedBox(height: 12),
            _buildViewChips(c),
            const SizedBox(height: 16),
            if (_view == _WikiView.browse)
              _buildBrowseView(context, controller, c)
            else if (_view == _WikiView.recent)
              _buildRecentView(context, controller, c)
            else
              _buildFavoritesView(context, controller, c),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: GlowFab(
            icon: Icons.add,
            onPressed: () => _showCreateMenu(context, controller),
            heroTag: 'wiki_fab',
          ),
        ),
      ],
    );
  }

  // ────────────────────────────────────────────
  //  顶部：搜索 + 视图切换 chips
  // ────────────────────────────────────────────

  Widget _buildTopBar(AppSemanticColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pageHorizontal,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              style: AppTypography.bodyMedium.copyWith(color: c.textPrimary),
              decoration: InputDecoration(
                hintText: '搜索 Wiki 页面 / 待办...',
                hintStyle:
                    AppTypography.bodySmall.copyWith(color: c.textDisabled),
                prefixIcon: Icon(Icons.search, size: 20, color: c.textTertiary),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        color: c.textTertiary,
                        onPressed: () => setState(() => _searchQuery = ''),
                      )
                    : null,
                filled: true,
                fillColor: c.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 刷新按钮：重新扫描文件系统
          IconButton(
            onPressed: () async {
              final controller = ref.read(wikiControllerProvider);
              await controller.refresh();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('已刷新知识库'),
                    duration: const Duration(seconds: 1),
                    backgroundColor: c.success,
                  ),
                );
              }
            },
            icon: Icon(Icons.refresh, size: 22, color: c.textSecondary),
            tooltip: '刷新',
            style: IconButton.styleFrom(
              backgroundColor: c.surfaceVariant,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: c.border, width: 0.5),
              ),
              padding: const EdgeInsets.all(10),
              minimumSize: Size.zero,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewChips(AppSemanticColors c) {
    final entries = <(_WikiView, IconData, String)>[
      (_WikiView.browse, Icons.folder_outlined, '浏览'),
      (_WikiView.recent, Icons.history, '最近'),
      (_WikiView.favorites, Icons.star_border, '收藏'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pageHorizontal,
      ),
      child: Row(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            _ViewChip(
              icon: entries[i].$2,
              label: entries[i].$3,
              selected: _view == entries[i].$1,
              onTap: () => setState(() {
                _view = entries[i].$1;
                _fileKindFilter = 'all';
              }),
            ),
            if (i < entries.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  // ────────────────────────────────────────────
  //  形态 A：浏览（v6.2 文件管理器风格：文件夹内联展开）
  // ────────────────────────────────────────────

  Widget _buildBrowseView(
    BuildContext context,
    WikiController controller,
    AppSemanticColors c,
  ) {
    final allFiles = <String>[
      ...controller.wikiPages.where((p) => !p.startsWith('todos/')),
      ...controller.rawFiles,
    ];

    final counts = _countByKind(allFiles);

    // 按文件夹分组
    final grouped = _groupByTopFolder(controller);
    if (grouped.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.pageHorizontal,
          vertical: 24,
        ),
        child: Center(
          child: Text(
            '暂无 Wiki 文件，AI 在对话中会自动创建分组',
            style: AppTypography.bodySmall.copyWith(color: c.textTertiary),
          ),
        ),
      );
    }

    // 文件夹排序：按该文件夹下文件最新 updatedAt 倒序
    final sortedFolders = grouped.keys.toList()
      ..sort((a, b) => _folderLatestUpdated(grouped[a]!, controller)
          .compareTo(_folderLatestUpdated(grouped[b]!, controller)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFileKindFilterBar(c, counts),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.pageHorizontal,
          ),
          child: Row(
            children: [
              Text(
                '文件夹',
                style: AppTypography.labelMedium.copyWith(
                  color: c.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() {
                  _explicitlyExpanded.clear();
                  _explicitlyCollapsed.clear();
                  _defaultExpanded = !_defaultExpanded;
                }),
                icon: Icon(
                  _defaultExpanded
                      ? Icons.unfold_less
                      : Icons.unfold_more,
                  size: 16,
                  color: c.primary,
                ),
                label: Text(
                  _defaultExpanded ? '全部收起' : '全部展开',
                  style: AppTypography.bodySmall.copyWith(color: c.primary),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        ...sortedFolders.map((folder) {
          final files = grouped[folder]!;
          final filteredFiles = _filterFilesByKind(files, controller);
          final expanded = _isFolderExpanded(folder);
          return _FolderExpandableCard(
            name: folder,
            files: filteredFiles,
            totalCount: files.length,
            visibleCount: filteredFiles.length,
            expanded: expanded,
            controller: controller,
            onToggle: () => setState(() {
              final isExpanded = _isFolderExpanded(folder);
              if (isExpanded) {
                _explicitlyCollapsed.add(folder);
                _explicitlyExpanded.remove(folder);
              } else {
                _explicitlyExpanded.add(folder);
                _explicitlyCollapsed.remove(folder);
              }
            }),
            onFileTap: (f) => _openItem(context, controller, f),
            onFileLongPress: (f) => _showFileActions(context, controller, f),
          );
        }),
        const SizedBox(height: 12),
      ],
    );
  }

  /// 文件类型筛选 chips（顶部一行）
  Widget _buildFileKindFilterBar(
    AppSemanticColors c,
    Map<String, int> counts,
  ) {
    final entries = <(String, IconData, String)>[
      ('all', Icons.all_inclusive, '全部'),
      ('doc', Icons.description_outlined, '文档'),
      ('img', Icons.image_outlined, '图片'),
      ('video', Icons.movie_outlined, '视频'),
      ('music', Icons.music_note_outlined, '音乐'),
    ];
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.pageHorizontal,
        ),
        children: [
          for (final e in entries) ...[
            _ViewChip(
              icon: e.$2,
              label:
                  e.$1 == 'all' ? e.$3 : '${e.$3} · ${counts[e.$1] ?? 0}',
              selected: _fileKindFilter == e.$1,
              onTap: () => setState(() => _fileKindFilter = e.$1),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  /// 按顶层文件夹分组
  Map<String, List<String>> _groupByTopFolder(WikiController controller) {
    final out = <String, List<String>>{};
    for (final p in controller.wikiPages) {
      if (p.startsWith('todos/')) continue;
      final parts = p.split('/');
      if (parts.length >= 2) {
        out.putIfAbsent(parts.first, () => []).add(p);
      }
    }
    for (final p in controller.rawFiles) {
      final parts = p.split('/');
      if (parts.length >= 2) {
        out.putIfAbsent(parts.first, () => []).add(p);
      } else if (parts.isNotEmpty) {
        // raw 顶层文件归到 'raw'
        out.putIfAbsent('raw', () => []).add(p);
      }
    }
    return out;
  }

  /// 文件夹下最新更新时间（用于文件夹排序）
  DateTime _folderLatestUpdated(
    List<String> files,
    WikiController controller,
  ) {
    DateTime? latest;
    for (final f in files) {
      final t = controller.metaOf(f)?.updatedAt;
      if (t == null) continue;
      if (latest == null || t.isAfter(latest)) latest = t;
    }
    return latest ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// 当前文件类型筛选 + 搜索后的文件列表
  List<String> _filterFilesByKind(
    List<String> files,
    WikiController controller,
  ) {
    var result = files;
    if (_fileKindFilter != 'all') {
      final exts = _extsForKind(_fileKindFilter);
      result = result
          .where((p) => exts.any((ext) => p.toLowerCase().endsWith(ext)))
          .toList();
    }
    return _applySearch(result, controller);
  }

  bool _isFolderExpanded(String folder) {
    if (_explicitlyExpanded.contains(folder)) return true;
    if (_explicitlyCollapsed.contains(folder)) return false;
    return _defaultExpanded;
  }

  Widget _buildEmptyHint(AppSemanticColors c, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Text(
          text,
          style: AppTypography.bodyMedium.copyWith(color: c.textTertiary),
        ),
      ),
    );
  }

  // ────────────────────────────────────────────
  //  形态 B：最近（按真实更新时间分组）
  // ────────────────────────────────────────────

  Widget _buildRecentView(
    BuildContext context,
    WikiController controller,
    AppSemanticColors c,
  ) {
    // 把所有可见条目 + 真实 updatedAt 拼成 _RecentItem
    final items = <_RecentItem>[];
    for (final p in controller.wikiPages) {
      items.add(_RecentItem.fromPath(p, controller.metaOf(p)?.updatedAt));
    }
    for (final p in controller.todoFiles) {
      items.add(_RecentItem.fromPath(p, controller.metaOf(p)?.updatedAt));
    }
    for (final p in controller.rawFiles) {
      items.add(_RecentItem.fromPath(p, controller.metaOf(p)?.updatedAt));
    }

    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            '暂无最近活动',
            style: AppTypography.bodyMedium.copyWith(color: c.textTertiary),
          ),
        ),
      );
    }

    // 按 updatedAt 倒序
    items.sort((a, b) {
      if (a.date == null && b.date == null) return 0;
      if (a.date == null) return 1;
      if (b.date == null) return -1;
      return b.date!.compareTo(a.date!);
    });

    // 应用搜索过滤
    final query = _searchQuery.trim().toLowerCase();
    final filtered = query.isEmpty
        ? items
        : items.where((it) {
            final m = controller.metaOf(it.path);
            return it.path.toLowerCase().contains(query) ||
                it.title.toLowerCase().contains(query) ||
                (m?.description.toLowerCase().contains(query) ?? false);
          }).toList();

    // 分桶：今天 / 昨天 / 前天 / 本周早些时候 / 上周 / 更早
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final today = <_RecentItem>[];
    final yesterday = <_RecentItem>[];
    final dayBeforeYesterday = <_RecentItem>[];
    final earlierThisWeek = <_RecentItem>[];
    final lastWeek = <_RecentItem>[];
    final older = <String, List<_RecentItem>>{};

    for (final it in filtered) {
      final d = it.date;
      if (d == null) {
        older.putIfAbsent('更早', () => <_RecentItem>[]).add(it);
        continue;
      }
      final dayDiff =
          startOfToday.difference(DateTime(d.year, d.month, d.day)).inDays;
      if (dayDiff <= 0) {
        today.add(it);
      } else if (dayDiff == 1) {
        yesterday.add(it);
      } else if (dayDiff == 2) {
        dayBeforeYesterday.add(it);
      } else if (dayDiff < 7) {
        earlierThisWeek.add(it);
      } else if (dayDiff < 14) {
        lastWeek.add(it);
      } else {
        final key = '${d.year}/'
            '${d.month.toString().padLeft(2, '0')}';
        older.putIfAbsent(key, () => <_RecentItem>[]).add(it);
      }
    }

    final groups = <(String, List<_RecentItem>)>[
      ('今天', today),
      ('昨天', yesterday),
      ('前天', dayBeforeYesterday),
      ('本周早些时候', earlierThisWeek),
      ('上周', lastWeek),
    ];
    final olderKeys = older.keys.toList()..sort((a, b) {
      if (a == '更早') return 1;
      if (b == '更早') return -1;
      return b.compareTo(a);
    });
    for (final k in olderKeys) {
      groups.add((k, older[k]!));
    }

    if (filtered.isEmpty) {
      return _buildEmptyHint(c, '没有匹配「${_searchQuery.trim()}」的最近活动');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final g in groups)
          if (g.$2.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pageHorizontal,
                vertical: 6,
              ),
              child: Text(
                g.$1,
                style: AppTypography.labelMedium.copyWith(
                  color: c.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pageHorizontal,
              ),
              child: Column(
                children: [
                  for (final it in g.$2)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _RecentTile(
                        item: it,
                        meta: controller.metaOf(it.path),
                        onTap: () => _openItem(context, controller, it.path),
                        onLongPress: () =>
                            _showFileActions(context, controller, it.path),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }

  // ────────────────────────────────────────────
  //  形态 C：收藏
  // ────────────────────────────────────────────

  Widget _buildFavoritesView(
    BuildContext context,
    WikiController controller,
    AppSemanticColors c,
  ) {
    final starred = controller.starredPaths.toList();
    if (starred.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.star_border, size: 40, color: c.textTertiary),
              const SizedBox(height: 12),
              Text(
                '暂无收藏',
                style: AppTypography.bodyLarge.copyWith(
                  color: c.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '在文件卡片上长按菜单中标记收藏后会汇总到这里',
                style: AppTypography.bodySmall.copyWith(color: c.textDisabled),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // 按更新时间倒序
    starred.sort((a, b) {
      final am = controller.metaOf(a)?.updatedAt;
      final bm = controller.metaOf(b)?.updatedAt;
      if (am == null && bm == null) return a.compareTo(b);
      if (am == null) return 1;
      if (bm == null) return -1;
      return bm.compareTo(am);
    });

    final filtered = _applySearch(starred, controller);

    if (filtered.isEmpty) {
      return _buildEmptyHint(c, '收藏中没有匹配「${_searchQuery.trim()}」的文件');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.pageHorizontal,
            vertical: 4,
          ),
          child: Row(
            children: [
              Icon(Icons.star, size: 16, color: c.warning),
              const SizedBox(width: 6),
              Text(
                '我的收藏 · ${filtered.length} 项',
                style: AppTypography.bodySmall.copyWith(
                  color: c.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        ...filtered.map(
          (f) => _WikiFileRow(
            path: f,
            controller: controller,
            onTap: () => _openItem(context, controller, f),
            onLongPress: () => _showFileActions(context, controller, f),
          ),
        ),
      ],
    );
  }

  // ────────────────────────────────────────────
  //  通用工具
  // ────────────────────────────────────────────

  Map<String, int> _countByKind(List<String> files) {
    final exts = <String, List<String>>{
      'doc': ['.md', '.txt'],
      'img': ['.png', '.jpg', '.jpeg', '.gif', '.webp'],
      'video': ['.mp4', '.mov', '.avi'],
      'music': ['.mp3', '.wav', '.flac'],
    };
    final counts = <String, int>{
      'doc': 0,
      'img': 0,
      'video': 0,
      'music': 0,
    };
    for (final p in files) {
      final lower = p.toLowerCase();
      exts.forEach((k, list) {
        if (list.any((e) => lower.endsWith(e))) {
          counts[k] = (counts[k] ?? 0) + 1;
        }
      });
    }
    return counts;
  }

  List<String> _extsForKind(String kind) {
    switch (kind) {
      case 'doc':
        return ['.md', '.txt'];
      case 'img':
        return ['.png', '.jpg', '.jpeg', '.gif', '.webp'];
      case 'video':
        return ['.mp4', '.mov', '.avi'];
      case 'music':
        return ['.mp3', '.wav', '.flac'];
    }
    return const [];
  }

  List<String> _applySearch(List<String> files, WikiController controller) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return files;
    return files.where((p) {
      final m = controller.metaOf(p);
      return p.toLowerCase().contains(query) ||
          (m?.title.toLowerCase().contains(query) ?? false) ||
          (m?.description.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  // ────────────────────────────────────────────
  //  交互
  // ────────────────────────────────────────────

  void _openItem(BuildContext context, WikiController controller, String path) {
    _openPage(context, controller, path);
  }

  void _openPage(
    BuildContext context,
    WikiController controller,
    String fileName,
  ) async {
    final c = AppSemanticColors.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: CircularProgressIndicator(color: c.primary),
      ),
    );

    final content = await controller.readPage(fileName);

    if (!mounted) return;
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    if (content.isEmpty) return;

    if (context.mounted) {
      _showMarkdownViewer(context, fileName, content);
    }
  }

  void _showMarkdownViewer(
    BuildContext context,
    String title,
    String content,
  ) {
    final c = AppSemanticColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final mediaHeight = MediaQuery.of(ctx).size.height;
        return SizedBox(
          height: mediaHeight * 0.85,
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: c.textDisabled,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: AppTypography.titleMedium
                            .copyWith(color: c.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      color: c.textTertiary,
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              Divider(height: 0.5, color: c.divider),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SimpleMarkdownText(content: content),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showFileActions(
    BuildContext context,
    WikiController controller,
    String fileName,
  ) {
    final c = AppSemanticColors.of(context);
    final meta = controller.metaOf(fileName);
    final starred = meta?.starred ?? false;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: c.textDisabled,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meta?.title.isNotEmpty == true
                        ? meta!.title
                        : fileName.split('/').last,
                    style: AppTypography.titleMedium
                        .copyWith(color: c.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (fileName.contains('/'))
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        fileName,
                        style: AppTypography.bodySmall
                            .copyWith(color: c.textTertiary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            Divider(height: 0.5, color: c.divider),
            ListTile(
              leading: Icon(
                starred ? Icons.star : Icons.star_border,
                color: starred ? c.warning : c.textSecondary,
              ),
              title: Text(starred ? '取消收藏' : '收藏'),
              onTap: () async {
                Navigator.pop(ctx);
                await controller.toggleStarred(fileName);
                if (mounted) setState(() {});
              },
            ),
            ListTile(
              leading: Icon(Icons.drive_file_rename_outline,
                  color: c.textSecondary),
              title: const Text('重命名'),
              onTap: () {
                Navigator.pop(ctx);
                _showRenameDialog(context, controller, fileName);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: c.error),
              title: Text('删除', style: TextStyle(color: c.error)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(context, controller, fileName);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(
    BuildContext context,
    WikiController controller,
    String fileName,
  ) {
    final nameCtrl = TextEditingController(
      text: fileName.split('/').last.replaceAll('.md', ''),
    );
    final c = AppSemanticColors.of(context);
    final isInSubdir = fileName.contains('/');
    final folderPrefix = isInSubdir
        ? fileName.substring(0, fileName.lastIndexOf('/') + 1)
        : '';

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text('重命名',
            style: TextStyle(color: c.textPrimary, fontSize: 16)),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          style: AppTypography.bodyMedium.copyWith(color: c.textPrimary),
          decoration: InputDecoration(
            hintText: '新名称',
            hintStyle:
                AppTypography.bodySmall.copyWith(color: c.textDisabled),
            filled: true,
            fillColor: c.surfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: c.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: c.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: c.borderFocus),
            ),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final raw = nameCtrl.text.trim();
              if (raw.isEmpty) {
                Navigator.pop(ctx);
                return;
              }
              final newName = '$folderPrefix$raw.md';
              if (newName == fileName) {
                Navigator.pop(ctx);
                return;
              }
              await controller.renameWikiPage(fileName, newName);
              if (mounted) setState(() {});
              if (context.mounted) Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    WikiController controller,
    String fileName,
  ) {
    final c = AppSemanticColors.of(context);
    final isTodo = fileName.startsWith('todos/');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(
          isTodo ? '删除待办' : '删除页面',
          style: TextStyle(color: c.error, fontSize: 16),
        ),
        content: Text(
          '确定要删除「$fileName」吗？此操作不可恢复。',
          style: AppTypography.bodyMedium
              .copyWith(color: c.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: c.error),
            onPressed: () async {
              if (isTodo) {
                await controller.deleteTodo(fileName);
              } else {
                await controller.deletePage(fileName);
              }
              if (mounted) setState(() {});
              if (context.mounted) Navigator.pop(ctx);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _showCreateMenu(BuildContext context, WikiController controller) {
    final c = AppSemanticColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: c.textDisabled,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Icon(Icons.check_circle_outline, color: c.primary),
              title: const Text('新建待办（推荐）'),
              subtitle: const Text('多文件并发，每条 todo 独立管理'),
              onTap: () {
                Navigator.pop(ctx);
                _showNewTodoDialog(context, controller);
              },
            ),
            ListTile(
              leading: Icon(Icons.add_circle_outline, color: c.primary),
              title: const Text('新建 Wiki 页面'),
              onTap: () {
                Navigator.pop(ctx);
                _showNewPageDialog(context, controller);
              },
            ),
            ListTile(
              leading: Icon(Icons.upload_file_outlined, color: c.accent),
              title: const Text('导入 PDF / 文档'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showNewPageDialog(BuildContext context, WikiController controller) {
    final nameCtrl = TextEditingController();
    final c = AppSemanticColors.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text('新建 Wiki 页面',
            style: TextStyle(color: c.textPrimary, fontSize: 16)),
        content: TextField(
          controller: nameCtrl,
          style: AppTypography.bodyMedium
              .copyWith(color: c.textPrimary),
          decoration: InputDecoration(
            hintText: '页面名称（如 project-vex.md）',
            hintStyle: AppTypography.bodySmall
                .copyWith(color: c.textDisabled),
            filled: true,
            fillColor: c.surfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: c.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: c.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: c.borderFocus),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('页面名称不能为空')),
                );
                return;
              }
              final fileName =
                  name.endsWith('.md') ? name : '$name.md';
              await controller.writePage(fileName, '# $fileName\n\n');
              if (mounted) setState(() {});
              if (context.mounted) Navigator.pop(ctx);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  void _showNewTodoDialog(BuildContext context, WikiController controller) {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final c = AppSemanticColors.of(context);
    String priority = 'medium';

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: c.surface,
          title: Text('新建待办',
              style: TextStyle(color: c.textPrimary, fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: titleCtrl,
                  style: AppTypography.bodyMedium
                      .copyWith(color: c.textPrimary),
                  decoration: InputDecoration(
                    labelText: '标题',
                    hintText: '如：修复登录页崩溃',
                    filled: true,
                    fillColor: c.surfaceVariant,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: c.border),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  maxLines: 3,
                  style: AppTypography.bodyMedium
                      .copyWith(color: c.textPrimary),
                  decoration: InputDecoration(
                    labelText: '描述',
                    hintText: '一句话说明',
                    filled: true,
                    fillColor: c.surfaceVariant,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: c.border),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '优先级',
                  style: AppTypography.bodySmall
                      .copyWith(color: c.textSecondary),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: ['low', 'medium', 'high', 'urgent'].map((p) {
                    final selected = p == priority;
                    return ChoiceChip(
                      label: Text(p),
                      selected: selected,
                      onSelected: (_) => setLocal(() => priority = p),
                      selectedColor: c.primary,
                      backgroundColor: c.surfaceVariant,
                      labelStyle: AppTypography.bodySmall.copyWith(
                        color: selected ? Colors.white : c.textPrimary,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('标题不能为空')),
                  );
                  return;
                }
                final created = await controller.createTodo(
                  title: title,
                  description: descCtrl.text.trim(),
                  priority: priority,
                );
                if (mounted) setState(() {});
                if (created != null && ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 浏览视图中的「文件夹」卡片：点击标题行可展开 / 收起，内部内联展示文件列表。
class _FolderExpandableCard extends StatelessWidget {
  const _FolderExpandableCard({
    required this.name,
    required this.files,
    required this.totalCount,
    required this.visibleCount,
    required this.expanded,
    required this.controller,
    required this.onToggle,
    required this.onFileTap,
    required this.onFileLongPress,
  });

  final String name;
  final List<String> files;
  final int totalCount;
  final int visibleCount;
  final bool expanded;
  final WikiController controller;
  final VoidCallback onToggle;
  final ValueChanged<String> onFileTap;
  final ValueChanged<String> onFileLongPress;

  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            margin: const EdgeInsets.symmetric(
              horizontal: AppSpacing.pageHorizontal,
              vertical: 4,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: c.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    Icons.folder_outlined,
                    size: 19,
                    color: c.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    style: AppTypography.bodyMedium.copyWith(
                      color: c.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  visibleCount == totalCount
                      ? '$totalCount'
                      : '$visibleCount/$totalCount',
                  style: AppTypography.bodySmall.copyWith(color: c.textTertiary),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.expand_more,
                    size: 20,
                    color: c.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...[
          if (files.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pageHorizontal,
                vertical: 12,
              ),
              child: Text(
                '该文件夹下暂无匹配文件',
                style: AppTypography.bodySmall.copyWith(color: c.textTertiary),
              ),
            )
          else
            ...files.map(
              (f) => _WikiFileRow(
                path: f,
                controller: controller,
                onTap: () => onFileTap(f),
                onLongPress: () => onFileLongPress(f),
              ),
            ),
        ],
      ],
    );
  }
}

/// Wiki 文件行（浏览 / 收藏视图通用）
class _WikiFileRow extends StatelessWidget {
  const _WikiFileRow({
    required this.path,
    required this.controller,
    required this.onTap,
    required this.onLongPress,
  });

  final String path;
  final WikiController controller;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    final meta = controller.metaOf(path);
    final iconInfo = _iconFor(path);
    final title = (meta?.title.isNotEmpty ?? false)
        ? meta!.title
        : path.split('/').last.replaceAll('.md', '');
    final subtitle = (meta?.description.isNotEmpty ?? false)
        ? meta!.description
        : _humanUpdatedAt(meta?.updatedAt);
    final trailingTime = _formatRelativeTime(meta?.updatedAt);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.pageHorizontal,
          vertical: 4,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: iconInfo.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(iconInfo.icon, size: 20, color: iconInfo.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: AppTypography.bodyMedium.copyWith(
                            color: c.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (meta?.starred == true) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.star, size: 14, color: c.warning),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTypography.bodySmall
                        .copyWith(color: c.textTertiary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (trailingTime.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                trailingTime,
                style: AppTypography.bodySmall.copyWith(
                  color: c.textTertiary,
                  fontSize: 11,
                ),
              ),
            ],
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: c.textTertiary),
          ],
        ),
      ),
    );
  }

  _IconInfo _iconFor(String path) {
    if (path.startsWith('todos/')) {
      return _IconInfo(Icons.check_box_outlined, const Color(0xFFFF6B9D));
    }
    if (path.endsWith('.png') ||
        path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.gif') ||
        path.endsWith('.webp')) {
      return _IconInfo(Icons.image_outlined, const Color(0xFFFFB23F));
    }
    if (path.endsWith('.mp4') || path.endsWith('.mov') || path.endsWith('.avi')) {
      return _IconInfo(Icons.movie_outlined, const Color(0xFFFF6B9D));
    }
    if (path.endsWith('.mp3') || path.endsWith('.wav') || path.endsWith('.flac')) {
      return _IconInfo(Icons.music_note_outlined, const Color(0xFF5DD5C4));
    }
    if (path.endsWith('.md') || path.endsWith('.txt')) {
      return _IconInfo(Icons.description_outlined, const Color(0xFF4D6EF5));
    }
    return _IconInfo(Icons.menu_book_outlined, const Color(0xFF5DD5C4));
  }

  String _humanUpdatedAt(DateTime? d) {
    if (d == null) return '';
    return _formatRelativeTime(d);
  }

  String _formatRelativeTime(DateTime? d) {
    if (d == null) return '';
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) {
      final hh = d.hour.toString().padLeft(2, '0');
      final mm = d.minute.toString().padLeft(2, '0');
      return '今天 $hh:$mm';
    }
    if (diff.inDays < 2) {
      final hh = d.hour.toString().padLeft(2, '0');
      final mm = d.minute.toString().padLeft(2, '0');
      return '昨天 $hh:$mm';
    }
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    if (d.year == now.year) {
      return '${d.month}/${d.day}';
    }
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  }
}

class _IconInfo {
  const _IconInfo(this.icon, this.color);
  final IconData icon;
  final Color color;
}

/// 待办卡片（v6：每条 todo 一张卡，含状态/优先级徽章）
class _TodoTile extends StatefulWidget {
  const _TodoTile({
    required this.fileName,
    required this.controller,
  });

  final String fileName;
  final WikiController controller;

  @override
  State<_TodoTile> createState() => _TodoTileState();
}

class _TodoTileState extends State<_TodoTile> {
  WikiFrontMatter? _fm;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _TodoTile old) {
    super.didUpdateWidget(old);
    if (old.fileName != widget.fileName) _load();
  }

  Future<void> _load() async {
    final fm = await widget.controller.readTodoFrontMatter(widget.fileName);
    if (!mounted) return;
    setState(() {
      _fm = fm;
      _loading = false;
    });
  }

  Color _statusColor(String? status, AppSemanticColors c) {
    switch (status) {
      case 'done':
        return c.success;
      case 'in_progress':
        return c.primary;
      case 'cancelled':
        return c.textTertiary;
      default:
        return c.warning;
    }
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'done':
        return '已完成';
      case 'in_progress':
        return '进行中';
      case 'cancelled':
        return '已取消';
      default:
        return '待办';
    }
  }

  Color _priorityColor(String? priority, AppSemanticColors c) {
    switch (priority) {
      case 'urgent':
        return c.error;
      case 'high':
        return c.warning;
      case 'low':
        return c.textTertiary;
      default:
        return c.primary;
    }
  }

  String _priorityLabel(String? priority) {
    switch (priority) {
      case 'urgent':
        return '紧急';
      case 'high':
        return '高';
      case 'low':
        return '低';
      default:
        return '中';
    }
  }

  void _showActions() {
    final c = AppSemanticColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: c.textDisabled,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                _fm?.title ?? widget.fileName,
                style: AppTypography.titleMedium
                    .copyWith(color: c.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Divider(height: 0.5, color: c.divider),
            ListTile(
                leading:
                    Icon(Icons.play_arrow_outlined, color: c.primary),
                title: const Text('标记为进行中'),
              ),
              ListTile(
                leading: Icon(Icons.check, color: c.success),
                title: const Text('标记为已完成'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await widget.controller
                      .updateTodoStatus(widget.fileName, 'done');
                },
              ),
              ListTile(
                leading: Icon(Icons.archive_outlined, color: c.warning),
                title: const Text('归档'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await widget.controller.archiveTodo(widget.fileName);
                },
              ),
              ListTile(
                leading:
                    Icon(Icons.unarchive_outlined, color: c.primary),
                title: const Text('取消归档'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await widget.controller.unarchiveTodo(widget.fileName);
                },
              ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: c.error),
              title: Text('删除', style: TextStyle(color: c.error)),
              onTap: () async {
                Navigator.pop(ctx);
                await widget.controller.deleteTodo(widget.fileName);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _view() async {
    final c = AppSemanticColors.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: CircularProgressIndicator(color: c.primary),
      ),
    );
    final content = await widget.controller.readPage(widget.fileName);
    if (!mounted) return;
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (content.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final mediaHeight = MediaQuery.of(ctx).size.height;
        return SizedBox(
          height: mediaHeight * 0.85,
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: c.textDisabled,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _fm?.title ?? widget.fileName,
                        style: AppTypography.titleMedium
                            .copyWith(color: c.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      color: c.textTertiary,
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              Divider(height: 0.5, color: c.divider),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SimpleMarkdownText(content: content),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox.shrink();
    }
    final fm = _fm;
    if (fm == null) return const SizedBox.shrink();

    final c = AppSemanticColors.of(context);
    final status = fm.extras['status'] as String? ?? 'pending';
    final priority = fm.extras['priority'] as String? ?? 'medium';
    final description = fm.description.isEmpty
        ? (fm.extras['description'] as String? ?? '')
        : fm.description;

    return GestureDetector(
      onTap: _view,
      onLongPress: _showActions,
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.pageHorizontal,
          vertical: 4,
        ),
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: c.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Badge(
                  label: _statusLabel(status),
                  color: _statusColor(status, c),
                  icon: status == 'done' ? Icons.check_circle : Icons.circle_outlined,
                ),
                const SizedBox(width: 6),
                _Badge(
                  label: _priorityLabel(priority),
                  color: _priorityColor(priority, c),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              fm.title,
              style: AppTypography.bodyLarge.copyWith(
                color: c.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                description,
                style: AppTypography.bodySmall.copyWith(
                  color: c.textSecondary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 简单徽章（状态/优先级）
class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════
//  视图 chips + 浏览 / 最近 / 收藏 视图组件
// ════════════════════════════════════════════════════════

class _ViewChip extends StatelessWidget {
  const _ViewChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? c.primary : c.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14, color: selected ? c.onPrimary : c.textPrimary),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: selected ? c.onPrimary : c.textPrimary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 「最近」视图条目（path + 真实 updatedAt）
class _RecentItem {
  _RecentItem({
    required this.path,
    required this.title,
    required this.category,
    required this.date,
  });
  final String path;
  final String title;
  final String category;
  final DateTime? date;

  factory _RecentItem.fromPath(String path, DateTime? date) {
    final name = path.split('/').last;
    final stem = name.contains('.')
        ? name.substring(0, name.lastIndexOf('.'))
        : name;
    final parts = path.split('/');
    String category;
    if (parts.length >= 2) {
      category = _categoryLabel(parts.first);
    } else if (path.startsWith('todos/')) {
      category = '待办';
    } else {
      category = '知识';
    }
    return _RecentItem(path: path, title: stem, category: category, date: date);
  }

  static String _categoryLabel(String key) {
    switch (key) {
      case 'todos':
        return '待办';
      case 'concepts':
        return '知识';
      case 'sessions':
        return '会话';
      default:
        return key;
    }
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({
    required this.item,
    required this.meta,
    required this.onTap,
    required this.onLongPress,
  });
  final _RecentItem item;
  final WikiPageMeta? meta;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    final iconInfo = _iconFor(item.path);
    final title = (meta?.title.isNotEmpty ?? false)
        ? meta!.title
        : item.title;
    final subtitleParts = <String>[
      item.category,
      if (item.date != null) _formatTime(item.date!),
    ];
    final timeLabel = subtitleParts.join(' · ');

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: iconInfo.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(iconInfo.icon, size: 20, color: iconInfo.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: AppTypography.bodyMedium.copyWith(
                            color: c.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (meta?.starred == true) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.star, size: 14, color: c.warning),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    timeLabel,
                    style: AppTypography.bodySmall
                        .copyWith(color: c.textTertiary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: c.textTertiary),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  _IconInfo _iconFor(String path) {
    if (path.startsWith('todos/')) {
      return _IconInfo(Icons.check_box_outlined, const Color(0xFFFF6B9D));
    }
    if (path.endsWith('.png') ||
        path.endsWith('.jpg') ||
        path.endsWith('.jpeg')) {
      return _IconInfo(Icons.image_outlined, const Color(0xFFFFB23F));
    }
    if (path.endsWith('.md') || path.endsWith('.txt')) {
      return _IconInfo(Icons.description_outlined, const Color(0xFF4D6EF5));
    }
    if (path.endsWith('.mp4') || path.endsWith('.mov')) {
      return _IconInfo(Icons.movie_outlined, const Color(0xFFFF6B9D));
    }
    if (path.endsWith('.mp3') || path.endsWith('.wav')) {
      return _IconInfo(Icons.music_note_outlined, const Color(0xFF5DD5C4));
    }
    return _IconInfo(Icons.menu_book_outlined, const Color(0xFF5DD5C4));
  }
}