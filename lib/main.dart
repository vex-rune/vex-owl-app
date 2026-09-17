import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'application/providers/app_providers.dart';
import 'core/util/talker_service.dart';

/// 应用入口
///
/// 初始化顺序：
/// 1. Flutter 引擎绑定初始化
/// 2. 全局日志服务初始化
/// 3. 系统 UI 配置（状态栏样式、屏幕方向）
/// 4. 触发 Wiki 仓库初始化（确保 wiki/ 目录结构完整）
/// 5. 启动应用并包裹 ProviderScope
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化全局日志服务
  TalkerService.instance.init();

  // 设置状态栏样式为浅色图标（适配深色背景）
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  // 强制竖屏显示
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // 启动应用前先确保 ProviderScope 已包裹，
  // 首次访问 wikiRepositoryProvider 时会进行惰性初始化
  await Future.microtask(() {});

  runApp(
    const ProviderScope(
      child: OwlApp(),
    ),
  );
}

/// 触发 Wiki 仓库的预初始化（在 ProviderScope 内使用）
///
/// 在应用启动前调用以确保 wiki/ 目录结构已创建。
Future<void> warmUpProviders(WidgetRef ref) async {
  await ref.read(wikiRepositoryProvider).initialize();
}
