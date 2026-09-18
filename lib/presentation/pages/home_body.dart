import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/controller/chat_controller.dart';
import '../../application/controller/session_controller.dart';
import '../../application/controller/settings_controller.dart';
import '../../core/model/api_config.dart';
import '../../core/model/message.dart';
import '../../core/model/session.dart';
import '../../design_system/design_system.dart';
import '../widgets/widgets.dart';

/// 唯一页面：始终是 Chat 形态
///
/// - 没有消息 → 消息流显示一个「空态」widget（招呼卡 + 推荐）
/// - 有消息 → 正常聊天流
///
/// 不再有「Home 形态」。AppBar 永远存在；首次进入若 currentSession 为空，
/// 会自动创建一个新会话占位，避免空白。
class HomeChatBody extends ConsumerStatefulWidget {
  const HomeChatBody({super.key});
  @override
  ConsumerState<HomeChatBody> createState() => _HomeChatBodyState();
}

class _HomeChatBodyState extends ConsumerState<HomeChatBody> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroller = ScrollController();
  bool _composing = false;
  bool _autoCreated = false;

  @override
  void initState() {
    super.initState();
    _composer.addListener(() {
      final v = _composer.text.trim().isNotEmpty;
      if (v != _composing) setState(() => _composing = v);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final chatCtrl = ref.read(chatControllerProvider);
      final c = AppSemanticColors.of(context);
      chatCtrl.onWarning = (m) => messenger.showSnackBar(
            SnackBar(
              content: Text(m),
              backgroundColor: c.warning,
              duration: const Duration(seconds: 3),
            ),
          );
      chatCtrl.onError = (m) => messenger.showSnackBar(
            SnackBar(
              content: Text(m),
              backgroundColor: c.error,
              duration: const Duration(seconds: 3),
            ),
          );

      // 若启动时没有会话，自动创建一个（仅一次）
      final sessionCtrl = ref.read(sessionControllerProvider);
      if (sessionCtrl.currentSession == null && !_autoCreated) {
        _autoCreated = true;
        sessionCtrl.createSession('新对话');
      }
    });
  }

  @override
  void dispose() {
    _composer.dispose();
    _scroller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    final chatCtrl = ref.watch(chatControllerProvider);
    final current = ref.watch(sessionControllerProvider).currentSession;
    final isStreaming = chatCtrl.isStreaming;

    return SafeArea(
      child: Column(
        children: [
          _ChatTopBar(
            session: current,
            onClear: _clearContext,
            onMore: _showMoreMenu,
            onNewSession: _createNewSession,
          ),
          const _NoConfigBanner(),
          Expanded(
            child: chatCtrl.messages.isEmpty
                ? const _EmptyState()
                : _MessageList(scroller: _scroller, streaming: isStreaming),
          ),
          _Composer(
            controller: _composer,
            onSend: _sendCurrent,
            onAttach: _onAttach,
            onPickModel: _showModelPicker,
            showTokenCount: !isStreaming && chatCtrl.messages.isNotEmpty,
            tokenCount: chatCtrl.inputTokenEstimate,
            modelLabel: chatCtrl.activeModelName ?? '请配置模型',
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────
  //  行为
  // ────────────────────────────────────────────

  void _fillComposer(String text) {
    _composer.text = text;
    _composer.selection =
        TextSelection.collapsed(offset: _composer.text.length);
  }

  Future<void> _sendCurrent() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;

    final sessionCtrl = ref.read(sessionControllerProvider);
    final chatCtrl = ref.read(chatControllerProvider);

    Session? target = sessionCtrl.currentSession;
    if (target == null) {
      target = await sessionCtrl.createSession('新对话');
      if (target == null || !mounted) return;
    }

    _composer.clear();

    // 首条消息自动命名
    final isFresh = target.name == '新对话' || target.name.trim().isEmpty;
    if (isFresh) {
      sessionCtrl.autoNameSession(target.id, text);
    }

    chatCtrl.sendMessage(text);
  }

  Future<void> _createNewSession() async {
    final s = await ref.read(sessionControllerProvider).createSession('新对话');
    if (s != null) {
      ref.read(chatControllerProvider).clearContext();
      _composer.clear();
    }
  }

  void _clearContext() {
    ref.read(chatControllerProvider).clearContext();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('上下文已清空')),
    );
  }

  void _onAttach() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('文件上传功能即将上线')),
    );
  }

  // ────────────────────────────────────────────
  //  Bottom sheets
  // ────────────────────────────────────────────

  void _showModelPicker() {
    _showModelMenu(context, ref,
        onPicked: (displayName) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已切换到 $displayName')),
      );
    });
  }

  void _showMoreMenu() {
    final c = AppSemanticColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  Icon(Icons.bookmark_add_outlined, color: c.textSecondary),
              title: const Text('存入 Wiki'),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('记忆入库功能即将上线')),
                );
              },
            ),
            ListTile(
              leading:
                  Icon(Icons.delete_sweep_outlined, color: c.textSecondary),
              title: const Text('清空上下文'),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _clearContext();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════
//  顶部 AppBar
// ════════════════════════════════════════════════════════

class _ChatTopBar extends ConsumerWidget {
  const _ChatTopBar({
    required this.session,
    required this.onClear,
    required this.onMore,
    required this.onNewSession,
  });

  final Session? session;
  final VoidCallback onClear;
  final VoidCallback onMore;
  final VoidCallback onNewSession;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AppSemanticColors.of(context);
    final model = ref.watch(chatControllerProvider).activeModelName ?? '请配置模型';
    final title = session?.name ?? '新对话';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      height: 56,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.menu, size: 22),
            color: c.textPrimary,
            onPressed: () => Scaffold.of(context).openDrawer(),
            tooltip: '菜单',
          ),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_comment_rounded, size: 22),
            color: c.textSecondary,
            onPressed: onNewSession,
            tooltip: '新对话',
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz, size: 22),
            color: c.textSecondary,
            onPressed: onMore,
            tooltip: '更多',
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _ModelChip extends StatelessWidget {
  const _ModelChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: c.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 11, color: c.primary),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: c.primary,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.keyboard_arrow_down, size: 12, color: c.primary),
          ],
        ),
      ),
    );
  }
}

