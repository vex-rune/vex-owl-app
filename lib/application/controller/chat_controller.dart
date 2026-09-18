import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../../core/core.dart';
import '../../core/prompt/ingest_prompt.dart' as ip;
import '../../core/prompt/query_prompt.dart' as qp;
import '../../data/llm/llm.dart';
import '../service/context_compressor.dart';
import '../service/file_tools.dart';
import '../service/session_file_service.dart';
import '../service/tool_registry.dart';
import '../service/wiki_tools.dart';

import 'session_controller.dart';
import 'settings_controller.dart';
import 'provider_controller.dart';

/// 聊天逻辑控制器（v6.4）
///
/// 负责消息发送、真实 LLM 流式响应接收、上下文管理等核心聊天流程。
/// 通过构造函数注入 [Ref]，再从 `app_providers` 中获取仓库与 [SessionController]。
///
/// v6.4 变更：
/// - `_saveContext()` 改为调用 `ISessionRepository.appendMessages()`
/// - 添加 `_sending` 标志位防止并发发送（C3）
/// - 修复 `stopGeneration` 状态不一致：中断时将所有 streaming=true 的消息标记为 streaming=false（C4）
/// - 修复 H3：自动命名只触发一次（用 `_named` 标志位）
class ChatController extends ChangeNotifier {
  ChatController(this._ref) {
    log.debug('初始化 ChatController');
    _sessionCtrl = _ref.read(sessionControllerProvider);
    _sessionCtrl.addListener(_onSessionChanged);
    _settingsCtrl = _ref.read(settingsControllerProvider);
    _settingsCtrl.addListener(_onSettingsChanged);
    _providerCtrl = _ref.read(providerControllerProvider);

    // 初始化文件工具集（白名单 + 原子写入）
    final wiki = _ref.read(wikiRepositoryProvider);
    final fileTools = FileTools(wiki);
    final wikiTools = WikiTools('');  // 根路径后续设置
    _toolRegistry = ToolRegistry(fileTools: fileTools, wikiTools: wikiTools);
    // 异步设置 Wiki 根路径（用于解析白名单路径）
    _initToolRootPath(fileTools, wiki);

    // 初始化上下文压缩器（依赖注入）
    _compressor = ContextCompressor(DefaultCompressorDependencies(
      settings: _settingsCtrl.settings,
      defaultConfig: _settingsCtrl.defaultConfig,
      sessionFileService: SessionFileService(wiki),
      llmCaller: ({required systemPrompt, required userPrompt, required config}) async {
        final provider = _providerCtrl.resolveProvider(config);
        return provider.chatComplete(
          config,
          messages: [Message.user(sessionId: '', content: userPrompt)],
          systemPrompt: systemPrompt,
        );
      },
    ));
  }

  /// 工具调用循环上限（防止无限循环消耗 Token）
  static const int _maxToolRounds = 3;

  final Ref _ref;
  late final SessionController _sessionCtrl;
  late final SettingsController _settingsCtrl;
  late final ProviderController _providerCtrl;
  late final ContextCompressor _compressor;
  late final ToolRegistry _toolRegistry;

  /// 异步探测 Wiki 根目录的绝对路径，注入到 FileTools。
  Future<void> _initToolRootPath(FileTools fileTools, wiki) async {
    try {
      final root = await wiki.getRootPath();
      if (root.isNotEmpty) {
        fileTools.setRootPath(root);
        log.info(
          '🔧 FileTools 根目录已设置：$root',
        );
      }
    } catch (e) {
      log.info('⚠️ FileTools 根目录初始化失败：$e');
    }
  }

  // ── 内部可变状态 ──

  /// 当前消息所属的会话 ID
  String? _currentSessionId;

  List<Message> _messages = const [];
  bool _isStreaming = false;

  /// 修复 C3：发送锁，防止并发调用 sendMessage
  bool _sending = false;

  /// 修复 H3：自动命名标志位，防止重复触发
  bool _named = false;

  int _inputTokenEstimate = 0;
  int _outputTokensUsed = 0;
  int _inputTokensUsed = 0;
  String? _lastError;

  /// 流式响应的取消令牌（用于中断生成）
  Completer<void>? _streamCancelToken;

  // ── 回调（UI 层订阅用于 SnackBar 提示） ──

  void Function(String message)? onWarning;
  void Function(String message)? onError;

  // ── Getters ──

  List<Message> get messages => _messages;
  bool get isStreaming => _isStreaming;
  int get inputTokenEstimate => _inputTokenEstimate;
  int get outputTokensUsed => _outputTokensUsed;
  int get inputTokensUsed => _inputTokensUsed;
  String? get lastError => _lastError;

  /// 当前激活 Provider 的显示名称
  String? get activeProviderName {
    final cfg = _settingsCtrl.defaultConfig;
    if (cfg == null) return null;
    return _providerCtrl.resolveProvider(cfg).displayName;
  }

