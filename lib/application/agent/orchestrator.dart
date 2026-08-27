import 'dart:async';

import '../../core/agent/agent.dart';
import '../../core/model/agent_response.dart';
import '../../core/model/message.dart';
import '../../core/repository/config_repository.dart';
import '../../core/repository/message_repository.dart';
import '../../core/repository/repository_error.dart';
import '../../core/repository/session_repository.dart';
import '../../core/util/log.dart';
import 'message_store.dart';
import 'response_serializer.dart';

/// 单个会话的 Agent 运行状态(UI 用)。
enum SendStatus { idle, sending, error }

/// 单次 run 的对外可观察状态。
class AgentRunState {
  AgentRunState({
    required this.conversationId,
    required this.status,
    this.turnId,
    this.errorMessage,
  });

  final String conversationId;
  final SendStatus status;

  /// 当前正在跑的 turnId;sending 时有值,idle / error 时为 null。
  final String? turnId;

  /// 最近一次错误信息(仅 status == error 时携带)。
  final String? errorMessage;

  AgentRunState copyWith({
    SendStatus? status,
    String? turnId,
    String? errorMessage,
  }) {
    return AgentRunState(
      conversationId: conversationId,
      status: status ?? this.status,
      turnId: turnId ?? this.turnId,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// Agent 运行协调器:管理 run 生命周期 + 多会话并行 + 消息落库。
///
/// **职责**(本类之前散落在 ChatPage 里,本类一次性收回):
/// * 启动 / 取消 / 重试 AgentRun;
/// * 把 [AgentResponse] 序列化为 Markdown,通过 [TurnMessageStore] 落库;
/// * 同会话的并发控制(同时只许一个 run);
/// * run 状态对外广播,UI 通过 Stream 观察。
///
/// **Page 退出 ≠ run 取消**:Orchestrator 是单例,run 状态归它管,
/// 不会随 Page dispose 而丢失;下次进 Page 直接 watch 最新状态即可。
class AgentOrchestrator {
  AgentOrchestrator({
    required Agent agent,
    required SessionRepository sessionRepository,
    required MessageRepository messageRepository,
    required ConfigRepository configRepository,
    TurnMessageStore? messageStore,
  })  : _agent = agent,
        _sessionRepository = sessionRepository,
        _messageRepository = messageRepository,
        _configRepository = configRepository,
        _messageStore = messageStore ??
            TurnMessageStore(messageRepository: messageRepository);

  final Agent _agent;
  // ignore: unused_field
  final SessionRepository _sessionRepository;
  final MessageRepository _messageRepository;
  final ConfigRepository _configRepository;
  final TurnMessageStore _messageStore;

  // 多会话并行:Map<conversationId, _RunSession>
  final Map<String, _RunSession> _activeRuns = {};

  // 对外广播的 run 状态流(broadcast,允许多 Page 订阅同一会话)。
  final StreamController<AgentRunState> _statesController =
      StreamController<AgentRunState>.broadcast();

  /// 所有会话的 run 状态流。订阅时按 conversationId 过滤。
  Stream<AgentRunState> get runStates => _statesController.stream;

  static const _tag = 'AgentOrchestrator';

  // ===== 对外 API =====

  /// 启动一次 Agent 运行。会话 user 消息落库 + 启动 Agent + 订阅流式事件。
  ///
  /// **并发策略**:同会话同时只许一个 run;已在跑则直接返回(由调用方决定提示)。
  /// 返回 `false` 表示"已在跑,本次发送被忽略";`true` 表示成功启动。
  Future<bool> send({
    required String conversationId,
    required String userInput,
  }) async {
    if (_activeRuns.containsKey(conversationId)) {
      Log.warn(_tag, '并发请求被忽略:会话已有 run 在跑',
          extra: {'id': conversationId});
      return false;
    }

    final text = userInput.trim();
    if (text.isEmpty) return false;

    // 1. 用户消息落库(DB watch 自动触发 UI 渲染)。
    await _messageRepository.append(Message(
      id: _newUserMessageId(),
      conversationId: conversationId,
      role: MessageRole.user,
      type: MessageType.text,
      content: text,
      toolCalls: null,
      createdAt: DateTime.now(),
      streaming: false,
    ));

    // 2. 准备 turnId + AgentRun + 订阅链路。
    final turnId = _newTurnId();
    final session = _RunSession(
      orchestrator: this,
      conversationId: conversationId,
      turnId: turnId,
    );
    _activeRuns[conversationId] = session;
    _emit(conversationId, status: SendStatus.sending, turnId: turnId);

    await session.start();
    return true;
  }

  /// 取消当前 run(若没有则 no-op)。
  void cancel(String conversationId) {
    final session = _activeRuns[conversationId];
    if (session == null) return;
    session.disposeSubscription();
  }

  /// 关闭整个协调器(应用退出时调用,释放 controller)。
  Future<void> dispose() async {
    for (final session in _activeRuns.values.toList()) {
      session.disposeSubscription();
    }
    _activeRuns.clear();
    await _statesController.close();
  }

  // ===== 内部 =====

  void _removeSession(String conversationId) {
    _activeRuns.remove(conversationId);
  }

  void _emit(
    String conversationId, {
    required SendStatus status,
    String? turnId,
    String? errorMessage,
  }) {
    _statesController.add(AgentRunState(
      conversationId: conversationId,
      status: status,
      turnId: turnId,
      errorMessage: errorMessage,
    ));
  }

  // ===== 历史 → AgentResponse 翻译(只用于回读上下文) =====

  List<AgentResponse> _toAgentResponses(List<Message> history) {
    const meta = AgentResponseMetadata.empty;
    return history
        .where((m) => m.role != MessageRole.user)
        .map((m) => AgentText(
              content: m.content,
              toolCalls: const [],
              metadata: meta,
            ))
        .toList(growable: false);
  }

  Future<List<AgentResponse>> _loadHistory(String conversationId) async {
    final historyMessages = await _messageRepository.loadHistory(conversationId);
    return _toAgentResponses(historyMessages);
  }

  // ===== ID 生成 =====

  String _newTurnId() {
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return 't-$ts';
  }

  String _newUserMessageId() {
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return 'u-$ts';
  }
}

/// 单次 run 的内部状态。生命周期 = AgentSubscription 的生命周期。
class _RunSession {
  _RunSession({
    required this.orchestrator,
    required this.conversationId,
    required this.turnId,
  });

  final AgentOrchestrator orchestrator;
  final String conversationId;
  final String turnId;

  AgentSubscription? _subscription;

  /// DB 操作串行化 chain:确保 appendDelta 们按顺序执行,
  /// 且 finalize 一定在所有 appendDelta 之后。
  ///
  /// **根因修复**:之前 doOnEach 回调是 async 的,但
  /// `_QuickAgentSubscription._stream.listen` 的 onData 是同步 void 调用,
  /// 不 await 返回的 Future。这导致多个 appendDelta 并发执行(竞态),
  /// 且 doOnComplete 的 finalize 可能在 appendDelta 完成之前执行
  /// (findById 返回 null → no-op → 消息不被落库)。
  Future<void> _pending = Future<void>.value();

  /// 本次 run 是否以错误终态结束(收到 AgentFinish(error))。
  ///
  /// 用于让 [start] 的 doOnComplete 跳过 finalize / bumpRound / emit idle,
  /// 错误已在 doOnEach 里落库 + 广播 SendStatus.error。
  bool _errored = false;

  Agent get _agent => orchestrator._agent;
  ConfigRepository get _configRepo => orchestrator._configRepository;
  TurnMessageStore get _store => orchestrator._messageStore;
  SessionRepository get _sessionRepo => orchestrator._sessionRepository;

  Future<void> start() async {
    try {
      final config = await _configRepo.load();
      final history = await orchestrator._loadHistory(conversationId);
      final handle = AgentHandle(
        conversationId: conversationId,
        history: history,
      );
      final run = _agent.run(handle: handle, config: config);

      _subscription = run.subscribe()
          .doOnEach((response) {
        // 终态错误:模型调用失败。QuickAgent 把异常包成 AgentFinish(error)
        // 作为普通事件 emit,而 serialize 对终态返回空串会被下面跳过,
        // 因此这里单独处理:把 errorMessage 落库为错误消息 + 广播 error 状态,
        // 避免"发出去没回答"的静默失败。
        if (response is AgentFinish && response.isError) {
          final err = response.errorMessage ?? '未知错误';
          _errored = true;
          _pending = _pending
              .then((_) => _store.appendDelta(
                    conversationId: conversationId,
                    turnId: turnId,
                    delta: err,
                  ))
              .then((_) => _store.markError(turnId, err))
              .then((_) {
            orchestrator._emit(
              conversationId,
              status: SendStatus.error,
              errorMessage: err,
            );
          }, onError: (e, st) {
            Log.error(_tag, '错误落库失败', error: e, stackTrace: st);
          });
          return;
        }
        final delta = AgentResponseSerializer.serialize(response);
        if (delta.isEmpty) return;
        // 串到 chain 末尾,不 await —— 保持 stream 不阻塞。
        // catch 防止 DB 异常变成 unhandled async error。
        _pending = _pending
            .then((_) => _store.appendDelta(
                  conversationId: conversationId,
                  turnId: turnId,
                  delta: delta,
                ))
            .then((_) {}, onError: (e, st) {
              Log.error(_tag, 'appendDelta 失败', error: e, stackTrace: st);
            });
      }).doOnError((e, st) {
        _pending = _pending.then((_) async {
          await _store.finalize(turnId);
          orchestrator._removeSession(conversationId);
          orchestrator._emit(
            conversationId,
            status: SendStatus.error,
            errorMessage: e.toString(),
          );
        });
      }).doOnComplete(() {
        // finalize 必须在所有 appendDelta 之后 —— 串到 chain 末尾。
        _pending = _pending.then((_) async {
          // 错误已在 doOnEach 落库 + 广播 error,这里不再 finalize / bumpRound /
          // emit idle,避免覆盖错误状态。
          if (_errored) {
            orchestrator._removeSession(conversationId);
            return;
          }
          await _store.finalize(turnId);
          try {
            await _sessionRepo.bumpRound(conversationId);
          } catch (e, st) {
            Log.error(_tag, 'bumpRound 失败', error: e, stackTrace: st);
          }
          orchestrator._removeSession(conversationId);
          orchestrator._emit(conversationId, status: SendStatus.idle);
        });
      }).doOnTerminate(() {
        // 兜底:任何路径退出都从 map 移除,防止泄漏。
        // 注意:不取消 _pending chain,让已入队的 DB 操作跑完。
        orchestrator._removeSession(conversationId);
      });
    } on RepositoryError catch (e) {
      Log.error(_tag, '启动 run 失败', error: e);
      orchestrator._removeSession(conversationId);
      orchestrator._emit(
        conversationId,
        status: SendStatus.error,
        errorMessage: e.message,
      );
    } catch (e, st) {
      Log.error(_tag, '启动 run 失败(未分类)', error: e, stackTrace: st);
      orchestrator._removeSession(conversationId);
      orchestrator._emit(
        conversationId,
        status: SendStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  void disposeSubscription() {
    final sub = _subscription;
    if (sub == null || sub.isDisposed) return;
    // 触发 doOnCancel + doOnTerminate + doFinally(cancelled),
    // doOnComplete 不会再触发,所以 _removeSession 一定会在 terminate 里跑。
    sub.dispose();
  }

  static const _tag = 'AgentOrchestrator';
}
