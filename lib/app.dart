import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'presentation/pages/chat_page.dart';
import 'presentation/pages/home_page.dart';
import 'presentation/pages/settings_page.dart';
import 'presentation/pages/splash_page.dart';
import 'presentation/theme/app_theme.dart';

/// vex owl 应用根组件。
///
/// 路由表遵循 docs/架构设计.md § 6.1 启动流程的"决策路由"设计:
/// `/splash` → `/home` 或 `/chat/:id` 或 `/settings`
class OwlApp extends StatelessWidget {
  const OwlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'vex owl',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: _router,
    );
  }

  static final _router = GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, _) => const SplashPage(),
      ),
      GoRoute(
        path: '/home',
        builder: (_, _) => const HomePage(),
        routes: [
          GoRoute(
            path: 'chat/:id',
            builder: (_, state) =>
                ChatPage(conversationId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: 'settings',
            builder: (_, _) => const SettingsPage(),
          ),
        ],
      ),
      // 顶层 /chat/:id:Splash 在「无历史」时直接进入对话,
      // ChatPage AppBar 的返回按钮回到 /home。
      GoRoute(
        path: '/chat/:id',
        builder: (_, state) =>
            ChatPage(conversationId: state.pathParameters['id']!),
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('页面不存在: ${state.uri}')),
    ),
  );
}
