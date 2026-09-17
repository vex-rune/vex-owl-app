import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../../core/core.dart';
import '../../core/util/talker_service.dart';
import '../../core/prompt/ingest_prompt.dart' as ip;
import '../../core/prompt/query_prompt.dart' as qp;
import '../../data/llm/llm.dart';
import '../service/context_compressor.dart';
import '../service/file_tools.dart';
import '../service/session_file_service.dart';
import '../service/tool_registry.dart';

import 'session_controller.dart';
import 'settings_controller.dart';
import 'provider_controller.dart';

/// 聊天逻辑控制器（基于 ChangeNotifier + Riverpod）
///
/// 负责消息发送、真实 LLM 流式响应接收、上下文管理等核心聊天流程。
/// 通过构造函数注入 [Ref]，再从 `app_providers` 中获取仓库与 [SessionController]。
class ChatController extends ChangeNotifier {
  ChatController(this._ref) {
    _sessionCtrl = _ref.read(sessionControllerProvider);
    _sessionCtrl.addListener(_onSessionChanged);
    _settingsCtrl = _ref.read(settingsControllerProvider);
    _settingsCtrl.addListener(_onSettingsChanged);
    _providerCtrl = _ref.read(providerControllerProvider);

    // 初始化文件工具集（白名单 + 原子写入）
    final wiki = _ref.read(wikiRepositoryProvider);
    final fileTools = FileTools(wiki);
    _toolRegistry = ToolRegistry(fileTools: fileTools);
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
  ///
  /// 通过 WikiRepository 的 [IWikiRepository.getRootPath] 获取（接口已扩展）。
  Future<void> _initToolRootPath(FileTools fileTools, wiki) async {
    try {
      final root = await wiki.getRootPath();
      if (root.isNotEmpty) {
        fileTools.setRootPath(root);
        TalkerService.instance.chatInfo(
          '🔧 FileTools 根目录已设置：$root',
        );
      }
    } catch (e) {
      TalkerService.instance.chatInfo('⚠️ FileTools 根目录初始化失败：$e');
      // 兜底：不设置根路径，工具调用会失败但不影响普通对话
    }
  }

  // ── 内部可变状态 ──

  /// 当前消息所属的会话 ID（用于判断会话是否真正切换）
  String? _currentSessionId;

  List<Message> _messages = const [];
  bool _isStreaming = false;
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
  ///
  /// 只有会话 ID 改变时才清空消息列表，并从数据库加载该会话的历史消息。
  /// 同一会话的重命名/归档等操作不会清空消息。
  void _onSessionChanged() {
    final newId = _sessionCtrl.currentSession?.id;
    if (newId != _currentSessionId) {
      _currentSessionId = newId;
      _inputTokenEstimate = 0;
      // 异步加载该会话的历史消息
      if (newId != null) {
        _loadMessages(newId);
      } else {
        _messages = const [];
        notifyListeners();
      }
    }
  }

  /// 从内存仓库加载指定会话的历史消息
  Future<void> _loadMessages(String sessionId) async {
    try {
      Session? session;
      for (final s in _sessionCtrl.sessions) {
        if (s.id == sessionId) {
          session = s;
          break;
        }
      }
      if (session == null || session.context.trim().isEmpty) {
        _messages = const [];
      } else {
        _messages = Message.listFromJson(session.context);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('加载历史消息失败：$e');
      _messages = const [];
      notifyListeners();
    }
  }

  /// 当设置（默认配置等）变更时通知 UI 刷新徽标
  void _onSettingsChanged() {
    notifyListeners();
  }

  /// 发送用户消息并获取 AI 回复
  Future<void> sendMessage(String content) async {
    if (content.trim().isEmpty) return;

    final session = _sessionCtrl.currentSession;
    if (session == null) {
      _lastError = '请先创建或选择一个会话';
      notifyListeners();
      onError?.call(_lastError!);
      return;
    }

    final config = _settingsCtrl.defaultConfig;
    if (config == null) {
      _lastError = '请先在设置中添加并启用一个 API 配置';
      TalkerService.instance.chatInfo('❌ 无默认配置，消息未发送');
      notifyListeners();
      onError?.call(_lastError!);
      return;
    }

    // 1. 清理可能残留的流式占位消息（上次调用被中断时）
    if (_messages.isNotEmpty && _messages.last.streaming) {
      _messages = _messages.sublist(0, _messages.length - 1);
    }

    // 2. Token 阈值告警（非阻塞）
    final tokens = TokenCounter.estimateTokens(content);
    if (tokens > _settingsCtrl.chatTokenThreshold) {
      TalkerService.instance.chatInfo('⚠️ Token 超阈值 $tokens > ${_settingsCtrl.chatTokenThreshold}');
      onWarning?.call(
          '本条消息约 $tokens tokens，超过阈值 ${_settingsCtrl.chatTokenThreshold}');
    }
    _inputTokenEstimate = tokens;

    // 3. 添加用户消息
    _currentSessionId = session.id;
    final userMessage = Message.user(
      sessionId: session.id,
      content: content.trim(),
    );
    _messages = [..._messages, userMessage];
    TalkerService.instance.chatInfo('📤 用户发送: "${content.trim().substring(0, content.trim().length > 30 ? 30 : content.trim().length)}${content.trim().length > 30 ? '...' : ''}"');
    notifyListeners();

    // 3. 首条消息触发 LLM 自动命名（fire-and-forget，不阻塞流式响应）
    if (_messages.length == 1) {
      TalkerService.instance.chat('🗓️ 首条消息，触发自动命名');
      unawaited(_autoNameSession(session.id, content.trim()));
    }

    // 4. 创建助手消息占位（用于流式填充）
    final assistantMessage = Message.assistant(
      sessionId: session.id,
      content: '',
    ).copyWith(streaming: true);
    _messages = [..._messages, assistantMessage];
    _isStreaming = true;
    _streamCancelToken = Completer<void>();
    notifyListeners();

    // 5. 解析 Provider 并启动流式调用（带工具调用循环）
    final provider = _providerCtrl.resolveProvider(config);
    final tools = _toolRegistry.listDefinitions();

    try {
      // 工具调用循环：最多 _maxToolRounds 轮
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

        // 如果本轮没有工具调用 → 结束循环
        if (toolCallsThisRound.isEmpty) break;

        TalkerService.instance.chat(
          '🔧 第 ${round + 1} 轮工具调用：${toolCallsThisRound.map((c) => c.name).join(', ')}',
        );

        // 把工具调用记录为「工具卡片」消息
        _appendToolCallMessages(toolCallsThisRound);

        // 顺序执行工具（并行有依赖风险，简单场景串行即可）
        for (final call in toolCallsThisRound) {
          final result = await _toolRegistry.execute(call);
          _appendToolResultMessage(result);
        }

        // 准备下一轮：创建新的助手占位
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
      // 关闭流式占位标志
      final updated = [..._messages];
      final lastIdx = updated.length - 1;
      if (lastIdx >= 0) {
        final finalContent = updated[lastIdx].content;
        updated[lastIdx] = updated[lastIdx].copyWith(streaming: false);
        TalkerService.instance.chatInfo('✅ 流式完成，回复 "${finalContent.length > 40 ? '${finalContent.substring(0, 40)}...' : finalContent}"');
      }
      _messages = updated;
      notifyListeners();
      // 6. 保存上下文到会话
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
          // 不应用事件（交给循环外统一处理），但要消费
          continue;
        }
        _applyStreamEvent(event);
      }
    } catch (e) {
      _applyStreamEvent(LlmStreamEvent.error('调用失败：$e'));
    }
    return toolCalls;
  }

