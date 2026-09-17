import 'dart:io';

import 'package:flutter/material.dart';

/// 应用权限项定义
enum AppPermission {
  storage('存储权限', Icons.folder_outlined, '用于读写本地文件'),
  photos('相册权限', Icons.photo_library_outlined, '用于读取图片附件'),
  location('位置权限', Icons.location_on_outlined, '用于基于位置的智能回答'),
  microphone('麦克风权限', Icons.mic_none_rounded, '用于语音对话'),
  notification('通知权限', Icons.notifications_outlined, '用于播放控制与消息提醒');

  const AppPermission(this.label, this.icon, this.description);
  final String label;
  final IconData icon;
  final String description;
}

/// 权限检查与请求管理器
///
/// 桌面平台（Windows/macOS/Linux）直接返回已授权，
/// 移动平台（Android/iOS）可通过 [ensurePermission] 按需请求。
///
/// 注意：当前版本移除了 permission_handler 依赖以避免 Windows 构建问题。
/// 移动端完整权限支持将在后续版本中通过条件导入重新引入。
class PermissionManager {
  PermissionManager._();

  /// 是否为移动平台
  static bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  /// 检查单个权限状态
  ///
  /// 桌面平台始终返回 [PermissionStatus.granted]。
  static Future<PermissionStatus> check(AppPermission perm) async {
    if (!_isMobile) return PermissionStatus.granted;
    // 移动平台：TODO 后续引入 permission_handler 条件导入
    return PermissionStatus.granted;
  }

  /// 请求单个权限
  ///
  /// 桌面平台始终返回 [PermissionStatus.granted]。
  static Future<PermissionStatus> request(AppPermission perm) async {
    if (!_isMobile) return PermissionStatus.granted;
    // 移动平台：TODO 后续引入 permission_handler 条件导入
    return PermissionStatus.granted;
  }

  /// 按需请求权限：先检查，未授权则请求，返回是否已授权
  static Future<bool> ensurePermission(AppPermission perm) async {
    if (await isGranted(perm)) return true;
    final status = await request(perm);
    return status.isGranted;
  }

  /// 是否已授权
  static Future<bool> isGranted(AppPermission perm) async {
    final status = await check(perm);
    return status.isGranted;
  }

  /// 是否被永久拒绝
  static Future<bool> isPermanentlyDenied(AppPermission perm) async {
    final status = await check(perm);
    return status.isPermanentlyDenied;
  }

  /// 打开系统应用设置页（桌面平台为空操作）
  static Future<bool> openAppSettingsPage() async {
    // TODO: 移动端引入 permission_handler 后实现 openAppSettings()
    return false;
  }
}

/// 权限状态枚举（自包含，不依赖 permission_handler）
enum PermissionStatus {
  granted,
  denied,
  permanentlyDenied,
  restricted,
  limited;

  bool get isGranted => this == PermissionStatus.granted;
  bool get isPermanentlyDenied =>
      this == PermissionStatus.permanentlyDenied;
  bool get isRestricted => this == PermissionStatus.restricted;
  bool get isLimited => this == PermissionStatus.limited;

  /// 转换为 UI 友好的状态枚举
  PermissionUiState toUiState() {
    if (isGranted) return PermissionUiState.granted;
    if (isPermanentlyDenied) return PermissionUiState.permanentlyDenied;
    if (isRestricted) return PermissionUiState.restricted;
    if (isLimited) return PermissionUiState.limited;
    return PermissionUiState.denied;
  }
}

/// UI 友好的权限状态
enum PermissionUiState { granted, denied, permanentlyDenied, restricted, limited }
