import 'dart:io';

import 'tool_path_safety.dart';

/// 媒体工具:返回图片/视频/音频的基本元信息(占位实现)。
///
/// **安全**:所有路径必须位于 [ToolPathSafety] 允许的根目录之内;
/// 单文件读取不超过 [ToolPathSafety.maxReadBytes] 字节。
/// **异步**:全部使用异步 I/O,避免阻塞 UI isolate。
Map<String, dynamic> mediaToolSchema() => <String, dynamic>{
      'type': 'object',
      'properties': {
        'path': {'type': 'string', 'description': '媒体文件的绝对路径'},
      },
      'required': ['path'],
    };

Future<String> mediaToolRun(Map<String, dynamic> args) async {
  final path = args['path'] as String?;
  if (path == null || path.isEmpty) return '错误:path 不能为空';

  // 路径沙箱校验
  final pathErr = await ToolPathSafety.validatePath(path);
  if (pathErr != null) return pathErr;

  final file = File(path);
  final exists = await file.exists();
  if (!exists) return '错误:文件 $path 不存在';

  final stat = await file.stat();
  final ext = path.contains('.') ? path.split('.').last : '未知';
  return '文件:$path\n大小:${stat.size} 字节\n修改时间:${stat.modified.toIso8601String()}\n扩展名:$ext';
}