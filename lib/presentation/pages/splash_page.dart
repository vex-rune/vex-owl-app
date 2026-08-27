import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/owl_logo.dart';

/// 启动页:初始化基础设施后路由到首页或新建对话。
class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> {
  Timer? _navTimer;

  @override
  void initState() {
    super.initState();
    _navTimer = Timer(const Duration(milliseconds: 800), _decideRoute);
  }

  Future<void> _decideRoute() async {
    if (!mounted) return;
    try {
      // 初始化基础设施(Drift 数据库 + 仓储)
      await ref.read(appDatabaseProvider.future);
      await ref.read(configRepositoryProvider.future);
      await ref.read(memoryRepositoryProvider.future);

      // 检查是否有历史会话
      final sessionService = await ref.read(conversationServiceProvider.future);
      final sessions = await sessionService.snapshot();
      if (sessions.isEmpty) {
        // 无历史 → 新建会话并直接进入 ChatPage
        final session = await sessionService.create();
        if (!mounted) return;
        context.go('/chat/${session.id}');
      } else {
        if (!mounted) return;
        context.go('/home');
      }
    } catch (_) {
      // 初始化失败也进入 HomePage(降级)
      if (!mounted) return;
      context.go('/home');
    }
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const OwlLogo.large(),
              const SizedBox(height: AppTheme.space5),
              Text('vex owl', style: theme.textTheme.headlineSmall),
              const SizedBox(height: AppTheme.space1),
              Text(
                '本地实时 AI 对话',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppTheme.space5),
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
