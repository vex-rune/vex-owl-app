import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../../core/model/conversation.dart';
import '../theme/app_theme.dart';
import '../widgets/conversation_card.dart';

/// 主页:对话历史列表 + 新建 FAB + 设置入口。
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  Future<void> _createAndOpen() async {
    final service = await ref.read(conversationServiceProvider.future);
    final session = await service.create();
    if (!mounted) return;
    context.push('/home/chat/${session.id}');
  }

  Future<void> _togglePin(Session session) async {
    final service = await ref.read(conversationServiceProvider.future);
    if (session.pinned) {
      await service.unpin(session.id);
    } else {
      await service.pin(session.id);
    }
    // 无需手动 reload —— sessionsStreamProvider 会自动推送新快照。
  }

  Future<void> _delete(String id) async {
    final service = await ref.read(conversationServiceProvider.future);
    await service.delete(id);
    // 无需手动 reload —— sessionsStreamProvider 会自动推送新快照。
  }

  @override
  Widget build(BuildContext context) {
    // watch 实时流:DB 变更(新建 / 改名 / 删除 / pin)自动反映到 UI。
    final sessionsAsync = ref.watch(sessionsStreamProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('vex owl'),
        actions: [
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/home/settings'),
          ),
        ],
      ),
      body: sessionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _EmptyState(onCreate: _createAndOpen, errorText: '加载失败:$e'),
        data: (sessions) => sessions.isEmpty
            ? _EmptyState(onCreate: _createAndOpen)
            : RefreshIndicator(
                // 下拉刷新:让用户手动 invalidate 重读,绕过 stream 缓存。
                onRefresh: () async => ref.invalidate(sessionsStreamProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.space4,
                    vertical: AppTheme.space3,
                  ),
                  itemCount: sessions.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppTheme.space3),
                  itemBuilder: (context, i) {
                    final c = sessions[i];
                    return ConversationCard(
                      conversation: c,
                      onTap: () => context.push('/home/chat/${c.id}'),
                      onLongPress: () => _showActionMenu(context, c),
                    );
                  },
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createAndOpen,
        icon: const Icon(Icons.add),
        label: const Text('新建对话'),
      ),
    );
  }

  void _showActionMenu(BuildContext context, Session session) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  session.pinned ? Icons.push_pin_outlined : Icons.push_pin,
                ),
                title: Text(session.pinned ? '取消置顶' : '置顶'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _togglePin(session);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('重命名'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showRenameDialog(context, session.id, session.title);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(ctx).colorScheme.error,
                ),
                title: Text(
                  '删除',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _delete(session.id);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showRenameDialog(BuildContext context, String id, String currentTitle) {
    final controller = TextEditingController(text: currentTitle);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入新标题'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final nav = Navigator.of(ctx);
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty) {
                final service = await ref.read(conversationServiceProvider.future);
                await service.rename(id, newTitle);
                // 无需手动 reload —— sessionsStreamProvider 自动推送。
              }
              if (!mounted) return;
              nav.pop();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  final String? errorText;
  const _EmptyState({required this.onCreate, this.errorText});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppTheme.space4),
            Text('问点什么吧~', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppTheme.space2),
            Text(
              errorText ?? '点击下方按钮开启你的第一次对话',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppTheme.space5),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('开始对话'),
            ),
          ],
        ),
      ),
    );
  }
}
