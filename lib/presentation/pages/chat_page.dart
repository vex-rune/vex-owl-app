import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/agent/orchestrator.dart';
import '../../application/providers.dart';
import '../../core/model/message.dart';
import '../../core/model/turn.dart';
import '../theme/app_theme.dart';
import '../widgets/assistant_turn_bubble.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/message_bubble.dart';
import '../widgets/typing_indicator.dart';

/// 对话页:核心交互页面。
///
/// **业务职责**:仅 UI 渲染 + 用户交互。所有 Agent 运行编排、消息落库、
/// 多会话并发控制都已下沉到 [AgentOrchestrator],通过 `ref.watch(...)`
/// 拿到状态,`ref.read(orchestratorProvider).send(...)` 触发动作。
class ChatPage extends ConsumerStatefulWidget {
  final String conversationId;
  const ChatPage({super.key, required this.conversationId});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _scrollCtrl = ScrollController();
  String _title = '新对话';
  String? _lastFailedInput;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    // Page dispose 不取消 run —— Orchestrator 是单例,run 状态归它管,
    // 用户下次进 Page 重新 watch runStateProvider 即可拿到最新状态。
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send(String userInput) async {
    // 配置守卫:apiKey/baseUrl 未配置时提示并跳设置页,避免空配置发起请求后
    // 模型静默失败(表现为"发出去没回答")。
    final cfg = await ref.read(currentConfigProvider.future);
    debugPrint('[ChatPage guard] apiKey=${cfg.redactedApiKey} '
        'baseUrl=${cfg.baseUrl} model=${cfg.model} '
        'isConfigured=${cfg.isConfigured}');
    if (!cfg.isConfigured) {
      _showError('请先在设置中配置 API Key 与 Base URL');
      if (!mounted) return;
      context.push('/home/settings');
      return;
    }

    final orchestrator = await ref.read(agentOrchestratorProvider.future);
    final started = await orchestrator.send(
      conversationId: widget.conversationId,
      userInput: userInput,
    );
    if (!started) {
      _showError('上一条消息还没回复完,请稍候');
      return;
    }
    _lastFailedInput = null;
  }

  void _cancel() {
    ref.read(agentOrchestratorProvider.future).then(
          (o) => o.cancel(widget.conversationId),
        );
  }

  Future<void> _retry() async {
    final input = _lastFailedInput;
    if (input == null) return;
    await _send(input);
    await _refreshTitle();
  }

  Future<void> _refreshTitle() async {
    final service = await ref.read(conversationServiceProvider.future);
    final newName = await service.generateTitle(widget.conversationId);
    if (!mounted) return;
    if (newName != _title) {
      setState(() => _title = newName);
    }
  }

  void _showError(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 消息流 watch —— UI 自动随 DB 变更 rebuild。
    final messagesAsync = ref.watch(
      conversationMessagesProvider(widget.conversationId),
    );
    final runStateAsync = ref.watch(
      runStateProvider(widget.conversationId),
    );

    // 每次消息列表更新都滚到底部(流式 + 起名 + 删除等场景都需要)。
    ref.listen<AsyncValue<List<Message>>>(
      conversationMessagesProvider(widget.conversationId),
      (_, next) => _scrollToBottom(),
    );

    final runState = runStateAsync.valueOrNull;
    final status = runState?.status ?? SendStatus.idle;
    final messages = messagesAsync.valueOrNull ?? const <Message>[];

    // 切到 idle 时若标题仍是默认,自动起名。
    if (status == SendStatus.idle &&
        _title == '新对话' &&
        messages.any((m) => m.role == MessageRole.user)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshTitle());
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (status == SendStatus.sending)
            IconButton(
              tooltip: '停止',
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: _cancel,
            ),
          if (status == SendStatus.error)
            IconButton(
              tooltip: '重试',
              icon: const Icon(Icons.refresh),
              onPressed: _retry,
            ),
          IconButton(
            tooltip: '清空对话',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () => _confirmClear(context),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == 'meta') _showMetaSheet(context, messages);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'meta', child: Text('查看元数据')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _renderList(messages, status == SendStatus.sending),
          ),
          if (status == SendStatus.error && runState?.errorMessage != null)
            _ErrorBanner(message: runState!.errorMessage!),
          ChatInputBar(
            onSend: _send,
            enabled: status != SendStatus.sending,
          ),
        ],
      ),
    );
  }

  /// 把扁平消息列表分组为 [User 消息 | AssistantTurn],渲染到 ListView。
  Widget _renderList(List<Message> messages, bool isSending) {
    if (messages.isEmpty && !isSending) return const _ChatEmpty();
    final items = groupTurns(messages);
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(vertical: AppTheme.space3),
      itemCount: items.length + (isSending ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == items.length) return const TypingIndicator();
        final item = items[i];
        if (item is AssistantTurn) {
          return AssistantTurnBubble(turn: item);
        }
        return MessageBubble(message: item as Message);
      },
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空对话'),
        content: const Text('清空后,该对话下的所有消息将被移除。确定继续?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final conv = await ref.read(conversationServiceProvider.future);
    await conv.delete(widget.conversationId);
  }

  void _showMetaSheet(BuildContext context, List<Message> messages) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.space4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('会话元数据', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: AppTheme.space3),
                _MetaRow(label: '会话 ID', value: widget.conversationId),
                const _MetaRow(label: 'Agent', value: 'fast-qa'),
                _MetaRow(
                  label: '当前轮次',
                  value:
                      '${messages.where((m) => m.role == MessageRole.assistant).length}',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space4,
        vertical: AppTheme.space2,
      ),
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
    );
  }
}

class _ChatEmpty extends StatelessWidget {
  const _ChatEmpty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppTheme.space4),
            Text('开启一段对话', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppTheme.space2),
            Text(
              '在下方输入框中输入消息,按发送即可开始',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;
  const _MetaRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.space1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
