import '../../core/agent/session_name_agent.dart';
import '../../core/model/conversation.dart';
import '../../core/model/message.dart';
import '../../core/model/owl_config.dart';
import '../../core/repository/config_repository.dart';
import '../../core/repository/message_repository.dart';
import '../../core/repository/repository_error.dart';
import '../../core/repository/session_repository.dart';
import '../../core/util/log.dart';

/// 会话门面(瘦化版):Session CRUD + 会话起名 + 消息读写代理。
///
/// **职责范围**(本版本已收敛):
/// * Session 聚合(create / findById / snapshot / watch / rename / pin / unpin / delete);
/// * 会话起名([generateTitle]);
/// * 历史消息读写([loadHistory] / [enqueueUserMessage])。
///
/// **不再负责**(已迁出):
/// * Agent 启动 + 落库编排 → [AgentOrchestrator];
/// * AgentResponse ↔ Message 翻译 → Orchestrator 内部。
///
/// **设计原则**:
/// * 纯 Dart,零 Flutter 依赖;
/// * 通过 Repository 接口解耦底层存储;
/// * 业务错误抛 [RepositoryError],调用方统一捕获。
class ConversationService {
  ConversationService({
    required SessionRepository sessionRepository,
    required MessageRepository messageRepository,
    required ConfigRepository configRepository,
    required SessionNameAgent sessionNameAgent,
  })  : _sessionRepository = sessionRepository,
        _messageRepository = messageRepository,
        _configRepository = configRepository,
        _sessionNameAgent = sessionNameAgent;

  final SessionRepository _sessionRepository;
  final MessageRepository _messageRepository;
  final ConfigRepository _configRepository;
  final SessionNameAgent _sessionNameAgent;

  static const _tag = 'ConversationService';

  /// 新会话的默认标题。
  static const String defaultTitle = '新对话';

  // ===== Session CRUD =====

  Future<Session> create({String title = defaultTitle, String agentId = 'fast-qa'}) {
    return _sessionRepository.create(title: title, agentId: agentId);
  }

  Future<Session?> findById(String id) => _sessionRepository.findById(id);

  Future<List<Session>> snapshot() => _sessionRepository.snapshot();

  Stream<List<Session>> watch() => _sessionRepository.watch();

  /// 重命名。
  Future<void> rename(String id, String newTitle) =>
      _sessionRepository.rename(id, newTitle);

  /// 置顶 / 取消置顶。
  Future<void> pin(String id) =>
      _translate(() => _sessionRepository.pin(id), '置顶会话');
  Future<void> unpin(String id) =>
      _translate(() => _sessionRepository.unpin(id), '取消置顶');

  /// 删除会话及其消息(实现负责级联或借助外键)。
  Future<void> delete(String id) =>
      _translate(() => _sessionRepository.delete(id), '删除会话');

  // ===== Message =====

  /// 落库用户消息 + 返回完整 Message。
  Future<Message> enqueueUserMessage({
    required String conversationId,
    required String userInput,
  }) async {
    final msg = Message(
      id: _newId('u'),
      conversationId: conversationId,
      role: MessageRole.user,
      type: MessageType.text,
      content: userInput,
      toolCalls: null,
      createdAt: DateTime.now(),
      streaming: false,
    );
    try {
      await _messageRepository.append(msg);
    } on RepositoryError {
      rethrow;
    } catch (e) {
      throw RepositoryError(
        RepositoryErrorKind.storage,
        '用户消息落库失败: $e',
        e,
      );
    }
    return msg;
  }

  /// 加载会话历史消息(只读,直接透传仓储)。
  Future<List<Message>> loadHistory(String conversationId, {int limit = 50}) =>
      _messageRepository.loadHistory(conversationId, limit: limit);

  // ===== 起名 =====

  /// 触发条件:
  /// * 会话当前标题仍为 [defaultTitle](说明还没有起过名);
  /// * 已存在至少一条用户消息。
  ///
  /// 满足条件则调用 [SessionNameAgent.generateTitle] 生成新标题并落库;
  /// **所有错误一律吞掉,仅打印日志** —— 起名失败不影响主链路。
  ///
  /// 返回最终写入的标题;若无需起名或起名失败,返回当前 session.title。
  Future<String> generateTitle(String conversationId) async {
    try {
      final session = await _sessionRepository.findById(conversationId);
      if (session == null) {
        Log.warn(_tag, '起名跳过:会话不存在', extra: {'id': conversationId});
        return defaultTitle;
      }
      if (session.title != defaultTitle) {
        // 已被改过名(用户手动 / 之前起过名),不再覆盖。
        return session.title;
      }

      final history = await _messageRepository.loadHistory(conversationId);
      if (history.every((m) => m.role != MessageRole.user)) {
        Log.warn(_tag, '起名跳过:尚无用户消息', extra: {'id': conversationId});
        return session.title;
      }

      final firstUser = history.firstWhere((m) => m.role == MessageRole.user);
      final config = await _loadConfig();

      final newTitle = await _sessionNameAgent.generateTitle(
        userInput: firstUser.content,
        config: config,
      );

      final finalTitle = _truncate(newTitle, 12);
      if (finalTitle.isEmpty || finalTitle == session.title) {
        return session.title;
      }

      await _sessionRepository.rename(conversationId, finalTitle);
      return finalTitle;
    } catch (e, st) {
      Log.error(_tag, '起名失败,保留原标题', error: e, stackTrace: st);
      return defaultTitle;
    }
  }

  // ===== 私有 =====

  /// 把仓储层"非业务错误"统一翻译成 [RepositoryError] 并附中文描述。
  Future<void> _translate(
    Future<void> Function() action,
    String userAction,
  ) async {
    try {
      await action();
    } on RepositoryError {
      rethrow;
    } catch (e) {
      throw RepositoryError(
        RepositoryErrorKind.storage,
        '$userAction失败: $e',
        e,
      );
    }
  }

  Future<OwlConfig> _loadConfig() async {
    try {
      return await _configRepository.load();
    } catch (e) {
      throw RepositoryError(
        RepositoryErrorKind.storage,
        '加载配置失败: $e',
        e,
      );
    }
  }

  String _truncate(String text, int max) {
    final cleaned = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.length <= max) return cleaned;
    return cleaned.substring(0, max);
  }

  String _newId(String prefix) {
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return '$prefix-$ts';
  }
}
