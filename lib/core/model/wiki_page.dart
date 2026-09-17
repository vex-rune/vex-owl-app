/// Wiki 页面数据模型。
///
/// 采用不可变设计，通过 [copyWith] 创建修改后的副本。
/// 表示一个 Wiki 文档页面的元数据和内容信息。
library;

/// Wiki 页面数据模型。
///
/// 不可变对象，使用 [copyWith] 生成修改后的副本。
/// 包含页面文件名、标题、摘要、正文、标签等核心信息。
class WikiPage {
  const WikiPage({
    required this.fileName,
    required this.title,
    required this.summary,
    required this.content,
    required this.tags,
    required this.updatedAt,
    this.sourceRawPath,
  });

  /// 文件名（如 "profile.md"）
  final String fileName;

  /// 页面标题
  final String title;

  /// 页面摘要（用于索引检索）
  final String summary;

  /// 页面正文内容（Markdown 格式）
  final String content;

  /// 页面标签列表（用于索引检索）
  final List<String> tags;

  /// 源文件的原始路径（可选）
  final String? sourceRawPath;

  /// 页面最后更新时间
  final DateTime updatedAt;

  /// 创建当前页面的修改副本。
  ///
  /// 未指定的参数保持原值不变。
  WikiPage copyWith({
    String? fileName,
    String? title,
    String? summary,
    String? content,
    List<String>? tags,
    String? sourceRawPath,
    DateTime? updatedAt,
  }) {
    return WikiPage(
      fileName: fileName ?? this.fileName,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      content: content ?? this.content,
      tags: tags ?? this.tags,
      sourceRawPath: sourceRawPath ?? this.sourceRawPath,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WikiPage &&
          runtimeType == other.runtimeType &&
          fileName == other.fileName &&
          title == other.title &&
          summary == other.summary &&
          content == other.content &&
          _listEquals(tags, other.tags) &&
          sourceRawPath == other.sourceRawPath &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
        fileName,
        title,
        summary,
        content,
        Object.hashAll(tags),
        sourceRawPath,
        updatedAt,
      );

  @override
  String toString() =>
      'WikiPage(fileName: $fileName, title: $title, '
      'tags: $tags, updatedAt: $updatedAt)';

  /// 比较两个列表是否相等
  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
