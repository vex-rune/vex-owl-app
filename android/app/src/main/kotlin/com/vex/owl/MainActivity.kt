package com.vex.owl

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Owl 应用主 Activity。
 *
 * 注册 MethodChannel "com.vex.owl/manage_external_storage"，用于：
 * - 获取 Android SDK 版本
 * - 检查 MANAGE_EXTERNAL_STORAGE 是否已授予
 * - 跳转到系统"所有文件访问权限"设置页
 *
 * 这些是 Android 11+ 写公共存储目录（如 /storage/emulated/0/.owl/）所需的特殊处理。
 */
class MainActivity : FlutterActivity() {
    private val channelName = "com.vex.owl/manage_external_storage"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSdkInt" -> result.success(Build.VERSION.SDK_INT)
                    "isExternalStorageManager" -> {
                        result.success(
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                Environment.isExternalStorageManager()
                            } else {
                                // Android 10 及以下：WRITE_EXTERNAL_STORAGE 已足够
                                // 这里始终返回 true，权限由系统级 manifest 授予
                                true
                            }
                        )
                    }
                    "openManageStorageSettings" -> {
                        try {
                            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                                    data = Uri.parse("package:$packageName")
                                }
                            } else {
                                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                    data = Uri.parse("package:$packageName")
                                }
                            }
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("OPEN_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}