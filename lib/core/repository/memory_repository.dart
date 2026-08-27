import '../model/memory.dart';

/// 记忆仓储抽象(WikeLLM 文件 IO)。
abstract class MemoryRepository {
  Future<String> readProfile();
  Future<void> writeProfile(String markdown);
  Future<String> readShortTerm();
  Future<void> appendShortTerm(String content);
  Future<String> readLongTerm();
  Future<void> appendLongTerm(String content);
  Future<void> writeHistoryLine({
    required String conversationId,
    required String title,
    required String summary,
  });
  Future<MemoryQueryResult> query(String scope, String keyword);
  Future<String> buildContextPrompt(String conversationId);
}
