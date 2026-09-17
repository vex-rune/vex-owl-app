import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'application/providers/app_providers.dart';
import 'core/core.dart';
import 'data/storage/owl_root.dart';

/// 应用入口
///
/// 初始化顺序：
/// 1. Flutter 引擎绑定初始化
/// 2. 全局日志服务初始化
/// 3. OwlRoot 初始化（创建 .owl/ 目录结构 + 执行迁移）
/// 4. 系统 UI 配置（状态栏样式、屏幕方向）
/// 5. 启动应用并包裹 ProviderScope
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化全局日志服务
  log.info('应用启动');

  // v6.4：初始化 OwlRoot（创建目录结构 + 迁移旧数据）
  await OwlRoot.instance.initialize();

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

  runApp(
    const ProviderScope(
      child: OwlApp(),
    ),
  );
}