  /// 在消息列表中追加一条「工具调用卡片」消息（仅记录元数据，用于 UI 显示）
  /// 旧实现：单独插入 assistant 消息。但 OpenAI 协议要求 assistant 与 tool 消息配对，
  /// 因此改为就地更新最后一条 assistant 占位（见 [_appendToolCallMessages] 重载）。
  /// 保留此函数仅为 API 占位（已弃用）。
  @Deprecated('已合并到 _appendToolCallMessages 的就地更新逻辑')
  void _appendToolCallMessagesLegacy(List<LlmToolCall> calls) {
    _appendToolCallMessages(calls);
  }

  /// 把工具调用绑定到最后一条 assistant 占位消息（替换文本，携带 toolCalls）
  ///
  /// 关键：必须就地修改同一 Message 对象，确保下一轮 LLM 调用时该消息
  /// 携带 `tool_calls` 字段（OpenAI 协议要求 assistant 消息带 tool_calls 时，
  /// 必须紧跟 role: tool 消息带相同 tool_call_id）。
  void _appendToolCallMessages(List<LlmToolCall> calls) {
    if (calls.isEmpty) return;
    final session = _sessionCtrl.currentSession;
    if (session == null) return;

    // 把最后一条 assistant 消息标记为「携带 toolCalls」，content 保持为空。
    // 工具调用摘要由 UI 层根据 toolCalls 字段折叠渲染，不再拼进 content。
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
  ///
  /// 注意：tool 消息必须紧跟在携带 toolCalls 的 assistant 消息之后，
  /// 且 tool_call_id 必须与上一条 assistant 消息中的 tool_call.id 对应。
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
  ///
  /// 组合：人格 + Wiki 索引 + 可用工具描述
  Future<String> _buildSystemPrompt() async {
    final buf = StringBuffer();

    // 1. 人格提示词
    buf.writeln(qp.querySystemPrompt);
    buf.writeln();

    // 2. Wiki 索引（让 LLM 看到知识库的整体结构）
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
    } catch (_) {
      // 索引读取失败不阻塞
    }

    // 3. 工具描述（不支持原生 function calling 的 Provider 会靠这段文本理解）
    buf.writeln(_toolRegistry.toSystemPromptDescription());

    return buf.toString();
  }

