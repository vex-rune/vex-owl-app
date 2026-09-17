/// Wiki 文件统一抽象（v5.0）
///
/// 文档规范：
/// - 由 [WikiFrontMatter] + 正文 Markdown body 组成
/// - 路径格式：`{relativePath}`，如 `todos/todo-uuid.md`、`sessions/abc-123.md`
/// - 写入由 [WikiFileWriter] 统一加锁 + 原子写 + 自动维护 updated_at
library;

import 'wiki_front_matter.dart';

/// Wiki 文件抽象（front-matter + body + 路径）
class WikiFile {
  const WikiFile({
    required this.frontMatter,
    required this.body,
    required this.relativePath,
  });

  /// 头部 front-matter
  final WikiFrontMatter frontMatter;

  /// 正文 Markdown（不含 front-matter 块）
  final String body;

  /// 相对路径，如 `todos/todo-uuid.md`、`concepts/project-vex.md`、`profile.md`
  final String relativePath;

  WikiFile copyWith({
    WikiFrontMatter? frontMatter,
    String? body,
    String? relativePath,
  }) {
    return WikiFile(
      frontMatter: frontMatter ?? this.frontMatter,
      body: body ?? this.body,
      relativePath: relativePath ?? this.relativePath,
    );
  }

  /// 序列化为完整 Markdown 字符串（front-matter + body）
  String serialize() {
    final fm = frontMatter.serialize();
    final body = this.body;
    if (body.isEmpty) return fm;
    // body 已不含 front-matter 块，直接拼接
    if (body.startsWith('\n')) return '$fm$body';
    return '$fm\n$body';
  }

  /// 从完整 Markdown 字符串解析（含 front-matter 块）
  ///
  /// [relativePath] 用于标识该文件在 wiki/ 下的位置。
  static WikiFile fromMarkdown(String relativePath, String content) {
    final (fm, body) = WikiFrontMatter.parse(content);
    return WikiFile(
      frontMatter: fm,
      body: body,
      relativePath: relativePath,
    );
  }
}