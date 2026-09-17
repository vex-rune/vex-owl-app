import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/controller/chat_controller.dart';
import '../../application/controller/session_controller.dart';
import '../../application/providers/app_providers.dart';
import '../../design_system/design_system.dart';
import '../pages/chat_body.dart';
import '../pages/settings_body.dart';
import '../pages/wiki_body.dart';

/// GoRouter 路由配置
///
/// 去掉底部导航，对话为主界面，Wiki 和设置在会话抽屉里导航。
final goRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => const _ScaffoldWithDrawer(),
    ),
    GoRoute(
      path: '/wiki',
      builder: (_, __) => const _FullScreenScaffold(
        title: 'Wiki 知识库',
        child: WikiBody(),
      ),
    ),
    GoRoute(
      path: '/settings',
      builder: (_, __) => const _FullScreenScaffold(
        title: '设置',
        child: SettingsBody(),
      ),
    ),
  ],
);

/// 主骨架（对话页 + 会话抽屉）
///
/// 抽屉始终可用，底部无导航栏。
class _ScaffoldWithDrawer extends StatefulWidget {
  const _ScaffoldWithDrawer();

  @override
  State<_ScaffoldWithDrawer> createState() => _ScaffoldWithDrawerState();
}

class _ScaffoldWithDrawerState extends State<_ScaffoldWithDrawer> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: c.background,
      drawer: _SessionDrawer(scaffoldKey: _scaffoldKey),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                gradient: c.primaryGradient,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.psychology_outlined,
                color: c.background,
                size: 14,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '智鸮 Owl',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                color: c.textPrimary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmark_add_outlined, size: 22),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('记忆入库功能即将上线')),
              );
            },
            tooltip: '存入记忆',
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, size: 22),
            onPressed: () {
              final container =
                  ProviderScope.containerOf(context, listen: false);
              container.read(chatControllerProvider).clearContext();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('上下文已清空')),
              );
            },
            tooltip: '清空上下文',
          ),
        ],
      ),
      body: const ChatBody(),
    );
  }
}

/// 全屏路由页面骨架（Wiki / 设置）
class _FullScreenScaffold extends StatelessWidget {
  const _FullScreenScaffold({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.go('/'),
        ),
        title: Text(title),
        actions: title == 'Wiki 知识库'
            ? [
                IconButton(
                  icon: const Icon(Icons.search, size: 22),
                  onPressed: () {},
                  tooltip: '搜索',
                ),
                IconButton(
                  icon: const Icon(Icons.file_download_outlined, size: 22),
                  onPressed: () {},
                  tooltip: '导入',
                ),
              ]
            : title == '设置'
                ? [
                    IconButton(
                      icon: const Icon(Icons.file_upload_outlined, size: 22),
                      onPressed: () {},
                      tooltip: '导出 Wiki',
                    ),
                  ]
                : null,
      ),
      body: child,
    );
  }
}

/// 左侧抽屉 — 会话列表 + 底部导航入口 + 主题切换
///
/// 顶部：品牌区 + 新建按钮 + 搜索框
/// 中间：会话列表
/// 底部：主题切换 + 导航入口（Wiki / 设置）
class _SessionDrawer extends ConsumerWidget {
  const _SessionDrawer({required this.scaffoldKey});

  final GlobalKey<ScaffoldState> scaffoldKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionCtrl = ref.watch(sessionControllerProvider);
    final currentLocation = GoRouterState.of(context).uri.path;
    final c = AppSemanticColors.of(context);
    final themeMode = ref.watch(themeModeProvider);

