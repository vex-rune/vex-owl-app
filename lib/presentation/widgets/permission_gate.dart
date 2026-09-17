import 'package:flutter/material.dart';

import '../../core/permission/permission_manager.dart';
import '../../design_system/design_system.dart';

/// 权限请求 Gate
///
/// 用法：
/// ```dart
/// PermissionGate(
///   permission: AppPermission.location,
///   description: '需要位置权限以提供附近问答',
///   child: YourProtectedWidget(),
/// )
/// ```
class PermissionGate extends StatefulWidget {
  const PermissionGate({
    super.key,
    required this.permission,
    required this.child,
    this.title,
    this.compact = false,
  });

  final AppPermission permission;
  final Widget child;
  final String? title;
  final bool compact;

  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate>
    with WidgetsBindingObserver {
  PermissionUiState _state = PermissionUiState.denied;
  bool _checking = true;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从系统设置返回后重新检查
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _checking = true);
    final status = await PermissionManager.check(widget.permission);
    if (!mounted) return;
    setState(() {
      _state = status.toUiState();
      _checking = false;
    });
  }

  Future<void> _request() async {
    setState(() => _requesting = true);
    final status = await PermissionManager.request(widget.permission);
    if (!mounted) return;
    setState(() {
      _state = status.toUiState();
      _requesting = false;
    });
  }

  Future<void> _openSettings() async {
    await PermissionManager.openAppSettingsPage();
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const SizedBox.shrink();
    }
    if (_state == PermissionUiState.granted) {
      return widget.child;
    }
    return _buildPrompt();
  }

  Widget _buildPrompt() {
    final c = AppSemanticColors.of(context);
    final isPermanently = _state == PermissionUiState.permanentlyDenied;
    final isCompact = widget.compact;

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: isCompact ? 12 : 16,
        vertical: isCompact ? 6 : 12,
      ),
      padding: EdgeInsets.all(isCompact ? 12 : 20),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (isPermanently ? c.error : c.warning)
              .withValues(alpha: 0.4),
        ),
        boxShadow: AppShadows.glowPrimary(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: isCompact ? 32 : 40,
                height: isCompact ? 32 : 40,
                decoration: BoxDecoration(
                  color: (isPermanently ? c.error : c.warning)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  widget.permission.icon,
                  color: isPermanently ? c.error : c.warning,
                  size: isCompact ? 16 : 20,
                ),
              ),
              SizedBox(width: isCompact ? 10 : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title ?? '${widget.permission.label}未开启',
                      style: AppTypography.titleMedium.copyWith(
                        fontSize: isCompact ? 14 : 16,
                      ),
                    ),
                    SizedBox(height: isCompact ? 2 : 6),
                    Text(
                      widget.permission.description,
                      style: AppTypography.bodySmall
                          .copyWith(color: c.textTertiary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: isCompact ? 8 : 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (isPermanently)
                TextButton(
                  onPressed: _openSettings,
                  child: const Text('去设置'),
                )
              else
                TextButton(
                  onPressed: _requesting ? null : _request,
                  child: Text(_requesting ? '请求中...' : '授权'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}