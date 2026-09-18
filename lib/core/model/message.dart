/// 聊天消息数据模型。
///
/// 采用不可变设计，通过 [copyWith] 创建修改后的副本。
/// 每条消息关联一个会话 [sessionId]，包含角色、多模态内容、类型等信息。
library;

import 'dart:convert';

import 'llm_tool_call.dart';

/// 消息角色枚举
enum MessageRole {
  /// 用户发送的消息
  user,

  /// AI 助手回复的消息
  assistant,

  /// 系统消息（如提示、通知等）
  system,

  /// 工具调用返回的消息
  tool,
}

/// 消息内容类型枚举（保留兼容旧逻辑）
enum MessageType {
  /// 纯文本消息
  text,

  /// 图片消息
  image,

  /// 文件消息
  file,
}

/// 多模态内容片段（替换单一字符串）
sealed class MessagePart {
  const MessagePart();
}

/// 文本片段
class TextPart extends MessagePart {
  const TextPart(this.text);
  final String text;
}

/// 图片 URL 片段
class ImageUrlPart extends MessagePart {
  const ImageUrlPart(this.url, {this.detail = 'auto'});
  final String url;
  final String detail; // 'auto' / 'low' / 'high'
}

/// MiniMax 文件 ID 片段（用于引用上传到 MiniMax 的文件）
///
/// 使用方式：
/// 1. 先调用 `MinimaxProvider.uploadFile()` 上传文件获取 file_id
/// 2. 创建 `MiniMaxFileIdPart(fileId, type)` 添加到消息
/// 3. MiniMaxProvider 会将其序列化为 `mm_file://{file_id}` 格式
///
/// 文档：https://platform.minimax.cn/docs/api-reference/file-management-upload
class MiniMaxFileIdPart extends MessagePart {
  const MiniMaxFileIdPart(this.fileId, this.type);
  final String fileId;
  final String type; // 'image' / 'video' / 'audio'

  /// 转为 MiniMax API 格式的 URL（mm_file:// 协议）
  String toMinimaxUrl() => 'mm_file://$fileId';
}

/// 消息数据模型（不可变）
class Message {
  const Message({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.parts,
    required this.createdAt,
    this.streaming = false,
    this.toolCallId,
    this.toolName,
    this.toolCalls = const [],
    this.reasoning = '',
  });

  static String _generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  /// 创建用户消息（支持文本或文本+图片）
  factory Message.user({
    required String sessionId,
    String? content,
    List<MessagePart> parts = const [],
  }) {
    final allParts = <MessagePart>[
      if (content != null && content.isNotEmpty) TextPart(content),
      ...parts,
    ];
    return Message(
      id: _generateId(),
      sessionId: sessionId,
      role: MessageRole.user,
      parts: allParts,
      createdAt: DateTime.now(),
    );
  }

  factory Message.assistant({
    required String sessionId,
    String content = '',
  }) {
    return Message(
      id: _generateId(),
      sessionId: sessionId,
      role: MessageRole.assistant,
      parts: [if (content.isNotEmpty) TextPart(content)],
      createdAt: DateTime.now(),
    );
  }

  factory Message.system({
    required String sessionId,
    required String content,
  }) {
    return Message(
      id: _generateId(),
      sessionId: sessionId,
      role: MessageRole.system,
      parts: [TextPart(content)],
      createdAt: DateTime.now(),
    );
  }

  /// 创建工具调用返回的消息
  ///
  /// [toolCallId] 对应 LLM 调用的工具调用 ID（OpenAI 协议：每个 tool_call 有唯一 id）
  /// [toolName] 工具名称（部分协议不传 id 时用于溯源）
  /// [content] 工具返回结果（JSON 字符串或纯文本）
  factory Message.tool({
    required String sessionId,
    required String toolCallId,
    required String toolName,
    required String content,
  }) {
    return Message(
      id: _generateId(),
      sessionId: sessionId,
      role: MessageRole.tool,
      parts: [TextPart(content)],
      createdAt: DateTime.now(),
      toolCallId: toolCallId,
      toolName: toolName,
    );
  }

  final String id;
  final String sessionId;
  final MessageRole role;
  final List<MessagePart> parts;
  final DateTime createdAt;
  final bool streaming;

  /// 工具调用 ID（仅 role == tool 时有值）
  final String? toolCallId;

  /// 工具名称（仅 role == tool 时有值，用于显示）
  final String? toolName;

  /// assistant 消息请求的工具调用列表（仅在工具循环回合中使用）
  ///
  /// 该字段不为空时，序列化到 OpenAI 时会输出 `tool_calls` 字段。
  /// UI 上仍可显示原始 `content`（含工具卡片描述），不影响视觉。
  final List<LlmToolCall> toolCalls;

  /// 思考过程内容（reasoning_split=true 时由 Provider 流式填充）
  ///
  /// 与 `content` 平级，UI 上可独立折叠展示。
  /// 默认空字符串表示无思考。
  final String reasoning;

  /// 兼容旧 API：从 parts 提取纯文本内容
  String get content => parts
      .whereType<TextPart>()
      .map((p) => p.text)
      .join('');

  /// 是否包含图片
  bool get hasImage => parts.any((p) => p is ImageUrlPart);

  /// 获取所有图片 URL
  List<String> get imageUrls => parts
      .whereType<ImageUrlPart>()
      .map((p) => p.url)
      .toList();

