/// LLM 工具注册表。
///
/// 集中维护工具定义 + 执行入口。
/// ChatController 通过 [listDefinitions] 获取给 Provider 的工具描述，
/// 通过 [execute] 运行工具拿到结果。
library;

import 'dart:convert';

import '../../data/llm/llm.dart';
import 'file_tools.dart';
import 'wiki_tools.dart';

/// 工具执行结果
class ToolResult {
  const ToolResult({
    required this.toolCallId,
    required this.name,
    required this.success,
    this.content = '',
    this.error,
  });

  final String toolCallId;
  final String name;
  final bool success;

  /// 成功时返回的内容（通常是字符串或 JSON）
  final String content;

  /// 失败时的错误信息
  final String? error;

  /// 转为 tool 消息的 content 字段
  String toMessageContent() {
    if (success) return content;
    return 'ERROR: ${error ?? '未知错误'}';
  }
}

/// LLM 可用工具注册表
class ToolRegistry {
  ToolRegistry({required FileTools fileTools, required WikiTools wikiTools})
      : _wikiTools = wikiTools,
        _fileTools = fileTools;

  final FileTools _fileTools;
  final WikiTools _wikiTools;

  /// 工具名称常量 - 通用文件工具
  static const String readFile = 'read_file';
  static const String writeFile = 'write_file';
  static const String appendFile = 'append_file';
  static const String editFile = 'edit_file';
  static const String listFiles = 'list_files';

  /// 工具名称常量 - Wiki 专用工具
  static const String wikiRead = 'wiki_read';
  static const String wikiWrite = 'wiki_write';
  static const String wikiList = 'wiki_list';
  static const String wikiSearch = 'wiki_search';

  /// 当前已注册工具名集合（用于权限校验）
  static const Set<String> enabledTools = {
    readFile,
    writeFile,
    appendFile,
    editFile,
    listFiles,
    // Wiki 专用工具
    wikiRead,
    wikiWrite,
    wikiList,
    wikiSearch,
  };