  /// 当前激活的模型名称
  String? get activeModelName => _settingsCtrl.defaultConfig?.modelName;

  @override
  void dispose() {
    _sessionCtrl.removeListener(_onSessionChanged);
    _settingsCtrl.removeListener(_onSettingsChanged);
    super.dispose();
  }

  /// 当 SessionController 通知变化时检查是否真正切换了会话
  void _onSessionChanged() {
    final newId = _sessionCtrl.currentSession?.id;
    if (newId != _currentSessionId) {
      _currentSessionId = newId;
      _inputTokenEstimate = 0;
      _named = false; // 重置自动命名标志
      // 从 SessionController 同步消息（不再单独加载）
      _messages = _sessionCtrl.currentMessages;
      notifyListeners();
    }
  }

  /// 当设置变更时通知 UI 刷新徽标
  void _onSettingsChanged() {
    notifyListeners();
  }

  /// 发送用户消息并获取 AI 回复
  ///
  /// 修复 C3：添加 `_sending` 锁，防止并发调用
  Future<void> sendMessage(String content) async {
    await sendMessageWithParts(
      content: content,
      parts: const [],
    );
  }

  /// 发送带多模态内容的消息（支持图片、视频、音频等）
  ///
  /// [content] 文本内容
  /// [parts] 多模态内容片段（如 MiniMaxFileIdPart）
  Future<void> sendMessageWithParts({
    required String content,
    required List<MessagePart> parts,
  }) async {
    if (content.trim().isEmpty) return;

    // 修复 C3：防止并发发送
    if (_sending) {
      log.info('⚠️ 上一条消息尚未发送完成');
      return;
    }
    _sending = true;

    final session = _sessionCtrl.currentSession;
    if (session == null) {
      _lastError = '请先创建或选择一个会话';
      notifyListeners();
      onError?.call(_lastError!);
      _sending = false;
      return;
    }

    final config = _settingsCtrl.defaultConfig;
    if (config == null) {
      _lastError = '请先在设置中添加并启用一个 API 配置';
      log.info('❌ 无默认配置，消息未发送');
      notifyListeners();
      onError?.call(_lastError!);
      _sending = false;
      return;
    }

    // 1. 清理可能残留的流式占位消息（上次调用被中断时）
    if (_messages.isNotEmpty && _messages.last.streaming) {
      _messages = _messages.sublist(0, _messages.length - 1);
    }

    // 2. Token 阈值告警（非阻塞）
    final tokens = TokenCounter.estimateTokens(content);
    if (tokens > _settingsCtrl.chatTokenThreshold) {
      log.info('⚠️ Token 超阈值 $tokens > ${_settingsCtrl.chatTokenThreshold}');
      onWarning?.call(
          '本条消息约 $tokens tokens，超过阈值 ${_settingsCtrl.chatTokenThreshold}');
    }
    _inputTokenEstimate = tokens;

    // 3. 添加用户消息（支持多模态内容）
    _currentSessionId = session.id;
    final userMessage = Message.user(
      sessionId: session.id,
      content: content.trim(),
      parts: parts,
    );
    _messages = [..._messages, userMessage];
    log.info('📤 用户发送: "${content.trim().substring(0, content.trim().length > 30 ? 30 : content.trim().length)}${content.trim().length > 30 ? '...' : ''}"');
    notifyListeners();

    // 4. 修复 H3：首条消息触发 LLM 自动命名（只触发一次）
    if (_messages.length == 1 && !_named) {
      _named = true;
      log.debug('🗓️ 首条消息，触发自动命名');
      unawaited(_autoNameSession(session.id, content.trim()));
    }

    // 5. 创建助手消息占位（用于流式填充）
    final assistantMessage = Message.assistant(
      sessionId: session.id,
      content: '',
    ).copyWith(streaming: true);
    _messages = [..._messages, assistantMessage];
    _isStreaming = true;
    _streamCancelToken = Completer<void>();
    notifyListeners();

    // 6. 解析 Provider 并启动流式调用（带工具调用循环）
    final provider = _providerCtrl.resolveProvider(config);
    final tools = _toolRegistry.listDefinitions();

    try {
      for (var round = 0; round < _maxToolRounds; round++) {
        final systemPrompt = await _buildSystemPrompt();
        final contextMessages = _buildContextMessages();

        final toolCallsThisRound = await _streamOnce(
          provider,
          config,
          messages: contextMessages,
          systemPrompt: systemPrompt,
          tools: tools,
        );

        if (toolCallsThisRound.isEmpty) break;

        log.debug(
          '🔧 第 ${round + 1} 轮工具调用：${toolCallsThisRound.map((c) => c.name).join(', ')}',
        );

        _appendToolCallMessages(toolCallsThisRound);

        for (final call in toolCallsThisRound) {
          final result = await _toolRegistry.execute(call);
          _appendToolResultMessage(result);
        }

        _messages = [
          ..._messages,
          Message.assistant(sessionId: session.id, content: '').copyWith(streaming: true),
        ];
        notifyListeners();
      }
    } catch (e) {
      _applyStreamEvent(LlmStreamEvent.error('调用失败：$e'));
    } finally {
      _isStreaming = false;
      _streamCancelToken = null;
      _sending = false; // 修复 C3：释放发送锁

      // 修复 C4：关闭所有流式占位标志
      final updated = [..._messages];
      for (var i = 0; i < updated.length; i++) {
        if (updated[i].streaming) {
          updated[i] = updated[i].copyWith(streaming: false);
        }
      }
      final lastIdx = updated.length - 1;
      if (lastIdx >= 0) {
        final finalContent = updated[lastIdx].content;
        log.info('✅ 流式完成，回复 "${finalContent.length > 40 ? '${finalContent.substring(0, 40)}...' : finalContent}"');
      }
      _messages = updated;
      notifyListeners();

      // 7. 保存上下文到会话（v6.4：追加消息到 JSONL）
      await _saveContext(session.id);
    }
  }

