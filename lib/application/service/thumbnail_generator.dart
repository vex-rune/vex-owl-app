/// 图片缩略图生成工具
///
/// - 把原图压缩成最大 512px 的 JPEG 缩略图
/// - 缩略图存到 app 私有目录（系统媒体扫描器不可见）
/// - 返回新文件路径，失败返回 null
library;

import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../../../core/core.dart';

class ThumbnailGenerator {
  ThumbnailGenerator._();

  /// 缩略图最大边长（px）
  static const int _maxSize = 512;

  /// JPEG 压缩质量
  static const int _quality = 85;

  /// 生成缩略图
  ///
  /// [sourcePath] 原图路径（可以是 file://, mm_file:// 或 http URL）
  ///              - file:// 或本地路径：本地解码
  ///              - mm_file:// 或 http(s)://：当前不支持（需要下载）
  ///
  /// 返回私有目录下的缩略图路径，失败返回 null
  static Future<String?> generate(String sourcePath) async {
    try {
      // 跳过非本地文件
      if (sourcePath.startsWith('http://') ||
          sourcePath.startsWith('https://') ||
          sourcePath.startsWith('mm_file://')) {
        log.info('⚠️ 跳过非本地文件: $sourcePath');
        return null;
      }

      // 移除 file:// 前缀
      final cleanPath =
          sourcePath.startsWith('file://')
              ? sourcePath.substring(7)
              : sourcePath;

      final src = File(cleanPath);
      if (!src.existsSync()) {
        log.info('⚠️ 原图不存在: $cleanPath');
        return null;
      }

      // 读取 + 解码
      final bytes = await src.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        log.error('❌ 图片解码失败: $cleanPath');
        return null;
      }

      // 计算缩放比例
      img.Image resized;
      if (decoded.width <= _maxSize && decoded.height <= _maxSize) {
        resized = decoded;
      } else {
        resized = img.copyResize(
          decoded,
          width: decoded.width > decoded.height ? _maxSize : null,
          height: decoded.height >= decoded.width ? _maxSize : null,
          interpolation: img.Interpolation.linear,
        );
      }

      // 编码为 JPEG
      final jpegBytes = img.encodeJpg(resized, quality: _quality);

      // 存到私有目录
      final docsDir = await getApplicationDocumentsDirectory();
      final thumbDir = Directory('${docsDir.path}/thumbnails');
      if (!await thumbDir.exists()) {
        await thumbDir.create(recursive: true);
      }

      // 命名：原文件 hash + 时间戳
      final ts = DateTime.now().millisecondsSinceEpoch;
      final hash = cleanPath.hashCode.toRadixString(16);
      final destPath = '${thumbDir.path}/${ts}_$hash.jpg';

      await File(destPath).writeAsBytes(jpegBytes);

      log.info('✅ 缩略图已生成: $destPath (${jpegBytes.length} bytes)');
      return destPath;
    } catch (e, st) {
      log.error('❌ 生成缩略图失败: $e', st);
      return null;
    }
  }
}