/// 弹出模型选择菜单（顶层 helper）
///
/// v6.2 重写：展示所有 enabled Agent，按 Provider 分组。点击某个 Agent 会
/// 把 `defaultConfig` 切到那个 Agent（不仅切 modelName，还会切 provider）。
void _showModelMenu(
  BuildContext context,
  WidgetRef ref, {
  required void Function(String displayName) onPicked,
}) {
  final settingsCtrl = ref.read(settingsControllerProvider);
  final def = settingsCtrl.defaultConfig;
  final c = AppSemanticColors.of(context);
  if (def == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('请先在设置中启用一个 Agent')),
    );
    return;
  }
  // 拉取所有 enabled Agent 并按 Provider 分组
  final enabled = settingsCtrl.agents.where((a) => a.enabled).toList();
  if (enabled.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('当前没有可用的 Agent')),
    );
    return;
  }
  final byProvider = <String, List<ApiConfig>>{};
  for (final a in enabled) {
    byProvider.putIfAbsent(a.providerId, () => []).add(a);
  }

  showModalBottomSheet(
    context: context,
    backgroundColor: c.surface,
    builder: (sheetCtx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                '选择 Agent',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                '点击切换默认 Agent，跨 Provider 也支持',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            for (final entry in byProvider.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Text(
                  settingsCtrl.providerController
                          .providerById(entry.key)
                          ?.displayName ??
                      entry.key,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: c.primary,
                  ),
                ),
              ),
              for (final a in entry.value)
                ListTile(
                  leading: Icon(
                    Icons.auto_awesome_outlined,
                    color: a.providerId == def.providerId &&
                            a.modelName == def.modelName
                        ? c.primary
                        : c.textSecondary,
                    size: 20,
                  ),
                  title: Text(
                    a.modelName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: a.providerId == def.providerId &&
                              a.modelName == def.modelName
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                  subtitle: Text(
                    a.apiKey.isEmpty ? '未配置 API Key' : 'Key 已配置',
                    style: TextStyle(fontSize: 11, color: c.textTertiary),
                  ),
                  trailing: a.providerId == def.providerId &&
                          a.modelName == def.modelName
                      ? Icon(Icons.check, color: c.primary, size: 18)
                      : null,
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    if (a.providerId == def.providerId &&
                        a.modelName == def.modelName) {
                      return;
                    }
                    // 切换默认 Agent 到这个；同时保证其他默认标记被清掉
                    settingsCtrl.setDefaultAgent(a.providerId, a.modelName);
                    onPicked(a.modelName);
                  },
                ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

// ════════════════════════════════════════════════════════
//  Banner
// ════════════════════════════════════════════════════════

class _NoConfigBanner extends ConsumerWidget {
  const _NoConfigBanner();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AppSemanticColors.of(context);
    final hasConfig =
        ref.watch(settingsControllerProvider).defaultConfig != null;
    if (hasConfig) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.warning.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: c.warning, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '尚未配置 AI 模型，请先在设置中添加并启用一个 API 配置',
              style: TextStyle(fontSize: 13, color: c.textPrimary),
            ),
          ),
          TextButton(
            onPressed: () => Scaffold.of(context).openDrawer(),
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════
//  消息流（核心）
// ════════════════════════════════════════════════════════

class _MessageList extends ConsumerWidget {
  const _MessageList({required this.scroller, required this.streaming});
  final ScrollController scroller;
  final bool streaming;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(chatControllerProvider).messages;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scroller.hasClients) return;
      scroller.animateTo(
        scroller.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });

    // 将 role=tool 的消息分组到前一个 assistant 消息
    final displayItems = _groupMessages(messages);

    return ListView.builder(
      controller: scroller,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: displayItems.length,
      itemBuilder: (context, i) {
        final item = displayItems[i];
        final msg = item.msg;
        final isUser = msg.role == MessageRole.user;
        return ChatBubble(
          role: isUser ? ChatBubbleRole.user : ChatBubbleRole.assistant,
          content: msg.content,
          reasoning: msg.reasoning,
          toolCalls: msg.toolCalls,
          toolResults: item.toolResults,
          isStreaming: i == displayItems.length - 1 &&
              streaming &&
              !isUser &&
              !item.isToolGroup,
          onWikiRefTap: (ref) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('打开 Wiki: $ref')),
            );
          },
          onLongPress: () => _showMsgMenu(context, msg, isUser),
        );
      },
    );
  }

  /// 将 tool 消息分组到其对应的 assistant 消息。
  ///
  /// 返回的消息列表中：
  /// - assistant 消息的 `toolResults` 会携带后续的 tool 消息
  /// - 独立的 tool 消息（无前导 assistant toolCalls）会被过滤掉
  /// - 空 content 的 assistant 消息（工具循环中转）会被跳过
  static List<_MessageDisplayItem> _groupMessages(List<Message> messages) {
    final items = <_MessageDisplayItem>[];
    var i = 0;
    while (i < messages.length) {
      final msg = messages[i];
      if (msg.role == MessageRole.tool) {
        // 跳过无归属的 tool 消息
        i++;
        continue;
      }
      if (msg.role == MessageRole.assistant && msg.toolCalls.isNotEmpty) {
        // 收集后续 tool 消息
        final toolResults = <Message>[];
        var j = i + 1;
        while (j < messages.length && messages[j].role == MessageRole.tool) {
          toolResults.add(messages[j]);
          j++;
        }
        // 跳过工具循环中的空 assistant 消息（tool 后面的空回复）
        if (j < messages.length &&
            messages[j].role == MessageRole.assistant &&
            messages[j].content.trim().isEmpty &&
            j + 1 < messages.length &&
            messages[j + 1].role == MessageRole.tool) {
          j++; // 跳过空 assistant
        }
        items.add(_MessageDisplayItem(
          msg: msg,
          toolResults: toolResults,
          isToolGroup: true,
        ));
        i = j;
      } else if (msg.role == MessageRole.assistant &&
          msg.content.trim().isEmpty &&
          !msg.streaming) {
        // 跳过无内容的 assistant 消息
        i++;
      } else {
        items.add(_MessageDisplayItem(msg: msg));
        i++;
      }
    }
    return items;
  }
}