  /// 单次 LLM 流式调用，结束后返回工具调用列表（若无则为空）
  Future<List<LlmToolCall>> _streamOnce(
    LlmProvider provider,
    ApiConfig config, {
    required List<Message> messages,
    required String systemPrompt,
    required List<LlmToolDefinition> tools,
  }) async {
    final toolCalls = <LlmToolCall>[];
    try {
      await for (final event in provider.chatStream(
        config,
        messages: messages,
        systemPrompt: systemPrompt,
        tools: tools.isNotEmpty ? tools : null,
      )) {
        if (_streamCancelToken?.isCompleted == true) break;
        if (event.toolCalls != null && event.toolCalls!.isNotEmpty) {
          toolCalls.addAll(event.toolCalls!);
          continue;
        }
        _applyStreamEvent(event);
      }
    } catch (e) {
      _applyStreamEvent(LlmStreamEvent.error('调用失败：$e'));
    }
    return toolCalls;
  }

  /// 把工具调用绑定到最后一条 assistant 占位消息
  void _appendToolCallMessages(List<LlmToolCall> calls) {
    if (calls.isEmpty) return;
    final session = _sessionCtrl.currentSession;
    if (session == null) return;

    final updated = [..._messages];
    final lastIdx = updated.length - 1;
    if (lastIdx >= 0 && updated[lastIdx].role == MessageRole.assistant) {
      final last = updated[lastIdx];
      updated[lastIdx] = last.copyWith(
        toolCalls: calls,
        streaming: false,
      );
    }
    _messages = updated;
    notifyListeners();
  }

  /// 把工具执行结果作为 tool 消息追加到消息列表
  void _appendToolResultMessage(ToolResult result) {
    final session = _sessionCtrl.currentSession;
    if (session == null) return;
    _messages = [
      ..._messages,
      Message.tool(
        sessionId: session.id,
        toolCallId: result.toolCallId,
        toolName: result.name,
        content: result.toMessageContent(),
      ),
    ];
    notifyListeners();
  }

  /// 构建系统提示词
  Future<String> _buildSystemPrompt() async {
    final buf = StringBuffer();

    buf.writeln(qp.querySystemPrompt);
    buf.writeln();

    try {
      final wikiRepo = _ref.read(wikiRepositoryProvider);
      final index = await wikiRepo.readIndex();
      if (index.trim().isNotEmpty) {
        buf.writeln('## Wiki 知识库索引');
        buf.writeln();
        buf.writeln(index.trim());
        buf.writeln();
        buf.writeln('> 你可以使用 read_file 工具读取某个页面的完整内容。');
        buf.writeln();
      }
    } catch (e) {
      log.info('⚠️ 构建 Wiki 索引失败: $e');
    }

    buf.writeln(_toolRegistry.toSystemPromptDescription());

    return buf.toString();
  }

