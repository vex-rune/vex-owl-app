import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repository/i_wiki_repository.dart';
import '../../data/repository/wiki_repository.dart';

// re-export from permission_onboarding for global access
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

/// 全局 Riverpod Providers
///
/// 集中声明仓库与常用状态 Provider。
/// 控制器通过 `ref.read(...)` 在构造时获取依赖，避免直接使用 GetX。
///
/// Wiki 仓库职责（v5）：
/// - 根目录：`<appDocs>/.owl/wiki/`
/// - `.meta/` — 私有目录（wiki.lock + export-meta.json + .audit.log）
/// - `.backup/` — 自动备份目录
/// - `schema.md` — LLM 编写规则（不可变）
/// - `index.md` — 人类可读展示目录
/// - `profile.md` — 用户画像
/// - `todos/todo-{uuid}.md` — 多文件待办（v5 新增）
/// - `sessions/{sessionId}.md` — 短期记忆 + 摘要（v5 改名）
/// - `concepts/{entityId}.md` — 长期知识
/// - `raw/` — 原始素材（只读）
/// - `context-settings.md` — 应用设置
/// - `api-configs.md` — API 配置（含加密 Key）
final wikiRepositoryProvider = Provider<IWikiRepository>((ref) {
  return WikiRepository();
});