class _MessageDisplayItem {
  const _MessageDisplayItem({
    required this.msg,
    this.toolResults = const [],
    this.isToolGroup = false,
  });
  final Message msg;
  final List<Message> toolResults;
  final bool isToolGroup;
}

void _showMsgMenu(BuildContext context, Message msg, bool isUser) {
  final c = AppSemanticColors.of(context);
  showModalBottomSheet(
    context: context,
    backgroundColor: c.surface,
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(Icons.copy, color: c.textSecondary),
            title: const Text('复制消息'),
            onTap: () => Navigator.of(sheetCtx).pop(),
          ),
          if (!isUser)
            ListTile(
              leading: Icon(Icons.refresh, color: c.textSecondary),
              title: const Text('重新生成回答'),
              onTap: () => Navigator.of(sheetCtx).pop(),
            ),
          ListTile(
            leading: Icon(Icons.search, color: c.textSecondary),
            title: const Text('在 Wiki 中搜索'),
            onTap: () => Navigator.of(sheetCtx).pop(),
          ),
          if (!isUser)
            ListTile(
              leading: Icon(Icons.bookmark_add_outlined, color: c.textSecondary),
              title: const Text('添加到 Wiki'),
              onTap: () => Navigator.of(sheetCtx).pop(),
            ),
        ],
      ),
    ),
  );
}

// ════════════════════════════════════════════════════════
//  空态（消息流里显示）
// ════════════════════════════════════════════════════════

class _EmptyState extends ConsumerWidget {
  const _EmptyState();

