/// 会话仓库抽象接口（v6.4）
///
/// 抽象会话数据的 CRUD 操作，与具体存储实现解耦。
/// 默认实现：[FileSessionRepository]（文件系统 + JSONL）
library;

import '../../core/model/session.dart';
import '../../core/model/message.dart';

/// 会话仓库接口
abstract class ISessionRepository {
  /// 加载所有会话元数据（按 updatedAt 降序）
  Future<List<Session>> listAll();

  /// 创建新会话
  Future<Session> create(String name);

  /// 更新会话元数据
  Future<void> update(Session session);

  /// 删除会话（删除整个目录）
  Future<void> delete(String sessionId);

  /// 归档会话（移动到 .archive/）
  Future<void> archive(String sessionId);

  /// 取消归档
  Future<void> unarchive(String sessionId);

  /// 加载消息历史（逐行读取 messages.jsonl）
  Future<List<Message>> loadMessages(String sessionId);

  /// 保存消息历史（全量覆写 messages.jsonl）
  Future<void> saveMessages(String sessionId, List<Message> messages);

  /// 追加消息到 messages.jsonl（高性能，writeln 追加）
  Future<void> appendMessages(String sessionId, List<Message> messages);

  /// 会话变更流（供 SessionController 订阅）
  Stream<void> get changes;

  /// 获取单个会话
  Future<Session?> getById(String sessionId);
}
