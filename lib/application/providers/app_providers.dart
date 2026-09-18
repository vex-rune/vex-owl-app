import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repository/i_wiki_repository.dart';
import '../../data/repository/wiki_repository.dart';

// re-export controllers for global access
export '../controller/settings_controller.dart' show settingsControllerProvider;

// re-export from permission_onboarding for global access
// v6.4: 修复 H1，移除 presentation 层反向导出（改为直接从 presentation 导入）
export '../../presentation/widgets/permission_onboarding.dart'
    show permissionOnboardedProvider;

// ══════════════════════════════════════════════════════════════════
//  主题模式（light / dark / system）
// ══════════════════════════════════════════════════════════════════

/// 全局主题模式。
///
/// - [ThemeMode.system]: 跟随系统
/// - [ThemeMode.light]:  浅色（白天）
/// - [ThemeMode.dark]:   深色（夜晚）
class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController() : super(ThemeMode.system);

  void set(ThemeMode mode) {
    state = mode;
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>(
  (ref) => ThemeModeController(),
);

/// 全局 Riverpod Providers（v6.4）
///
/// Wiki 仓库（v6.4）：
/// - 根目录使用 `OwlRoot.instance.wikiDir`
/// - 文件锁在 `.owl/.meta/wiki.lock`（由 WikiLockService 管理）
/// - 会话存储在 `.owl/sessions/{id}/`（JSONL 格式，由 FileSessionRepository 管理）
/// - 配置存储在 `.owl/config/`（JSONL 格式，由 ConfigStorage 管理）
/// - Wiki 页面仍在 `.owl/wiki/`（Markdown 格式）
final wikiRepositoryProvider = Provider<IWikiRepository>((ref) {
  return WikiRepository();
});
