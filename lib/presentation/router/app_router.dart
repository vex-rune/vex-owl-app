import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/controller/chat_controller.dart';
import '../../application/controller/session_controller.dart';
import '../../core/model/session.dart';
import '../../design_system/design_system.dart';
import '../pages/home_body.dart';
import '../pages/settings_body.dart';
import '../pages/wiki_body.dart';

/// GoRouter 路由配置
///
/// 主页（/）= HomeChatBody（同一个页面的两种形态：无消息→Home / 有消息→Chat）
/// 其他子页：/wiki /settings
final goRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const _HomeShell()),
    GoRoute(
        path: '/wiki',
        builder: (_, __) =>
            const _FullScreenScaffold(title: 'Wiki 知识库', child: WikiBody())),
    GoRoute(
        path: '/settings',
        builder: (_, __) =>
            const _FullScreenScaffold(title: '设置', child: SettingsBody())),
  ],
);

/// 主页 Shell：包含侧边菜单 + HomeChatBody
class _HomeShell extends StatelessWidget {
  const _HomeShell();
  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      drawer: const HomeDrawer(),
      body: const HomeChatBody(),
    );
  }
}

/// 侧边菜单
///
/// - 顶部「导航」区：会话历史列表（点击切换会话 / 关闭抽屉）
/// - 底部「设置」区：设置 / 知识库 / 主题外观
/// - 极底部：版本号
class HomeDrawer extends ConsumerWidget {
  const HomeDrawer({super.key});

