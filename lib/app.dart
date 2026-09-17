import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/providers/app_providers.dart';
import 'design_system/design_system.dart';
import 'presentation/router/app_router.dart';
import 'presentation/widgets/storage_permission_gate.dart';

/// vex owl 应用根组件。
///
/// 使用 [MaterialApp.router] 集成 Riverpod 状态管理和 GoRouter 路由。
/// 在 [build] 内通过 [ProviderScope.containerOf] 触发 Wiki 仓库的初始化，
/// 保证应用启动后第一次访问仓库时 wiki/ 目录结构已就绪。
///
/// 外层包 [StoragePermissionGate]：在 Android 11+ 未授予 MANAGE_EXTERNAL_STORAGE
/// 时拦截 UI，引导用户去系统设置授权（用于访问 /storage/emulated/0/.owl/）。
class OwlApp extends ConsumerWidget {
  const OwlApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 预热 Wiki 仓库（触发 wiki/ 目录结构初始化）
    ref.watch(wikiRepositoryProvider);

    // 订阅主题模式（light / dark / system）
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: '智鸮 Owl',
      debugShowCheckedModeBanner: false,
      // 日 / 夜双主题
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: goRouter,
      // 将 StoragePermissionGate 置于 MaterialApp 内部（builder 包裹 Navigator），
      // 使权限拦截页的 Scaffold 能获得 Directionality / Theme 等上下文。
      builder: (context, child) {
        return StoragePermissionGate(child: child ?? const SizedBox.shrink());
      },
    );
  }
}