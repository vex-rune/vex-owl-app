import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 工具调用的路径安全策略。
///
/// 所有 [FileTool] / [MediaTool] 等"读文件 / 读元信息"工具必须通过本类
/// 校验路径,避免 LLM 读取任意系统路径(如 /etc/passwd、~/.ssh/id_rsa)。
class ToolPathSafety {
  ToolPathSafety._();

  /// 单次读取文件的最大字节数(5 MB)。
  static const int maxReadBytes = 5 * 1024 * 1024;

  /// 允许访问的根目录(应用文档目录 / 应用支持目录)。
  ///
  /// 工具调用时入参 [path] 必须在该目录之内(规范化后 prefix 匹配)。
  /// 对不在白名单内的路径,返回错误字符串。
  static Future<Directory> _allowedRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    return docs;
  }

  /// 校验 [path] 是否在允许的根目录之内。
  ///
  /// 返回:
  /// * 校验通过时返回 `null`(无错误);
  /// * 校验失败时返回描述错误的字符串(供 tool 直接回传给 LLM)。
  static Future<String?> validatePath(String path) async {
    if (path.isEmpty) return '错误:path 不能为空';
    final root = await _allowedRoot();
    final rootPrefix = p.normalize(root.absolute.path);
    final target = p.normalize(p.absolute(path));
    if (!p.isWithin(rootPrefix, target)) {
      return '错误:path 必须位于应用目录($rootPrefix)之内';
    }
    return null;
  }

  /// 校验 [file] 大小是否在 [maxReadBytes] 之内。
  ///
  /// 返回:
  /// * 校验通过时返回 `null`;
  /// * 超出上限时返回描述错误的字符串。
  static String? validateSize(File file, int actualSize) {
    if (actualSize > maxReadBytes) {
      return '错误:文件大小 $actualSize 字节超过上限 $maxReadBytes 字节';
    }
    return null;
  }
}