import '../../core/model/memory.dart';
import '../../core/repository/memory_repository.dart';

/// 记忆服务:对 MemoryRepository 的薄包装。
class MemoryService {
  MemoryService(this.repository);
  final MemoryRepository repository;

  Future<String> buildContextPrompt(String conversationId) =>
      repository.buildContextPrompt(conversationId);

  Future<void> writeHistoryLine({
    required String conversationId,
    required String title,
    required String summary,
  }) =>
      repository.writeHistoryLine(
        conversationId: conversationId,
        title: title,
        summary: summary,
      );

  Future<MemoryQueryResult> query(String scope, String keyword) =>
      repository.query(scope, keyword);

  Future<void> appendShortTerm(String content) =>
      repository.appendShortTerm(content);

  Future<void> appendLongTerm(String content) =>
      repository.appendLongTerm(content);

  Future<void> writeProfile(String markdown) =>
      repository.writeProfile(markdown);
}