  Message copyWith({
    String? id,
    String? sessionId,
    MessageRole? role,
    List<MessagePart>? parts,
    DateTime? createdAt,
    bool? streaming,
    String? content, // 直接覆盖（用于流式拼接到最后一段文本）
    String? toolCallId,
    String? toolName,
    List<LlmToolCall>? toolCalls,
    String? reasoning,
  }) {
    List<MessagePart> newParts = parts ?? this.parts;
    if (content != null) {
      // Replace last text part or append new
      newParts = [...newParts];
      if (newParts.isNotEmpty && newParts.last is TextPart) {
        newParts[newParts.length - 1] = TextPart(content);
      } else {
        newParts.add(TextPart(content));
      }
    }
    return Message(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      role: role ?? this.role,
      parts: newParts,
      createdAt: createdAt ?? this.createdAt,
      streaming: streaming ?? this.streaming,
      toolCallId: toolCallId ?? this.toolCallId,
      toolName: toolName ?? this.toolName,
      toolCalls: toolCalls ?? this.toolCalls,
      reasoning: reasoning ?? this.reasoning,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Message &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          sessionId == other.sessionId &&
          role == other.role &&
          _partsEqual(parts, other.parts) &&
          createdAt == other.createdAt &&
          streaming == other.streaming;

  static bool _partsEqual(List<MessagePart> a, List<MessagePart> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] is TextPart && b[i] is TextPart) {
        if ((a[i] as TextPart).text != (b[i] as TextPart).text) return false;
      } else if (a[i] is ImageUrlPart && b[i] is ImageUrlPart) {
        if ((a[i] as ImageUrlPart).url != (b[i] as ImageUrlPart).url) return false;
      } else {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(id, sessionId, role, parts.length, createdAt, streaming);

  // ── JSON 序列化 / 反序列化 ──

  /// 将消息序列化为 JSON Map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sessionId': sessionId,
      'role': role.name,
      'parts': parts.map((p) {
        if (p is TextPart) return {'type': 'text', 'text': p.text};
        if (p is ImageUrlPart) {
          return {'type': 'image_url', 'url': p.url, 'detail': p.detail};
        }
        return <String, dynamic>{};
      }).toList(),
      'createdAt': createdAt.toIso8601String(),
      if (toolCallId != null) 'toolCallId': toolCallId,
      if (toolName != null) 'toolName': toolName,
      if (reasoning.isNotEmpty) 'reasoning': reasoning,
      if (toolCalls.isNotEmpty)
        'toolCalls': toolCalls
            .map((tc) => {
                  'id': tc.id,
                  'name': tc.name,
                  'arguments': tc.arguments,
                })
            .toList(),
    };
  }

  /// 从 JSON Map 反序列化消息
  factory Message.fromJson(Map<String, dynamic> json) {
    final roleStr = json['role'] as String? ?? 'assistant';
    final role = MessageRole.values.firstWhere(
      (r) => r.name == roleStr,
      orElse: () => MessageRole.assistant,
    );
    final partsList = (json['parts'] as List<dynamic>?) ?? [];
    final parts = partsList.map<MessagePart>((p) {
      final type = p['type'] as String? ?? 'text';
      if (type == 'image_url') {
        return ImageUrlPart(
          p['url'] as String? ?? '',
          detail: p['detail'] as String? ?? 'auto',
        );
      }
      return TextPart(p['text'] as String? ?? '');
    }).toList();
    return Message(
      id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      sessionId: json['sessionId'] as String? ?? '',
      role: role,
      parts: parts,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      toolCallId: json['toolCallId'] as String?,
      toolName: json['toolName'] as String?,
      reasoning: json['reasoning'] as String? ?? '',
      toolCalls: (json['toolCalls'] as List<dynamic>?)
              ?.map((tc) => LlmToolCall(
                    id: tc['id'] as String? ?? '',
                    name: tc['name'] as String? ?? '',
                    arguments: tc['arguments'] as String? ?? '',
                  ))
              .toList() ??
          const [],
    );
  }

  /// 从 JSON 字符串列表反序列化
  static List<Message> listFromJson(String jsonString) {
    if (jsonString.trim().isEmpty) return [];
    try {
      final decoded = jsonString is String
          ? (jsonString.startsWith('[')
              ? _parseJsonList(jsonString)
              : _parseJsonLines(jsonString))
          : <dynamic>[];
      return decoded
          .map((e) => Message.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static List<dynamic> _parseJsonList(String s) {
    return List<dynamic>.from(jsonDecode(s) as List);
  }

  static List<dynamic> _parseJsonLines(String s) {
    // 兼容旧格式 "role: content\n"，转换为 Message 列表
    // 注意：旧格式信息有限，只恢复基本内容
    return s.split('\n').where((l) => l.trim().isNotEmpty).map((line) {
      final colonIdx = line.indexOf(': ');
      if (colonIdx < 0) return <String, dynamic>{};
      final role = line.substring(0, colonIdx);
      final content = line.substring(colonIdx + 2);
      return {
        'role': role,
        'parts': [
          {'type': 'text', 'text': content}
        ],
      };
    }).toList();
  }

  @override
  String toString() => 'Message(id: $id, role: $role, parts: ${parts.length})';

  // ── JSONL 序列化 ─────────────────────────────────────────────────────

  /// 序列化为单行 JSON 对象（用于 messages.jsonl）
  ///
  /// 区别于 toJson()：不包含 streaming 字段（写入时 streaming 恒为 false）
  Map<String, dynamic> toJsonl() {
    final map = toJson();
    map.remove('streaming'); // 写入时移除流式标记
    return map;
  }

  /// 从单行 JSON 对象反序列化
  factory Message.fromJsonl(Map<String, dynamic> json) {
    // fromJson 本身已支持完整解析，调用它即可
    return Message.fromJson({
      ...json,
      'streaming': false, // JSONL 存储的都是已完成的非流式消息
    });
  }
}
