import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:langchain_openai/langchain_openai.dart';

import '../core/agent/agent.dart';
import '../core/agent/quick_agent.dart';
import '../core/agent/session_name_agent.dart';
import '../core/agent/tool_registry.dart';
import '../core/model/conversation.dart';
import '../core/model/message.dart';
import '../core/model/owl_config.dart';
import '../core/repository/config_repository.dart';
import '../core/repository/memory_repository.dart';
import '../core/repository/message_repository.dart';
import '../core/repository/session_repository.dart';
import '../data/repository/drift_config_repository.dart';
import '../data/repository/drift_memory_repository.dart';
import '../data/repository/drift_message_repository.dart';
import '../data/repository/drift_session_repository.dart';
import '../data/storage/database/app_database.dart';
import '../data/tools/bocha_search_tool.dart';
import '../data/tools/calc_tool.dart';
import '../data/tools/file_tool.dart';
import '../data/tools/history_query_tool.dart';
import '../data/tools/media_tool.dart';
import '../data/tools/memory_query_tool.dart';
import '../data/tools/time_tool.dart';
import 'agent/orchestrator.dart';
import 'conversation/conversation_service.dart';
import 'memory/memory_service.dart';

// ---- 数据库 ----

final appDatabaseProvider = FutureProvider<AppDatabase>((ref) async {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

// ---- 仓储 ----

final sessionRepositoryProvider = FutureProvider<SessionRepository>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftSessionRepository(db);
});

final messageRepositoryProvider = FutureProvider<MessageRepository>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftMessageRepository(db);
});

final memoryRepositoryProvider = FutureProvider<MemoryRepository>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftMemoryRepository(db);
});

final configRepositoryProvider = FutureProvider<ConfigRepository>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftConfigRepository(db);
});

// ---- 工具 ----

/// 工具注册中心。
///
/// 内部工具分两类:
/// 1. **静态工具**(time / calc / file / media):每次重建时重新 register;
/// 2. **依赖 repo 的工具**(memory_query / history_query):闭包持有 repo 引用,
///    这些 repo watch 自 Riverpod,当它们 dispose 时,本 provider 也会 dispose,
///    不会产生 stale repo。
final toolRegistryProvider = FutureProvider<ToolRegistry>((ref) async {
  final registry = ToolRegistry();

  // watch 配置 —— bochaApiKey 改了之后本 provider 自动重建,工具绑定新 key。
  final cfg = await ref.watch(currentConfigProvider.future);

  // 静态工具
  registry.register(
    name: 'get_current_time',
    description: '获取当前时间,返回 ISO8601 格式与时区信息。',
    inputJsonSchema: timeToolSchema(),
    func: timeToolRun,
  );
  registry.register(
    name: 'calculator',
    description: '安全表达式求值,支持 + - * / ^ sqrt()。',
    inputJsonSchema: calcToolSchema(),
    func: calcToolRun,
  );
  registry.register(
    name: 'file',
    description:
        '读取文件或列出目录内容。action=read(默认) 读取文件内容;action=list 列出目录。',
    inputJsonSchema: fileToolSchema(),
    func: fileToolRun,
  );
  registry.register(
    name: 'media_info',
    description: '获取媒体文件(图片/视频/音频)的基本元信息:文件大小、修改时间、扩展名。',
    inputJsonSchema: mediaToolSchema(),
    func: mediaToolRun,
  );

  // 联网搜索(博查)—— 需 API Key,留空时工具内部返回友好提示,不抛异常。
  registry.register(
    name: 'bocha_web_search',
    description:
        '联网实时搜索(博查 AI Search,支持中文 / 新闻 / 网页)。'
        '适用于查询实时信息、新闻、事实性知识。'
        '无需登录或离线无法回答的问题也调用此工具。',
    inputJsonSchema: bochaSearchToolSchema(),
    func: bindBochaSearchTool(apiKey: cfg.bochaApiKey),
  );

  // 依赖 repo 的工具 —— 通过 ref.watch 自动跟随 repo 生命周期
  final memoryRepo = await ref.watch(memoryRepositoryProvider.future);
  final sessionRepo = await ref.watch(sessionRepositoryProvider.future);
  final messageRepo = await ref.watch(messageRepositoryProvider.future);

  registry.register(
    name: 'memory_query',
    description: '检索用户记忆,scope 可选 profile / short_term / long_term / history。',
    inputJsonSchema: memoryQueryToolSchema(),
    func: bindMemoryQueryTool(memoryRepo),
  );
  registry.register(
    name: 'history_query',
    description:
        '查询会话历史消息。conversationId 可选(不传则列出所有会话标题);keyword 可选(按关键字过滤)。',
    inputJsonSchema: historyQueryToolSchema(),
    func: bindHistoryQueryTool(
      sessionRepo: sessionRepo,
      messageRepo: messageRepo,
    ),
  );

  return registry;
});

// ---- ChatOpenAI ----