  /// 返回所有工具的 LlmToolDefinition 列表
  ///
  /// 会一并传给 Provider 的 chatStream / chatComplete。
  List<LlmToolDefinition> listDefinitions() {
    return [
      // ─── Wiki 专用工具 ───────────────────────────────────────────
      LlmToolDefinition(
        name: wikiRead,
        description: '读取 Wiki 文件，返回文件内容和元数据（包括显示名称）。',
        parameters: {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description': 'Wiki 文件相对路径（英文文件名，含 .md 后缀）',
              'example': 'concepts/ai-assistant.md',
            },
          },
          'required': ['path'],
        },
      ),
      LlmToolDefinition(
        name: wikiWrite,
        description:
            '创建或更新 Wiki 页面。自动生成 front-matter，支持文件名验证、显示名称、自动溯源。',
        parameters: {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description': '文件名（英文小写、中划线分隔、.md 后缀）',
              'example': 'ai-assistant.md',
            },
            'title': {
              'type': 'string',
              'description': '显示名称（中文，用于 UI 展示）',
              'example': 'AI 助手',
            },
            'content': {
              'type': 'string',
              'description': '正文内容（Markdown 格式）',
            },
            'description': {
              'type': 'string',
              'description': '一句话摘要（≤ 200 字，可选，默认取内容前200字）',
            },
            'entity_type': {
              'type': 'string',
              'description':
                  '实体类型：concept/person/product/process/event（可选，默认 concept）',
              'default': 'concept',
            },
            'sources': {
              'type': 'array',
              'items': {'type': 'string'},
              'description': '引用来源列表（raw 文件路径，可选）',
              'example': ['raw/ai-notes.md'],
            },
            'parent_links': {
              'type': 'array',
              'items': {'type': 'string'},
              'description': '关联的父页面文件名列表（用于生成双向链接，可选）',
              'example': ['profile.md', 'concepts/llm.md'],
            },
          },
          'required': ['path', 'title', 'content'],
        },
      ),
      LlmToolDefinition(
        name: wikiList,
        description: '列出 Wiki 目录下指定子目录的文件，返回带显示名称的列表。',
        parameters: {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description': '子目录路径',
              'example': 'concepts/',
            },
          },
          'required': ['path'],
        },
      ),
      LlmToolDefinition(
        name: wikiSearch,
        description: '搜索 Wiki 文件内容，返回匹配结果及显示名称。',
        parameters: {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': '搜索关键词',
            },
            'path': {
              'type': 'string',
              'description': '搜索范围（可选，不填则搜索全部）',
            },
          },
          'required': ['query'],
        },
      ),

      // ─── 通用文件工具（保留兼容）────────────────────────────────
      LlmToolDefinition(
        name: readFile,
        description: '读取 Wiki 知识库内的文件内容。',
        parameters: {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description':
                  '文件相对路径，必须以 wiki/ 开头，如 "wiki/todos.md"',
            },
          },
          'required': ['path'],
        },
      ),
      LlmToolDefinition(
        name: writeFile,
        description:
            '完整覆盖写入 Wiki 文件。仅允许 wiki/profile.md、wiki/todos/todo-{uuid}.md 与 wiki/concepts/*.md。',
        parameters: {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description': '目标文件路径',
            },
            'content': {
              'type': 'string',
              'description': '完整文件内容',
            },
          },
          'required': ['path', 'content'],
        },
      ),
      LlmToolDefinition(
        name: appendFile,
        description:
            '追加内容到 Wiki 文件（不覆盖原文）。仅允许 wiki/profile.md、wiki/todos/todo-{uuid}.md 与 wiki/concepts/*.md。',
        parameters: {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description': '目标文件路径',
            },
            'content': {
              'type': 'string',
              'description': '要追加的内容',
            },
          },
          'required': ['path', 'content'],
        },
      ),
      LlmToolDefinition(
        name: editFile,
        description:
            '精确替换 Wiki 文件中指定的一段文本。仅允许 wiki/profile.md、wiki/todos/todo-{uuid}.md 与 wiki/concepts/*.md。',
        parameters: {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description': '目标文件路径',
            },
            'search': {
              'type': 'string',
              'description': '要被替换的原文本（必须与文件中某段完全一致）',
            },
            'replace': {
              'type': 'string',
              'description': '替换后的新文本',
            },
          },
          'required': ['path', 'search', 'replace'],
        },
      ),
      LlmToolDefinition(
        name: listFiles,
        description: '列出 wiki/ 目录下某子目录的所有 .md 文件。',
        parameters: {
          'type': 'object',
          'properties': {
            'dir': {
              'type': 'string',
              'description': '要列出的子目录，如 "wiki" 或 "wiki/concepts"',
              'default': 'wiki',
            },
          },
          'required': ['dir'],
        },
      ),
    ];
  }

  /// 生成给 LLM 看的 systemPrompt 描述
  ///
  /// 在不支持原生 function calling 的 Provider 上，把可用工具作为文本描述。
  String toSystemPromptDescription() {
    final buf = StringBuffer();
    buf.writeln('## 可用工具');
    buf.writeln();
    buf.writeln('你可以通过以下工具操作 Wiki 知识库：');
    buf.writeln();
    for (final def in listDefinitions()) {
      buf.writeln('### ${def.name}');
      buf.writeln(def.description);
      final props = def.parameters['properties'] as Map?;
      if (props != null) {
        for (final entry in props.entries) {
          final p = entry.value as Map;
          buf.writeln(
              '- ${entry.key}（${p['type'] ?? 'string'}）：${p['description'] ?? ''}');
        }
      }
      buf.writeln();
    }
    return buf.toString();
  }

  /// 执行工具调用，返回 ToolResult
  Future<ToolResult> execute(LlmToolCall call) async {
    try {
      final args = call.parsedArgs;

      // ─── Wiki 专用工具 ───────────────────────────────────────────
      switch (call.name) {
        case wikiRead:
          final path = args['path'] as String;
          final result = await _wikiTools.readFile(path);
          return _wrapWikiResult(call.id, call.name, result);

        case wikiWrite:
          final params = WikiPageParams(
            title: args['title'] as String,
            content: args['content'] as String,
            description: (args['description'] as String?) ?? '',
            entityType: (args['entity_type'] as String?) ?? 'concept',
            sources: (args['sources'] as List<dynamic>?)?.cast<String>() ?? [],
            parentLinks: (args['parent_links'] as List<dynamic>?)?.cast<String>() ?? [],
          );
          final result = await _wikiTools.writeFile(args['path'] as String, params);
          return _wrapWikiResult(call.id, call.name, result);

        case wikiList:
          final result = await _wikiTools.listFiles(args['path'] as String);
          return _wrapWikiResult(call.id, call.name, result);

        case wikiSearch:
          final result = await _wikiTools.searchFiles(
            args['query'] as String,
            path: args['path'] as String?,
          );
          return _wrapWikiResult(call.id, call.name, result);
      }

      // ─── 通用文件工具 ───────────────────────────────────────────
      final path = args['path'] as String? ?? args['dir'] as String? ?? '';
      final content = args['content'] as String? ?? '';

      switch (call.name) {
        case readFile:
          final r = await _fileTools.readFile(path);
          return ToolResult(
            toolCallId: call.id,
            name: call.name,
            success: true,
            content: r,
          );
        case writeFile:
          final r = await _fileTools.writeFile(path, content);
          return ToolResult(
            toolCallId: call.id,
            name: call.name,
            success: true,
            content: r,
          );
        case appendFile:
          final r = await _fileTools.appendFile(path, content);
          return ToolResult(
            toolCallId: call.id,
            name: call.name,
            success: true,
            content: r,
          );
        case editFile:
          final search = args['search'] as String? ?? '';
          final replace = args['replace'] as String? ?? '';
          final r = await _fileTools.editFile(path, search, replace);
          return ToolResult(
            toolCallId: call.id,
            name: call.name,
            success: true,
            content: r,
          );
        case listFiles:
          final r = await _fileTools.listFiles(path);
          return ToolResult(
            toolCallId: call.id,
            name: call.name,
            success: true,
            content: r,
          );
        default:
          return ToolResult(
            toolCallId: call.id,
            name: call.name,
            success: false,
            error: '未知工具：${call.name}',
          );
      }
    } on FileToolException catch (e) {
      return ToolResult(
        toolCallId: call.id,
        name: call.name,
        success: false,
        error: e.message,
      );
    } catch (e) {
      return ToolResult(
        toolCallId: call.id,
        name: call.name,
        success: false,
        error: '执行异常：$e',
      );
    }
  }

  /// 包装 Wiki 工具结果
  ToolResult _wrapWikiResult(String id, String name, WikiToolResult result) {
    if (result.success) {
      return ToolResult(
        toolCallId: id,
        name: name,
        success: true,
        content: jsonEncode(result.data),
      );
    } else {
      return ToolResult(
        toolCallId: id,
        name: name,
        success: false,
        error: result.error,
      );
    }
  }
}