  static const _recommendations = [
    '生成戴 1% 电量纸袋头像',
    '请用 React 模式帮我构思一个 AI 智能体',
    '上传图片，让角色跳舞视频',
    '请推荐用于 Java 开发的高效工具',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AppSemanticColors.of(context);
    final state = ref.read(_composerFillerProvider.notifier);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.border, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '有什么我能帮你的吗？',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '从下方推荐开始，或直接在底部输入你的问题',
                  style: TextStyle(fontSize: 13, color: c.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '为你推荐',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: c.textTertiary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final r in _recommendations)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RecTile(text: r, onPick: state.fill),
            ),
        ],
      ),
    );
  }
}

class _RecTile extends StatelessWidget {
  const _RecTile({required this.text, required this.onPick});
  final String text;
  final ValueChanged<String> onPick;
  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    return InkWell(
      onTap: () => onPick(text),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border, width: 0.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontSize: 14, color: c.textPrimary),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.auto_awesome, size: 18, color: c.warning),
          ],
        ),
      ),
    );
  }
}

/// 一个小型的 provider，用于把 _EmptyState 的推荐回调传到顶层 _Composer。
///
/// 由于 _EmptyState 是无状态 widget，无法直接回调到顶层 setState；
/// 用这个 provider 桥接：_EmptyState 点击推荐 → 这里填到 composer → 顶层监听并复制到 _composer。
final _composerFillerProvider =
    StateNotifierProvider<_ComposerFiller, String>((ref) {
  return _ComposerFiller();
});

class _ComposerFiller extends StateNotifier<String> {
  _ComposerFiller() : super('');
  void fill(String v) => state = v;
}

// ════════════════════════════════════════════════════════
//  Composer
// ════════════════════════════════════════════════════════

class _Composer extends ConsumerStatefulWidget {
  const _Composer({
    required this.controller,
    required this.onSend,
    required this.onAttach,
    required this.onPickModel,
    required this.showTokenCount,
    required this.tokenCount,
    required this.modelLabel,
  });
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final VoidCallback onPickModel;
  final bool showTokenCount;
  final int tokenCount;
  final String modelLabel;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);

    // 监听桥接信号：_EmptyState 里点击推荐 → 这里写入 controller；
    // controller 的 listener 会触发顶层 _HomeChatBodyState 的 setState，
    // 本 widget 会随之重建，无需手动 setState。
    ref.listen<String>(_composerFillerProvider, (prev, next) {
      if (next.isNotEmpty) {
        widget.controller.text = next;
        widget.controller.selection = TextSelection.collapsed(
          offset: widget.controller.text.length,
        );
      }
    });

    final hasText = widget.controller.text.trim().isNotEmpty;
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: c.background,
        border: Border(top: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _ModelPill(label: widget.modelLabel, onTap: widget.onPickModel),
              const Spacer(),
              if (widget.showTokenCount)
                Text(
                  '≈ ${widget.tokenCount} tokens',
                  style: TextStyle(fontSize: 11, color: c.textTertiary),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 130),
                  decoration: BoxDecoration(
                    color: c.surfaceVariant,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: LayoutBuilder(
                    builder: (ctx, constraints) {
                      return ConstrainedBox(
                        constraints: constraints.copyWith(maxHeight: 130),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: TextField(
                            controller: widget.controller,
                            maxLines: null,
                            minLines: 1,
                            maxLength: 4000,
                            textInputAction: TextInputAction.newline,
                            style: TextStyle(fontSize: 14, color: c.textPrimary),
                            decoration: InputDecoration(
                              hintText: '发消息…',
                              hintStyle: TextStyle(fontSize: 14, color: c.textTertiary),
                              border: InputBorder.none,
                              isCollapsed: true,
                              contentPadding: EdgeInsets.zero,
                              counterText: '',
                            ),
                            onSubmitted: (_) => widget.onSend(),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _SendButton(hasText: hasText, onTap: widget.onSend),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModelPill extends StatelessWidget {
  const _ModelPill({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: c.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_outlined, size: 12, color: c.primary),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: c.primary,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.keyboard_arrow_down, size: 14, color: c.primary),
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.hasText, required this.onTap});
  final bool hasText;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    return InkWell(
      onTap: hasText ? onTap : null,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: hasText ? c.primary : c.surfaceVariant,
          shape: BoxShape.circle,
          border: Border.all(
            color: hasText ? c.primary : c.border,
            width: 0.5,
          ),
        ),
        child: Icon(
          Icons.send_rounded,
          size: 18,
          color: hasText ? c.onPrimary : c.textTertiary,
        ),
      ),
    );
  }
}