import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/controller/wiki_controller.dart';
import '../../core/model/wiki_front_matter.dart';
import '../../design_system/design_system.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/widgets.dart';

/// Wiki 浏览器 Body 内容（v5）
///
/// 基于 Riverpod ChangeNotifierProvider，数据绑定到 [WikiController]。
/// 不包含 Scaffold/AppBar，由 HomePage Shell 统一管理。
///
/// v5 变更：
/// - 新增 Todos 分区（多文件，每个 todo 独立卡片）
/// - 文件按 front-matter 的 `weight` 升序展示
/// - todos/concepts/sessions/profile 分组显示
class WikiBody extends ConsumerStatefulWidget {
  const WikiBody({super.key});

  @override
  ConsumerState<WikiBody> createState() => _WikiBodyState();
}

class _WikiBodyState extends ConsumerState<WikiBody> {
  String _searchQuery = '';
  bool _showArchivedTodos = false;

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

    // 根据搜索词过滤列表
    final query = _searchQuery.toLowerCase();
    bool matches(String name) =>
        query.isEmpty || name.toLowerCase().contains(query);

    final filteredWiki = controller.wikiPages
        .where((p) => matches(p) && !p.startsWith('todos/'))
        .toList();
    final filteredTodo = controller.todoFiles.where(matches).toList();
    final filteredArchivedTodo = _showArchivedTodos
        ? controller.archivedTodoFiles.where(matches).toList()
        : <String>[];
    final filteredRaw = controller.rawFiles.where(matches).toList();
    final showSystem = query.isEmpty ||
        'index.md'.toLowerCase().contains(query) ||
        'schema.md'.toLowerCase().contains(query);

