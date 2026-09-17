import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/permission/permission_manager.dart';
import '../../design_system/design_system.dart';

/// 是否已完成首次权限引导
final permissionOnboardedProvider = StateProvider<bool>((ref) => false);

/// 首次启动权限引导页（全屏）
class PermissionOnboarding extends ConsumerStatefulWidget {
  const PermissionOnboarding({super.key});

  @override
  ConsumerState<PermissionOnboarding> createState() =>
      _PermissionOnboardingState();
}

class _PermissionOnboardingState extends ConsumerState<PermissionOnboarding> {
  int _currentPage = 0;
  bool _isRequesting = false;

  // 引导页配置
  static const List<
      ({
        IconData icon,
        String title,
        String description,
        AppPermission permission,
      })> _steps = [
    (
      icon: Icons.folder_outlined,
      title: '存储权限',
      description: '用于读写本地知识库文件',
      permission: AppPermission.storage,
    ),
    (
      icon: Icons.mic_none_rounded,
      title: '麦克风权限',
      description: '用于语音对话输入',
      permission: AppPermission.microphone,
    ),
    (
      icon: Icons.location_on_outlined,
      title: '位置权限',
      description: '用于基于位置的回答',
      permission: AppPermission.location,
    ),
    (
      icon: Icons.notifications_outlined,
      title: '通知权限',
      description: '用于播放控制和消息提醒',
      permission: AppPermission.notification,
    ),
  ];

  Future<void> _requestCurrent() async {
    if (_isRequesting) return;
    setState(() => _isRequesting = true);
    final perm = _steps[_currentPage].permission;
    await PermissionManager.request(perm);
    if (!mounted) return;
    setState(() => _isRequesting = false);
    _advance();
  }

  Future<void> _skip() async {
    _advance();
  }

  /// 推进到下一步；已是最后一步则完成整个引导
  void _advance() {
    if (_currentPage < _steps.length - 1) {
      setState(() => _currentPage++);
    } else {
      _completeOnboarding();
    }
  }

  Future<void> _completeOnboarding() async {
    ref.read(permissionOnboardedProvider.notifier).state = true;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    final step = _steps[_currentPage];
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [c.background, c.surface],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // 顶部进度条
                Row(
                  children: List.generate(_steps.length, (i) {
                    final isActive = i <= _currentPage;
                    return Expanded(
                      child: Container(
                        margin: EdgeInsets.only(
                            right: i == _steps.length - 1 ? 0 : 6),
                        height: 3,
                        decoration: BoxDecoration(
                          color: isActive
                              ? c.primary
                              : c.surfaceVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }),
                ),
                const Spacer(flex: 2),
                // 大图标
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: c.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    boxShadow: AppShadows.glowPrimary(context),
                  ),
                  child: Icon(step.icon, color: c.primary, size: 48),
                ),
                const SizedBox(height: 32),
                Text(step.title, style: AppTypography.displaySmall),
                const SizedBox(height: 12),
                Text(
                  step.description,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium
                      .copyWith(color: c.textSecondary),
                ),
                const Spacer(flex: 3),
                // 按钮区
                if (_currentPage == _steps.length - 1)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isRequesting ? null : _completeOnboarding,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c.primary,
                        foregroundColor: c.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('开始使用'),
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isRequesting ? null : _skip,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(color: c.border),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('稍后'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: _isRequesting ? null : _requestCurrent,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: c.primary,
                            foregroundColor: c.onPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _isRequesting
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('授权并继续'),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}