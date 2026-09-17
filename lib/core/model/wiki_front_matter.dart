/// Wiki 文件统一 front-matter 模型（v5.0）
///
/// 文档规范：
/// - 所有 Wiki 文件以 `---` YAML 块开头，含 `title/description/weight/updated_at`
/// - 不同文件类型（profile/todos/sessions/concepts）有专属字段
/// - 解析与序列化走 [WikiFrontMatter] 的静态方法
library;

import 'dart:convert';

/// Wiki front-matter 通用模型
///
/// 强制字段：[title] / [description] / [weight] / [updatedAt]
/// 类型专属字段统一存 [extras]（如 todos 的 status/todo_id、sessions 的 session_id 等）。
class WikiFrontMatter {
  WikiFrontMatter({
    required this.title,
    required this.description,
    this.weight = 100,
    DateTime? updatedAt,
    this.extras = const {},
  }) : updatedAt = updatedAt ?? DateTime.now().toUtc();

  /// 页面标题（≤ 200 字展示给用户）
  final String title;

  /// 一句话摘要（≤ 200 字，用于 index.md / 列表预览）
  final String description;

  /// 排序权重（UI 按升序展示，默认 100）
  final int weight;

  /// 最后修改时间
  final DateTime updatedAt;

  /// 其他类型专属字段（todos 的 status/todo_id、sessions 的 session_id 等）
  final Map<String, dynamic> extras;

  WikiFrontMatter copyWith({
    String? title,
    String? description,
    int? weight,
    DateTime? updatedAt,
    Map<String, dynamic>? extras,
  }) {
    return WikiFrontMatter(
      title: title ?? this.title,
      description: description ?? this.description,
      weight: weight ?? this.weight,
      updatedAt: updatedAt ?? this.updatedAt,
      extras: extras ?? this.extras,
    );
  }

  // ───────────────────────── 序列化 ─────────────────────────

  /// 序列化为完整 front-matter 字符串（含 `---` 包裹）
  String serialize() {
    final buf = StringBuffer('---\n');
    buf.writeln('title: ${_escapeYaml(title)}');
    buf.writeln('description: ${_escapeYaml(description)}');
    buf.writeln('weight: $weight');
    buf.writeln('updated_at: ${updatedAt.toUtc().toIso8601String()}');
    for (final entry in extras.entries) {
      buf.writeln('${_yamlKey(entry.key)}: ${_formatValue(entry.value)}');
    }
    buf.write('---\n');
    return buf.toString();
  }

  /// 解析 front-matter 块（`---\n...\n---\n`）
  ///
  /// 返回解析结果 + 剩余 body。
  /// 若文件不含 front-matter，返回默认值 + 原文。
  static (WikiFrontMatter, String) parse(String content) {
    if (content.isEmpty) {
      return (WikiFrontMatter(title: '', description: ''), content);
    }
    final lines = const LineSplitter().convert(content);
    if (lines.isEmpty || lines.first.trim() != '---') {
      return (WikiFrontMatter(title: '', description: ''), content);
    }
    var endIdx = -1;
    for (var i = 1; i < lines.length; i++) {
      if (lines[i].trim() == '---') {
        endIdx = i;
        break;
      }
    }
    if (endIdx < 0) {
      return (WikiFrontMatter(title: '', description: ''), content);
    }

    String title = '';
    String description = '';
    int weight = 100;
    DateTime? updatedAt;
    final extras = <String, dynamic>{};

    for (var i = 1; i < endIdx; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final colonIdx = line.indexOf(':');
      if (colonIdx <= 0) continue;
      final key = line.substring(0, colonIdx).trim();
      final valueRaw = line.substring(colonIdx + 1).trim();
      final value = _stripQuotes(valueRaw);

      switch (key) {
        case 'title':
          title = value;
          break;
        case 'description':
          description = value;
          break;
        case 'weight':
          weight = int.tryParse(value) ?? 100;
          break;
        case 'updated_at':
          updatedAt = DateTime.tryParse(value);
          break;
        default:
          extras[key] = _decodeValue(value);
      }
    }

    final body = lines.sublist(endIdx + 1).join('\n');
    return (
      WikiFrontMatter(
        title: title,
        description: description,
        weight: weight,
        updatedAt: updatedAt,
        extras: extras,
      ),
      body,
    );
  }

  // ───────────────────────── 私有辅助 ─────────────────────────

  static String _escapeYaml(String s) {
    if (s.contains(':') || s.contains('#') || s.contains('\n')) {
      return '"${s.replaceAll('"', '\\"')}"';
    }
    return s;
  }

  static String _stripQuotes(String s) {
    if (s.length >= 2 &&
        ((s.startsWith('"') && s.endsWith('"')) ||
            (s.startsWith("'") && s.endsWith("'")))) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }

  static String _yamlKey(String key) {
    // 简单 key 仅允许 [a-zA-Z0-9_-]，否则加引号
    if (RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(key)) return key;
    return '"${key.replaceAll('"', '\\"')}"';
  }

  static String _formatValue(dynamic value) {
    if (value == null) return '';
    if (value is bool) return value ? 'true' : 'false';
    if (value is num) return value.toString();
    if (value is List) {
      return '[${value.map((e) => _formatValue(e)).join(', ')}]';
    }
    return _escapeYaml(value.toString());
  }

  static dynamic _decodeValue(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return '';
    if (v == 'true') return true;
    if (v == 'false') return false;
    if (v == 'null') return null;
    if (RegExp(r'^-?\d+$').hasMatch(v)) return int.tryParse(v) ?? v;
    if (RegExp(r'^-?\d+\.\d+$').hasMatch(v)) {
      return double.tryParse(v) ?? v;
    }
    if (v.startsWith('[') && v.endsWith(']')) {
      final inner = v.substring(1, v.length - 1).trim();
      if (inner.isEmpty) return <String>[];
      return inner
          .split(',')
          .map((s) => _decodeValue(s.trim()))
          .toList();
    }
    return v;
  }
}