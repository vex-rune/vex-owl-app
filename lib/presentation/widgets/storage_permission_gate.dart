import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/permission/manage_storage_permission.dart';
import '../../design_system/design_system.dart';

/// 存储权限守门组件
///
/// 在以下情况拦截整个应用 UI（仅 Android 11+ 生效）：
/// - 目标存储路径是 /storage/emulated/0/.owl/wiki/
/// - 但 MANAGE_EXTERNAL_STORAGE 未授予
///
/// 用户需要去系统设置勾选"允许访问所有文件"才能正常使用 Wiki。
class StoragePermissionGate extends ConsumerStatefulWidget {
  const StoragePermissionGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<StoragePermissionGate> createState() =>
      _StoragePermissionGateState();
}

class _StoragePermissionGateState extends ConsumerState<StoragePermissionGate>
    with WidgetsBindingObserver {
  bool? _granted;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 用户从系统设置返回时重新检测
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (!Platform.isAndroid) {
      setState(() {
        _granted = true;
        _checking = false;
      });
      return;
    }
    final ok = await ManageStoragePermission.isGranted();
    setState(() {
      _granted = ok;
      _checking = false;
    });
  }

  Future<void> _openSettings() async {
    await ManageStoragePermission.openSystemSettings();
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const _LoadingScreen();
    }
    if (_granted == true) {
      return widget.child;
    }
    return _PermissionRequestScreen(onSettings: _openSettings);
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      body: Center(
        child: CircularProgressIndicator(color: c.warning),
      ),
    );
  }
}

class _PermissionRequestScreen extends StatelessWidget {
  const _PermissionRequestScreen({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              // 图标
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: c.warning.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.folder_shared_outlined,
                  size: 48,
                  color: c.warning,
                ),
              ),
              const SizedBox(height: 32),
              // 标题
              Text(
                '需要文件访问权限',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              // 描述
              Text(
                '智鸮需要"所有文件访问权限"，才能将知识库存放在手机存储根目录 '
                '/storage/emulated/0/.owl/wiki/，与系统 Documents 等平级，'
                '便于你在文件管理器中查看和备份。',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: c.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              // 步骤说明
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    _StepItem(
                      index: '1',
                      text: '点击下方"前往设置"按钮',
                    ),
                    _StepItem(
                      index: '2',
                      text: '在设置中找到"允许访问所有文件"开关',
                    ),
                    _StepItem(
                      index: '3',
                      text: '打开开关后返回应用',
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // 操作按钮
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: c.warning,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: onSettings,
                child: const Text(
                  '前往设置',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  // 暂不开启：仍允许进入，但 Wiki 会回退到应用沙盒
                  // 由调用方处理
                },
                child: Text(
                  '暂不开启（数据将存于应用沙盒）',
                  style: TextStyle(color: c.textTertiary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepItem extends StatelessWidget {
  const _StepItem({required this.index, required this.text});

  final String index;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.warning,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              index,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: c.textSecondary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