  /// 抽屉中最多直接展示的会话条数；超出后显示「更多」
  static const int _visibleSessionLimit = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AppSemanticColors.of(context);
    final sessions = ref.watch(sessionControllerProvider).sessions;
    final pinned = sessions.where((s) => s.pinned).toList();
    final others = sessions.where((s) => !s.pinned).toList();
    return Drawer(
      backgroundColor: c.background,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 4),
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: c.textDisabled.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // ── 顶置 ──
            if (pinned.isNotEmpty) ...[
              const _SectionLabel('顶置'),
              const SizedBox(height: 4),
              for (final s in pinned) _SessionRow(session: s),
              const SizedBox(height: 8),
            ],
            // ── 全部会话 ──
            const _SectionLabel('对话'),
            const SizedBox(height: 4),
            Expanded(
              child: _buildSessionList(context, ref, c, others),
            ),
            // ── 设置 ──
            const Divider(
                height: 24, thickness: 0.5, indent: 16, endIndent: 16),
            const _SectionLabel('设置'),
            const SizedBox(height: 4),
            _NavItem(
              icon: Icons.settings_outlined,
              iconColor: c.textPrimary,
              iconBg: c.surfaceVariant,
              label: '设置',
              showChevron: true,
              onTap: () {
                Navigator.of(context).pop();
                context.go('/settings');
              },
            ),
            _NavItem(
              icon: Icons.menu_book_outlined,
              iconColor: c.textPrimary,
              iconBg: c.surfaceVariant,
              label: '知识库',
              showChevron: true,
              onTap: () {
                Navigator.of(context).pop();
                context.go('/wiki');
              },
            ),
            _NavItem(
              icon: Icons.palette_outlined,
              iconColor: c.textPrimary,
              iconBg: c.surfaceVariant,
              label: '主题外观',
              showChevron: true,
              onTap: () {
                Navigator.of(context).pop();
                context.go('/settings');
              },
            ),
            // ── 版本号 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Center(
                child: Text(
                  'AI Assistant v1.0.0',
                  style: TextStyle(fontSize: 11, color: c.textTertiary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionList(
    BuildContext context,
    WidgetRef ref,
    AppSemanticColors c,
    List<Session> sessions,
  ) {
    if (sessions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Text(
          '还没有会话，去首页开始一段新对话吧',
          style: TextStyle(fontSize: 12, color: c.textTertiary),
        ),
      );
    }

    final visible = sessions.take(_visibleSessionLimit).toList();
    final hiddenCount = sessions.length - visible.length;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final s in visible) _SessionRow(session: s),
        if (hiddenCount > 0)
          InkWell(
            onTap: () {
              Navigator.of(context).pop();
              // 「更多」暂跳转到首页，由首页的最近对话列表承载全量
              context.go('/');
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(
                children: [
                  Icon(Icons.chat,
                      size: 18, color: c.textTertiary),
                  const SizedBox(width: 8),
                  Text(
                    '更多',
                    style: TextStyle(
                      fontSize: 13,
                      color: c.textTertiary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// 会话历史项
class _SessionRow extends ConsumerWidget {
  const _SessionRow({required this.session});
  final Session session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AppSemanticColors.of(context);
    final current =
        ref.watch(sessionControllerProvider).currentSession?.id == session.id;
    final color = _iconColorForName(session.name);
    return InkWell(
      onTap: () {
        ref.read(sessionControllerProvider).switchSession(session.id);
        // 不调用 clearContext() — switchSession 已触发 _loadMessages 加载历史消息
        Navigator.of(context).pop();
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(10),
          border: current
              ? Border.all(color: c.primary, width: 1)
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _iconForName(session.name),
                size: 18,
                color: color,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                session.name,
                style: TextStyle(
                  fontSize: 14,
                  color: c.textPrimary,
                  fontWeight:
                      current ? FontWeight.w600 : FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // ── 顶置标记 ──
            if (session.pinned)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.push_pin,
                    size: 14, color: c.primary),
              ),
            // ── ⋯ 菜单（顶置/删除） ──
            InkWell(
              onTap: () => _showRowMenu(context, ref),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.more_horiz,
                    size: 18, color: c.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRowMenu(BuildContext context, WidgetRef ref) {
    final c = AppSemanticColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
      builder: (sheetCtx) => SafeArea(
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
                session.name,
                style: AppTypography.titleMedium
                    .copyWith(color: c.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Divider(height: 0.5, color: c.divider),
            ListTile(
              leading: Icon(
                session.pinned
                    ? Icons.push_pin_outlined
                    : Icons.push_pin,
                color: c.textSecondary,
              ),
              title: Text(session.pinned ? '取消顶置' : '顶置'),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                ref
                    .read(sessionControllerProvider)
                    .togglePin(session.id);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: c.error),
              title: Text('删除', style: TextStyle(color: c.error)),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                ref
                    .read(sessionControllerProvider)
                    .deleteSession(session.id);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  IconData _iconForName(String n) {
    final l = n.toLowerCase();
    if (l.contains('python') || l.contains('代码') || l.contains('code')) {
      return Icons.code;
    }
    if (l.contains('旅行') || l.contains('travel') || l.contains('map')) {
      return Icons.map_outlined;
    }
    if (l.contains('翻译') || l.contains('translate')) {
      return Icons.translate;
    }
    if (l.contains('设计') || l.contains('design')) {
      return Icons.palette_outlined;
    }
    if (l.contains('学习') || l.contains('learn')) {
      return Icons.school_outlined;
    }
    return Icons.menu_book_outlined;
  }

  Color _iconColorForName(String n) {
    final l = n.toLowerCase();
    if (l.contains('python') || l.contains('代码') || l.contains('code')) {
      return const Color(0xFF4D6EF5);
    }
    if (l.contains('旅行') || l.contains('travel')) {
      return const Color(0xFFFF6B9D);
    }
    if (l.contains('翻译') || l.contains('translate')) {
      return const Color(0xFF5DD5C4);
    }
    return const Color(0xFF4D6EF5);
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: c.textTertiary,
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.onTap,
    this.badge,
    this.showChevron = false,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final String? badge;
  final bool showChevron;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: c.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: c.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badge!,
                  style: TextStyle(
                    fontSize: 11,
                    color: c.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            if (showChevron)
              Icon(Icons.chevron_right,
                  size: 18, color: c.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// 全屏路由页面骨架（Wiki / 设置）
class _FullScreenScaffold extends StatelessWidget {
  const _FullScreenScaffold({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 24),
          onPressed: () => context.go('/'),
        ),
        title: Text(
          title,
          style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: c.textPrimary),
        ),
      ),
      body: child,
    );
  }
}