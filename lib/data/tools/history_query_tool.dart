import '../../core/repository/message_repository.dart';
import '../../core/repository/session_repository.dart';

/// 会话历史查询工具:按关键字检索会话历史消息。
Map<String, dynamic> historyQueryToolSchema() => <String, dynamic>{
      'type': 'object',
      'properties': {
        'conversationId': {
          'type': 'string',
          'description': '会话 ID(不传则列出所有会话)',
        },
        'keyword': {'type': 'string', 'description': '按关键字过滤消息内容'},
        'limit': {'type': 'integer', 'default': 20},
      },
    };

Future<String> Function(Map<String, dynamic>) bindHistoryQueryTool({
  required SessionRepository sessionRepo,
  required MessageRepository messageRepo,
}) {
  return (args) async {
    final convId = args['conversationId'] as String?;
    final keyword = (args['keyword'] as String?) ?? '';
    final limit = (args['limit'] as num?)?.toInt() ?? 20;

    if (convId == null) {
      final sessions = await sessionRepo.snapshot();
      final titles = sessions.map((s) => '- ${s.title} (${s.id})').join('\n');
      return '当前会话列表:\n$titles';
    }

    final messages = await messageRepo.loadHistory(convId, limit: limit);
    var filtered = messages;
    if (keyword.isNotEmpty) {
      filtered = messages
          .where(
            (m) => m.content.toLowerCase().contains(keyword.toLowerCase()),
          )
          .toList();
    }
    if (filtered.isEmpty) return '未找到匹配的历史消息';
    final lines = filtered
        .map(
          (m) =>
              '[${m.createdAt.toIso8601String()}] [${m.role.name}] ${m.content}',
        )
        .join('\n');
    return '会话 $convId 历史消息:\n$lines';
  };
}
