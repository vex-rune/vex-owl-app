/// Markdown 通用序列化工具。
///
/// 提供 `wiki/context-settings.md` 和 `wiki/api-configs.md` 共用的
/// 序列化原语：YAML-like 行解析、Front-matter 解析、段（`##`）划分。
///
/// 这些函数均为纯函数，不涉及任何 I/O，调用方负责文件读写。
library;

/// 单个 `## 段名` 下的内容节点（`- key：value` 行）
class KvEntry {
  const KvEntry(this.key, this.value);

  final String key;
  final String value;

  @override
  String toString() => '- $key：$value';
}

/// 解析后的单个段落（`## 段名` + N 个 kv 行）
class MarkdownSection {
  MarkdownSection(this.title, [List<KvEntry>? entries])
      : entries = entries ?? [];

  /// 段落标题（如 `⚙️ 上下文管理`），不含 `## ` 前缀
  final String title;

  /// 段落下的 `- key：value` 行列表（保持原始顺序）
  final List<KvEntry> entries;

  /// 设置或更新某个 key 的 value（不存在则追加到末尾）
  void set(String key, String value) {
    final idx = entries.indexWhere((e) => e.key == key);
    if (idx >= 0) {
      entries[idx] = KvEntry(key, value);
    } else {
      entries.add(KvEntry(key, value));
    }
  }

  /// 读取某个 key 的 value，未找到返回 null
  String? get(String key) {
    for (final e in entries) {
      if (e.key == key) return e.value;
    }
    return null;
  }

  /// 删除某个 key 的行
  void remove(String key) {
    entries.removeWhere((e) => e.key == key);
  }
}

/// Markdown front-matter 解析结果
class FrontMatter {
  FrontMatter({this.version = 1, this.extra = const {}});

  /// `version: 1` 等数字字段
  final int version;

  /// 其他未知字段（向前兼容保留）
  final Map<String, String> extra;

  String toMarkdown() {
    final buf = StringBuffer('---\n');
    buf.writeln('version: $version');
    for (final entry in extra.entries) {
      buf.writeln('${entry.key}: ${entry.value}');
    }
    buf.write('---\n');
    return buf.toString();
  }
}

/// Markdown 解析工具集
class MarkdownParser {
  /// 解析 front-matter（`---\n...\n---\n`），返回剩余正文
  static (FrontMatter, String) parseFrontMatter(String content) {
    final lines = const OwlLineSplitter().convert(content);
    if (lines.isEmpty || lines.first.trim() != '---') {
      return (FrontMatter(), content);
    }

    var endIdx = -1;
    for (var i = 1; i < lines.length; i++) {
      if (lines[i].trim() == '---') {
        endIdx = i;
        break;
      }
    }
    if (endIdx < 0) {
      return (FrontMatter(), content);
    }

    var version = 1;
    final extra = <String, String>{};
    for (var i = 1; i < endIdx; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final m = RegExp(r'^([^：:]+)\s*[：:]\s*(.*)$').firstMatch(line);
      if (m == null) continue;
      final k = m.group(1)!.trim();
      final v = m.group(2)!.trim();
      if (k == 'version') {
        version = int.tryParse(v) ?? 1;
      } else {
        extra[k] = v;
      }
    }

    final body = lines.sublist(endIdx + 1).join('\n');
    return (FrontMatter(version: version, extra: extra), body);
  }

  /// 解析正文，按 `## 段名` 划分段落
  static List<MarkdownSection> parseSections(String body) {
    final result = <MarkdownSection>[];
    final lines = const OwlLineSplitter().convert(body);

    String? currentTitle;
    final currentEntries = <KvEntry>[];

    void flush() {
      if (currentTitle != null) {
        result.add(MarkdownSection(currentTitle!, List.of(currentEntries)));
      }
      currentTitle = null;
      currentEntries.clear();
    }

    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.startsWith('## ')) {
        flush();
        currentTitle = line.substring(3).trim();
        continue;
      }
      if (currentTitle == null) continue;
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      // 仅解析 `- key：value` 形式的列表项
      final m = RegExp(r'^-\s+([^：:]+)\s*[：:]\s*(.+)$').firstMatch(trimmed);
      if (m != null) {
        currentEntries.add(KvEntry(m.group(1)!.trim(), m.group(2)!.trim()));
      }
    }
    flush();

    return result;
  }
}

/// 反向序列化工具：将 `FrontMatter + List<Section>` 还原为 Markdown 字符串
class MarkdownWriter {
  /// 序列化 FrontMatter + 段落列表
  static String serialize({
    required FrontMatter frontMatter,
    required List<MarkdownSection> sections,
    String? title,
  }) {
    final buf = StringBuffer();
    buf.write(frontMatter.toMarkdown());
    buf.writeln();
    if (title != null) {
      buf.writeln('# $title');
      buf.writeln();
    }
    for (final s in sections) {
      buf.writeln('## ${s.title}');
      buf.writeln();
      for (final e in s.entries) {
        buf.writeln(e.toString());
      }
      buf.writeln();
    }
    return buf.toString();
  }
}

/// OwlLineSplitter 复用 dart:convert 以避免重复实现
class OwlLineSplitter {
  const OwlLineSplitter();
  List<String> convert(String input) =>
      input.split(RegExp(r'\r\n|\r|\n'));
}