  /// 应用单条流式事件到消息列表
  void _applyStreamEvent(LlmStreamEvent event) {
    if (event.error != null) {
      TalkerService.instance.chatInfo('❌ 流式错误: ${event.error}');
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

  /// 构建发送给 LLM 的上下文：从 [_messages] 中按配置的 maxMessages 截取尾部；
  /// 若最后一条是助手（占位符），则剔除以避免重复发送。
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
      // 回退到截取前 15 字
      final fallback = firstMessage.length > 15
          ? firstMessage.substring(0, 15)
          : firstMessage;
      await _sessionCtrl.renameSession(sessionId, fallback);
    }
  }

  /// 停止当前正在进行的生成
  void stopGeneration() {
    _streamCancelToken?.complete();
    _isStreaming = false;
    notifyListeners();
  }

  /// 清空当前会话的上下文
  void clearContext() {
    _messages = const [];
    _inputTokenEstimate = 0;
    notifyListeners();

    final session = _sessionCtrl.currentSession;
    if (session != null) {
      _sessionCtrl.updateSessionContext(session.id, '');
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

  /// 保存当前消息上下文（JSON 格式）+ 按需触发压缩
  ///
  /// 流程：
  /// 1. 截取非流式消息尾部（按配置的 maxMessages）
  /// 2. 检测是否需要压缩（超限 + 策略 != nolimit）
  /// 3. 若需压缩 → 异步触发 ContextCompressor（fire-and-forget）
  /// 4. 保存截断后的消息到内存仓库
  Future<void> _saveContext(String sessionId) async {
    final nonStreaming = _messages.where((m) => !m.streaming).toList();
    final maxMessages = _settingsCtrl.settings.context.maxMessages;
    final tail = nonStreaming.length > maxMessages
        ? nonStreaming.sublist(nonStreaming.length - maxMessages)
        : nonStreaming;
    final jsonStr = jsonEncode(tail.map((m) => m.toJson()).toList());
    await _sessionCtrl.updateSessionContext(sessionId, jsonStr);

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
