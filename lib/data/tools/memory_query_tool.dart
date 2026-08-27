import '../../core/repository/memory_repository.dart';

/// 记忆查询工具:按 scope + keyword 检索 WikeLLM 记忆。
Map<String, dynamic> memoryQueryToolSchema() => <String, dynamic>{
      'type': 'object',
      'properties': {
        'scope': {
          'type': 'string',
          'enum': ['profile', 'short_term', 'long_term', 'history'],
          'default': 'short_term',
        },
        'keyword': {'type': 'string', 'description': '检索关键字(可为空,空则返回全部)'},
      },
      'required': ['scope'],
    };

Future<String> Function(Map<String, dynamic>) bindMemoryQueryTool(
  MemoryRepository repo,
) {
  return (args) async {
    final scope = (args['scope'] as String?) ?? 'short_term';
    final keyword = (args['keyword'] as String?) ?? '';
    final result = await repo.query(scope, keyword);
    if (result.lines.isEmpty) {
      return '在 $scope 中未找到与 "$keyword" 相关的记忆';
    }
    return '在 ${result.scope.name} 中找到 ${result.lines.length} 条:\n${result.lines.join('\n')}';
  };
}