/// 配置变更通知 provider —— 一个"信号量",没有任何状态,
/// 只用作 `ref.invalidate(configChangesProvider)` 的锚点,
/// 让 [chatOpenAIProvider] / [quickAgentProvider] 等 watch 它
/// 的对象在用户改 Settings 后自动重建。
final configChangesProvider = StateProvider<int>((ref) => 0);

/// 当前已加载的 [OwlConfig](监听 [configChangesProvider])。
///
/// 任何依赖配置的 Provider 应当 watch 本 provider,而不是
/// 直接读 [configRepositoryProvider] —— 这样 Settings 改动后
/// 它们会自动重建。
final currentConfigProvider = FutureProvider<OwlConfig>((ref) async {
  // watch 信号量,Settings 改动时本 provider 失效 → 下游也失效。
  ref.watch(configChangesProvider);
  final repo = await ref.watch(configRepositoryProvider.future);
  return repo.load();
});

final chatOpenAIProvider = FutureProvider<ChatOpenAI>((ref) async {
  final cfg = await ref.watch(currentConfigProvider.future);
  return ChatOpenAI(
    apiKey: cfg.apiKey,
    baseUrl: cfg.baseUrl,
    defaultOptions: ChatOpenAIOptions(
      model: cfg.model,
      temperature: cfg.temperature,
    ),
  );
});

// ---- Agent ----

/// 当前 Agent 实现:QuickAgent。
///
/// 以后接别的 Agent 实现时,在这里 switch 即可,ConversationService / UI 不变。
final quickAgentProvider = FutureProvider<Agent>((ref) async {
  final chat = await ref.watch(chatOpenAIProvider.future);
  final registry = await ref.watch(toolRegistryProvider.future);
  return QuickAgent(chat: chat, toolRegistry: registry);
});

/// 会话起名 Agent(非流式,只暴露 generateTitle())。
final sessionNameAgentProvider = FutureProvider<SessionNameAgent>((ref) async {
  final chat = await ref.watch(chatOpenAIProvider.future);
  return SessionNameAgent(chat: chat);
});

// ---- Application 服务 ----

final memoryServiceProvider = FutureProvider<MemoryService>((ref) async {
  final repo = await ref.watch(memoryRepositoryProvider.future);
  return MemoryService(repo);
});

/// 对话服务:Session CRUD + 起名 + 消息读写代理。
/// Agent 运行编排由 [AgentOrchestrator] 独立承担。
final conversationServiceProvider =
    FutureProvider<ConversationService>((ref) async {
      final sessionNameAgent =
          await ref.watch(sessionNameAgentProvider.future);
      final sessionRepo = await ref.watch(sessionRepositoryProvider.future);
      final messageRepo = await ref.watch(messageRepositoryProvider.future);
      final configRepo = await ref.watch(configRepositoryProvider.future);
      return ConversationService(
        sessionRepository: sessionRepo,
        messageRepository: messageRepo,
        configRepository: configRepo,
        sessionNameAgent: sessionNameAgent,
      );
    });

/// 会话列表实时流 —— UI 通过 `ref.watch(sessionsStreamProvider)`
/// 自动响应 DB 变更(新建 / 重命名 / 删除 / pin),无需手动 reload。
final sessionsStreamProvider = StreamProvider<List<Session>>((ref) async* {
  final repo = await ref.watch(sessionRepositoryProvider.future);
  yield* repo.watch();
});

// ---- AgentOrchestrator ----

/// Agent 运行协调器(单例,跨 Page 共享 run 状态)。
final agentOrchestratorProvider =
    FutureProvider<AgentOrchestrator>((ref) async {
  final agent = await ref.watch(quickAgentProvider.future);
  final sessionRepo = await ref.watch(sessionRepositoryProvider.future);
  final messageRepo = await ref.watch(messageRepositoryProvider.future);
  final configRepo = await ref.watch(configRepositoryProvider.future);

  final orchestrator = AgentOrchestrator(
    agent: agent,
    sessionRepository: sessionRepo,
    messageRepository: messageRepo,
    configRepository: configRepo,
  );

  ref.onDispose(orchestrator.dispose);
  return orchestrator;
});

/// 单个会话的 run 状态流(空值表示"未启动"或"已完成")。
final runStateProvider = StreamProvider.family<AgentRunState, String>(
  (ref, conversationId) async* {
    final orchestrator =
        await ref.watch(agentOrchestratorProvider.future);
    // 初始发射一个 idle 状态,UI 立即可以渲染"可发送"形态。
    yield AgentRunState(
      conversationId: conversationId,
      status: SendStatus.idle,
    );
    yield* orchestrator.runStates
        .where((state) => state.conversationId == conversationId);
  },
);

/// 单个会话的消息流(替代 ChatPage 内部的 _messages 列表)。
final conversationMessagesProvider =
    StreamProvider.family<List<Message>, String>(
  (ref, conversationId) async* {
    final repo = await ref.watch(messageRepositoryProvider.future);
    yield* repo.watch(conversationId);
  },
);