    return Drawer(
      backgroundColor: c.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 品牌区 ──
            _buildBrandArea(context, sessionCtrl),

            // ── 搜索框 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.base,
                AppSpacing.sm,
                AppSpacing.base,
                AppSpacing.sm,
              ),
              child: TextField(
                style: AppTypography.bodyMedium.copyWith(color: c.textPrimary),
                decoration: InputDecoration(
                  hintText: '搜索会话...',
                  prefixIcon:
                      Icon(Icons.search, size: 20, color: c.textTertiary),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: c.surfaceVariant,
                  hintStyle: AppTypography.bodyMedium
                      .copyWith(color: c.textTertiary),
                ),
              ),
            ),
            Divider(color: c.divider, height: 1),

            // ── 会话列表 ──
            Expanded(
              child: sessionCtrl.sessions.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.chat_bubble_outline,
                                size: 48,
                                color: c.textTertiary.withValues(alpha: 0.5)),
                            const SizedBox(height: 12),
                            Text('暂无会话',
                                style: AppTypography.bodyMedium
                                    .copyWith(color: c.textTertiary)),
                            const SizedBox(height: 4),
                            Text('点击右上角 + 开始新对话',
                                style: AppTypography.bodySmall.copyWith(
                                    color: c.textTertiary
                                        .withValues(alpha: 0.6))),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      itemCount: sessionCtrl.sessions.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 2),
                      itemBuilder: (context, index) {
                        final session = sessionCtrl.sessions[index];
                        final isSelected =
                            sessionCtrl.currentSession?.id == session.id;
                        return ListTile(
                          selected: isSelected,
                          selectedTileColor:
                              c.primary.withValues(alpha: 0.08),
                          leading: Icon(
                            Icons.chat_bubble_outline,
                            size: 20,
                            color: isSelected ? c.primary : c.textTertiary,
                          ),
                          title: Text(
                            session.name,
                            style: AppTypography.bodyMedium.copyWith(
                              color: isSelected
                                  ? c.primary
                                  : c.textSecondary,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          dense: true,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            sessionCtrl.switchSession(session.id);
                          },
                          onLongPress: () => _showSessionActions(
                            context,
                            ref,
                            session.id,
                            session.name,
                          ),
                        );
                      },
                    ),
            ),

            // ── 主题切换段 ──
            Divider(color: c.divider, height: 1),
            _buildThemeSwitcher(context, themeMode),

            // ── 底部分割线 ──
            Divider(color: c.divider, height: 1),

            // ── 底部导航入口 ──
            _BottomNavEntry(
              icon: Icons.library_books_outlined,
              selectedIcon: Icons.library_books,
              label: 'Wiki 知识库',
              isActive: currentLocation == '/wiki',
              onTap: () {
                Navigator.pop(context);
                GoRouter.of(context).push('/wiki');
              },
            ),
            _BottomNavEntry(
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings,
              label: '设置',
              isActive: currentLocation == '/settings',
              onTap: () {
                Navigator.pop(context);
                GoRouter.of(context).push('/settings');
              },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  /// 抽屉顶部品牌区
  Widget _buildBrandArea(BuildContext context, SessionController sessionCtrl) {
    final c = AppSemanticColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.base,
        AppSpacing.base,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            c.primary.withValues(alpha: 0.08),
            Colors.transparent,
          ],
        ),
        border: Border(
          bottom: BorderSide(
            color: c.divider.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: c.primaryGradient,
                  shape: BoxShape.circle,
                  boxShadow: AppShadows.glowPrimary(context),
                ),
                child: Icon(
                  Icons.psychology_outlined,
                  color: c.onPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '智鸮 Owl',
                      style: AppTypography.titleMedium.copyWith(
                        color: c.textPrimary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      '对话列表',
                      style: AppTypography.bodySmall
                          .copyWith(color: c.textTertiary),
                    ),
                  ],
                ),
              ),
              Material(
                color: c.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                child: InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    sessionCtrl.createSession('新对话');
                  },
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusSm),
                  child: Tooltip(
                    message: '新建会话',
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      child:
                          Icon(Icons.add, size: 18, color: c.primary),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 主题切换器（白天 / 夜晚 / 跟随系统）
  Widget _buildThemeSwitcher(BuildContext context, ThemeMode currentMode) {
    final c = AppSemanticColors.of(context);
    final controller =
        ProviderScope.containerOf(context, listen: false)
            .read(themeModeProvider.notifier);

    Widget segBtn(ThemeMode mode, IconData icon, String label) {
      final selected = mode == currentMode;
      return Expanded(
        child: Material(
          color: selected
              ? c.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              controller.set(mode);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: selected ? c.primary : c.textTertiary,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: AppTypography.bodySmall.copyWith(
                      fontSize: 11,
                      color: selected ? c.primary : c.textTertiary,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.sm,
        AppSpacing.base,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              '主题外观',
              style: AppTypography.bodySmall
                  .copyWith(color: c.textTertiary, fontSize: 11),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: c.surfaceVariant,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.border, width: 0.5),
            ),
            child: Row(
              children: [
                segBtn(ThemeMode.light, Icons.light_mode_outlined, '白天'),
                segBtn(ThemeMode.dark, Icons.dark_mode_outlined, '夜晚'),
                segBtn(ThemeMode.system, Icons.brightness_auto_outlined, '自动'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSessionActions(
    BuildContext context,
    WidgetRef ref,
    String sessionId,
    String sessionName,
  ) {
    final sessionCtrl = ref.read(sessionControllerProvider);
    final c = AppSemanticColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.edit_outlined, color: c.textSecondary),
              title: const Text('重命名'),
              onTap: () {
                Navigator.pop(ctx);
                sessionCtrl.renameSession(sessionId, sessionName);
              },
            ),
            ListTile(
              leading:
                  Icon(Icons.archive_outlined, color: c.textSecondary),
              title: const Text('归档'),
              onTap: () {
                Navigator.pop(ctx);
                sessionCtrl.archiveSession(sessionId);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: c.error),
              title: Text('删除', style: TextStyle(color: c.error)),
              onTap: () {
                Navigator.pop(ctx);
                sessionCtrl.deleteSession(sessionId);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 底部导航入口行（Wiki / 设置）
class _BottomNavEntry extends StatelessWidget {
  const _BottomNavEntry({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    final color = isActive ? c.primary : c.textSecondary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                isActive ? selectedIcon : icon,
                size: 22,
                color: color,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: AppTypography.bodyMedium.copyWith(
                  color: color,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              const Spacer(),
              if (isActive)
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.primary,
                    boxShadow: AppShadows.glowPrimary(context),
                  ),
                )
              else
                Icon(Icons.chevron_right,
                    size: 18,
                    color: color.withValues(alpha: 0.5)),
            ],
          ),
        ),
      ),
    );
  }
}