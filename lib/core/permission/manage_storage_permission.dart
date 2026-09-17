import 'dart:io';

import 'package:flutter/services.dart';

/// Android 11+ 写公共存储所需的特殊权限（MANAGE_EXTERNAL_STORAGE）辅助类
///
/// Android 11 (API 30) 起，受 Scoped Storage 限制，应用不能直接写
/// `/storage/emulated/0/` 下的任意位置，需要 `MANAGE_EXTERNAL_STORAGE`
/// 权限。此权限只能通过跳转系统设置让用户手动授予，无法用普通 API 弹窗授予。
///
/// 使用方式：
/// ```dart
/// if (await ManageStoragePermission.isGranted()) {
///   // 已授权
/// } else {
///   await ManageStoragePermission.openSystemSettings();
///   // 用户返回后再次 isGranted() 校验
/// }
/// ```
class ManageStoragePermission {
  ManageStoragePermission._();

  /// Channel 与 Android 原生通信
  static const _channel =
      MethodChannel('com.vex.owl/manage_external_storage');

  /// 是否为受 Scoped Storage 限制的 Android 版本（API 30+）
  static bool get _isRestrictedAndroid =>
      Platform.isAndroid &&
      _androidSdkInt != null &&
      _androidSdkInt! >= 30;

  /// Android SDK 版本号（懒加载缓存）
  static int? _androidSdkInt;
  static Future<int?> _getSdkInt() async {
    if (!Platform.isAndroid) return null;
    if (_androidSdkInt != null) return _androidSdkInt;
    try {
      _androidSdkInt = await _channel.invokeMethod<int>('getSdkInt');
    } catch (_) {
      _androidSdkInt = 0;
    }
    return _androidSdkInt;
  }

  /// 检查是否已获得 MANAGE_EXTERNAL_STORAGE
  ///
  /// - Android 10 及以下：始终返回 true（无需此权限）
  /// - Android 11+：调用原生 `Environment.isExternalStorageManager()` 检测
  static Future<bool> isGranted() async {
    if (!Platform.isAndroid) return true;
    final sdk = await _getSdkInt();
    if (sdk == null || sdk < 30) return true; // ≤ 29 不需要
    try {
      final ok = await _channel.invokeMethod<bool>('isExternalStorageManager');
      return ok ?? false;
    } catch (e) {
      // 原生端未实现或异常时返回 false，由 UI 引导用户升级
      return false;
    }
  }

  /// 跳转到系统的"所有文件访问权限"设置页
  ///
  /// Android 11+ 专用：用户需在系统设置里勾选"允许访问所有文件"。
  /// 跳不到时会降级到应用详情页。
  /// 返回 true 表示跳转意图已发出。
  static Future<bool> openSystemSettings() async {
    if (!_isRestrictedAndroid) return false;
    try {
      await _channel.invokeMethod('openManageStorageSettings');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Android 完整 Wiki 写入路径是否就绪
  ///
  /// 流程：
  /// 1. 已授权 → true
  /// 2. 未授权 → 由调用方决定如何引导（弹窗 / 跳设置）
  static Future<bool> canAccessPublicRoot() async {
    if (!Platform.isAndroid) return true;
    return isGranted();
  }
}