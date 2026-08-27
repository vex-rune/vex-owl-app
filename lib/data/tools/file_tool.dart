import 'dart:io';

import 'tool_path_safety.dart';

/// 文件工具:读取应用沙箱目录下的文件 / 列出目录。
///
/// **安全**:所有路径必须位于 [ToolPathSafety] 允许的根目录之内;
/// 单次读取不超过 [ToolPathSafety.maxReadBytes] 字节。
/// **异步**:全部使用异步 I/O,避免阻塞 UI isolate。
Map<String, dynamic> fileToolSchema() => <String, dynamic>{
      'type': 'object',
      'properties': {
        'action': {
          'type': 'string',
          'enum': ['read', 'list'],
          'default': 'read',
        },
        'path': {'type': 'string', 'description': '文件或目录的绝对路径'},
      },
      'required': ['path'],
    };

Future<String> fileToolRun(Map<String, dynamic> args) async {
  final path = args['path'] as String?;
  if (path == null || path.isEmpty) return '错误:path 不能为空';
  final action = (args['action'] as String?) ?? 'read';

  // 路径沙箱校验
  final pathErr = await ToolPathSafety.validatePath(path);
  if (pathErr != null) return pathErr;

  final type = await FileSystemEntity.type(path);
  if (type == FileSystemEntityType.directory) {
    final dir = Directory(path);
    final exists = await dir.exists();
    if (!exists) return '错误:目录 $path 不存在';
    if (action == 'list') {
      final entries = <String>[];
      await for (final entity in dir.list()) {
        entries.add(entity.path.split(Platform.pathSeparator).last);
      }
      return '目录 $path 内容:\n${entries.join('\n')}';
    }
    return '错误:$path 是目录,请用 action=list';
  }
  if (type == FileSystemEntityType.file) {
    final file = File(path);
    final exists = await file.exists();
    if (!exists) return '错误:文件 $path 不存在';
    if (action == 'read') {
      final stat = await file.stat();
      final sizeErr = ToolPathSafety.validateSize(file, stat.size);
      if (sizeErr != null) return sizeErr;
      // 按 maxReadBytes 截断读取,避免一次 load 全部到内存。
      final raf = await file.open();
      try {
        final bytes = await raf.read(ToolPathSafety.maxReadBytes);
        final content = String.fromCharCodes(bytes);
        final truncated = stat.size > ToolPathSafety.maxReadBytes;
        return truncated ? '$content\n...(已截断)' : content;
      } finally {
        await raf.close();
      }
    }
    return '错误:$path 是文件,请用 action=read';
  }
  return '错误:路径 $path 不存在';
}