    final hasFilteredContent = filteredWiki.isNotEmpty ||
        filteredTodo.isNotEmpty ||
        filteredArchivedTodo.isNotEmpty ||
        filteredRaw.isNotEmpty ||
        showSystem;

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 100),
          children: [
            _buildSearchBar(),
            if (!hasFilteredContent)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    '未找到匹配「$query」的结果',
                    style: AppTypography.bodyMedium
                        .copyWith(color: c.textTertiary),
                  ),
                ),
              ),

            // ── 待办（v5：每条独立卡片） ──
            if (filteredTodo.isNotEmpty) ...[
              _buildSectionHeader(
                '待办',
                Icons.check_circle_outline,
                filteredTodo.length,
                action: filteredArchivedTodo.isNotEmpty ||
                        controller.archivedTodoFiles.isNotEmpty
                    ? TextButton(
                        onPressed: () => setState(
                          () => _showArchivedTodos = !_showArchivedTodos,
                        ),
                        child: Text(
                          _showArchivedTodos ? '隐藏已归档' : '显示已归档',
                          style: AppTypography.bodySmall.copyWith(
                            color: c.primary,
                          ),
                        ),
                      )
                    : null,
              ),
              ...filteredTodo.map(
                (file) => _TodoTile(
                  fileName: file,
                  controller: controller,
                ),
              ),
            ],

            // ── 已归档 todos ──
            if (filteredArchivedTodo.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildSectionHeader(
                '已归档',
                Icons.archive_outlined,
                filteredArchivedTodo.length,
              ),
              ...filteredArchivedTodo.map(
                (file) => _TodoTile(
                  fileName: file,
                  controller: controller,
                  archived: true,
                ),
              ),
            ],

            // ── Wiki 页面（concepts + profile） ──
            if (filteredWiki.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildSectionHeader(
                '知识页面',
                Icons.article_outlined,
                filteredWiki.length,
              ),
              ...filteredWiki.map(
                (page) => WikiFileTile(
                  name: page,
                  fileType: _inferFileType(page),
                  onTap: () => _openPage(context, controller, page),
                  onLongPress: () =>
                      _showFileActions(context, controller, page, 'wiki'),
                ),
              ),
            ],

            // ── Raw 文件 ──
            if (filteredRaw.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildSectionHeader(
                'Raw 文件',
                Icons.description_outlined,
                filteredRaw.length,
              ),
              ...filteredRaw.map(
                (file) => WikiFileTile(
                  name: file,
                  fileType: WikiFileType.raw,
                  onTap: () => _openRawFile(context, controller, file),
                  onLongPress: () =>
                      _showFileActions(context, controller, file, 'raw'),
                ),
              ),
            ],

            // ── 系统文件 ──
            if (showSystem) ...[
              const SizedBox(height: 16),
              _buildSectionHeader('系统文件', Icons.settings_outlined, 2),
              if (query.isEmpty || 'index.md'.toLowerCase().contains(query))
                WikiFileTile(
                  name: 'index.md',
                  fileType: WikiFileType.indexFile,
                  subtitle: 'Wiki 全局目录',
                  onTap: () => _openPage(context, controller, 'index.md'),
                ),
              if (query.isEmpty || 'schema.md'.toLowerCase().contains(query))
                WikiFileTile(
                  name: 'schema.md',
                  fileType: WikiFileType.schema,
                  subtitle: 'LLM Wiki 编写规则',
                  onTap: () => _openPage(context, controller, 'schema.md'),
                ),
            ],
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

  Widget _buildSearchBar() {
    final c = AppSemanticColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pageHorizontal,
        vertical: AppSpacing.sm,
      ),
      child: TextField(
        onChanged: (v) => setState(() => _searchQuery = v),
        style: AppTypography.bodyMedium.copyWith(color: c.textPrimary),
        decoration: InputDecoration(
          hintText: '搜索 Wiki 页面 / 待办...',
          hintStyle: AppTypography.bodySmall
              .copyWith(color: c.textDisabled),
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
    );
  }

  Widget _buildSectionHeader(
    String title,
    IconData icon,
    int count, {
    Widget? action,
  }) {
    final c = AppSemanticColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pageHorizontal,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: c.primary),
          const SizedBox(width: 6),
          Text(
            title,
            style: AppTypography.labelMedium.copyWith(
              color: c.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: c.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: AppTypography.bodySmall.copyWith(
                color: c.primary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),
          if (action != null) action,
        ],
      ),
    );
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

    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    if (content.isEmpty || !mounted) return;

    _showMarkdownViewer(context, fileName, content);
  }

  void _openRawFile(
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

    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    if (content.isEmpty || !mounted) return;

    _showMarkdownViewer(context, fileName, content);
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
    String type,
  ) {
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
                fileName,
                style: AppTypography.titleMedium
                    .copyWith(color: c.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Divider(height: 0.5, color: c.divider),
            if (type == 'wiki')
              ListTile(
                leading:
                    Icon(Icons.edit_outlined, color: c.textSecondary),
                title: const Text('编辑'),
              ),
            ListTile(
              leading: Icon(Icons.copy, color: c.textSecondary),
              title: const Text('复制内容'),
            ),
            ListTile(
              leading:
                  Icon(Icons.share_outlined, color: c.textSecondary),
              title: const Text('导出为 Markdown'),
            ),
            if (type == 'wiki')
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

  void _confirmDelete(
    BuildContext context,
    WikiController controller,
    String fileName,
  ) {
    final c = AppSemanticColors.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text('删除页面',
            style: TextStyle(color: c.error, fontSize: 16)),
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
            onPressed: () {
              controller.deletePage(fileName);
              Navigator.pop(ctx);
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
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('页面名称不能为空')),
                );
                return;
              }
              final fileName =
                  name.endsWith('.md') ? name : '$name.md';
              controller.writePage(fileName, '# $fileName\n\n');
              Navigator.pop(ctx);
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

/// 待办卡片（v5：每条 todo 一张卡，含状态/优先级徽章）
class _TodoTile extends StatefulWidget {
  const _TodoTile({
    required this.fileName,
    required this.controller,
    this.archived = false,
  });

  final String fileName;
  final WikiController controller;
  final bool archived;

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
            if (!widget.archived) ...[
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
            ] else ...[
              ListTile(
                leading:
                    Icon(Icons.unarchive_outlined, color: c.primary),
                title: const Text('取消归档'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await widget.controller.unarchiveTodo(widget.fileName);
                },
              ),
            ],
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
    Navigator.of(context, rootNavigator: true).pop();
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
    final description = (fm.description as String).isEmpty
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
                if (widget.archived)
                  Icon(Icons.archive_outlined,
                      size: 14, color: c.textTertiary),
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
WikiFileType _inferFileType(String relativePath) {
  if (relativePath == 'profile.md') return WikiFileType.profileFile;
  if (relativePath.startsWith('todos/')) return WikiFileType.todoFile;
  if (relativePath.startsWith('sessions/')) return WikiFileType.sessionFile;
  if (relativePath.startsWith('concepts/')) return WikiFileType.conceptFile;
  return WikiFileType.wiki;
}

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