  /// 应用单条流式事件到消息列表
  void _applyStreamEvent(LlmStreamEvent event) {
    if (event.error != null) {
      log.info('❌ 流式错误: ${event.error}');
      final updated = [..._messages];
      final lastIdx = updated.length - 1;
      if (lastIdx >= 0) {
        updated[lastIdx] = updated[lastIdx].copyWith(
          content: '${updated[lastIdx].content}\n\n> ${event.error}',
          streaming: false,
        );
      }
      _messages = updated;
      _lastError = event.error;
      notifyListeners();
      onError?.call(event.error!);
      return;
    }
    if (event.delta != null) {
      final delta = event.delta!;
      final updated = [..._messages];
      final lastIdx = updated.length - 1;
      if (lastIdx >= 0) {
        updated[lastIdx] = updated[lastIdx].copyWith(
          content: updated[lastIdx].content + delta,
          streaming: true,
        );
      }
      _messages = updated;
      notifyListeners();
    }
    if (event.reasoning != null) {
      final reasoning = event.reasoning!;
      final updated = [..._messages];
      final lastIdx = updated.length - 1;
      if (lastIdx >= 0) {
        updated[lastIdx] = updated[lastIdx].copyWith(
          reasoning: updated[lastIdx].reasoning + reasoning,
          streaming: true,
        );
      }
      _messages = updated;
      notifyListeners();
    }
    if (event.done) {
      final usage = event.usage ?? const LlmUsage();
      _inputTokensUsed = usage.inputTokens;
      _outputTokensUsed = usage.outputTokens;
      notifyListeners();
    }
  }

  /// 构建发送给 LLM 的上下文
  List<Message> _buildContextMessages() {
    final usable = _messages
        .where((m) =>
            (m.content.isNotEmpty || m.toolCalls.isNotEmpty) && !m.streaming)
        .toList();
    final maxMessages = _settingsCtrl.settings.context.maxMessages;
    final tail = usable.length <= maxMessages
        ? usable
        : usable.sublist(usable.length - maxMessages);
    if (tail.isNotEmpty && tail.last.role == MessageRole.assistant) {
      return tail.sublist(0, tail.length - 1);
    }
    return tail;
  }

  /// 调用 LLM 自动命名会话，失败时回退到前 15 字
  Future<void> _autoNameSession(
      String sessionId, String firstMessage) async {
    final cfg = _settingsCtrl.defaultConfig;
    if (cfg == null) return;
    try {
      final provider = _providerCtrl.resolveProvider(cfg);
      final name = await provider.chatComplete(
        cfg,
        messages: [
          Message.user(sessionId: sessionId, content: firstMessage),
        ],
        systemPrompt: ip.sessionNameSystemPrompt,
      );
      final clean = name
          .replaceAll(RegExp(r'["\n\r]'), '')
          .replaceAll(RegExp(r'^会话名称[:：]\s*'), '')
          .trim();
      if (clean.isNotEmpty && clean.length <= 30) {
        await _sessionCtrl.renameSession(sessionId, clean);
        return;
      }
      throw '命名结果为空或过长';
    } catch (e) {
      debugPrint('自动命名失败：$e');
      final fallback = firstMessage.length > 15
          ? firstMessage.substring(0, 15)
          : firstMessage;
      await _sessionCtrl.renameSession(sessionId, fallback);
    }
  }

  /// 停止当前正在进行的生成
  ///
  /// 修复 C4：将所有 streaming=true 的消息标记为 streaming=false
  void stopGeneration() {
    _streamCancelToken?.complete();
    _isStreaming = false;
    _sending = false; // 修复 C3：释放发送锁

    // 修复 C4：中断时将所有流式消息标记为非流式
    final updated = [..._messages];
    for (var i = 0; i < updated.length; i++) {
      if (updated[i].streaming) {
        updated[i] = updated[i].copyWith(streaming: false);
      }
    }
    _messages = updated;
    notifyListeners();
  }

  /// 清空当前会话的上下文
  void clearContext() {
    _messages = const [];
    _inputTokenEstimate = 0;
    _named = false; // 重置自动命名标志
    notifyListeners();

    final session = _sessionCtrl.currentSession;
    if (session != null) {
      _sessionCtrl.setMessages(const []);
    }
  }

  /// 估算文本的 token 数量并更新 [inputTokenEstimate]
  void estimateTokens(String text) {
    _inputTokenEstimate = TokenCounter.estimateTokens(text);
    notifyListeners();
  }

  /// 清除最近一次错误状态
  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  /// 保存当前消息上下文（v6.4：追加消息到 messages.jsonl）
  ///
  /// 修复 C2：不再使用 JSON 字符串，改为追加到 JSONL 文件
  Future<void> _saveContext(String sessionId) async {
    // 只保存非流式消息（排除正在生成的最后一条）
    final nonStreaming = _messages.where((m) => !m.streaming).toList();

    // 追加到会话存储（高性能）
    await _sessionCtrl.appendMessages(sessionId, nonStreaming);

    // 同步到 SessionController 的 currentMessages
    _sessionCtrl.setMessages(nonStreaming);

    // 检查是否需要压缩（异步执行，不阻塞主流程）
    final session = _sessionCtrl.currentSession;
    if (session != null && session.id == sessionId) {
      unawaited(_compressor.compressIfNeeded(
        session: session,
        messages: nonStreaming,
      ));
    }
  }
}

/// Riverpod Provider：暴露 [ChatController]
final chatControllerProvider = ChangeNotifierProvider<ChatController>(
  (ref) => ChatController(ref),
);
