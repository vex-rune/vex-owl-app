import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/controller/chat_controller.dart';
import '../../application/controller/session_controller.dart';
import '../../application/controller/settings_controller.dart';
import '../../core/model/message.dart';
import '../../design_system/design_system.dart';
import '../widgets/widgets.dart';

/// 对话页 Body 内容
///
/// 不包含 Scaffold/AppBar，由 HomePage Shell 统一管理。
/// 使用 Riverpod ChangeNotifierProvider 订阅 [ChatController] 与 [SessionController]。
class ChatBody extends ConsumerStatefulWidget {
  const ChatBody({super.key});

  @override
  ConsumerState<ChatBody> createState() => _ChatBodyState();
}

class _ChatBodyState extends ConsumerState<ChatBody>
    with TickerProviderStateMixin {
  final _scrollController = ScrollController();

  // ── 欢迎页动画 ──
  late final AnimationController _glowController;
  late final AnimationController _particleController;
  late final AnimationController _typewriterController;
  String _displayedSubtitle = '';
  bool _typewriterDone = false;

  static const _subtitleText = '基于 LLM-Wiki 的持久化知识助手';

  @override
  void initState() {
    super.initState();
    // 呼吸光圈动画（2秒循环）
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    // 粒子浮动动画（6秒循环）
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
    // 打字机动画（逐字显示，每字 80ms）
    _typewriterController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _subtitleText.length * 80),
    )..addListener(() {
        final idx =
            (_typewriterController.value * _subtitleText.length).floor();
        if (idx <= _subtitleText.length) {
          setState(() {
            _displayedSubtitle = _subtitleText.substring(0, idx);
            _typewriterDone = idx >= _subtitleText.length;
          });
        }
      })..forward();

    // 订阅 ChatController 的回调用于 SnackBar 提示
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final chatCtrl = ref.read(chatControllerProvider);
      final c = AppSemanticColors.of(context);
      chatCtrl.onWarning = (msg) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: c.warning,
            duration: const Duration(seconds: 3),
          ),
        );
      };
      chatCtrl.onError = (msg) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: c.error,
            duration: const Duration(seconds: 3),
          ),
        );
      };
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _glowController.dispose();
    _particleController.dispose();
    _typewriterController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatCtrl = ref.watch(chatControllerProvider);
    final messages = chatCtrl.messages;
    final isStreaming = chatCtrl.isStreaming;

    return Column(
      children: [
        _buildNoConfigBanner(),
        Expanded(
          child: messages.isEmpty
              ? _buildWelcomeView(context)
              : () {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _scrollToBottom();
                  });
                  return _buildMessageList(context, messages, isStreaming);
                }(),
        ),
        ChatInputBar(
          onSend: (text) {
            chatCtrl.sendMessage(text);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scrollToBottom();
            });
          },
          isStreaming: isStreaming,
          onStop: () => chatCtrl.stopGeneration(),
          tokenCount: messages.isNotEmpty ? chatCtrl.inputTokenEstimate : null,
          providerName: chatCtrl.activeProviderName,
          modelName: chatCtrl.activeModelName,
          onAttach: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('文件上传功能即将上线')),
            );
          },
        ),
      ],
    );
  }

  /// 未配置默认 API 时显示顶部告警条，引导用户进入设置
  Widget _buildNoConfigBanner() {
    final c = AppSemanticColors.of(context);
    final hasConfig =
        ref.watch(settingsControllerProvider).defaultConfig != null;
    if (hasConfig) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.warning.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: c.warning, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '尚未配置 AI 模型，请先在设置中添加并启用一个 API 配置',
              style: AppTypography.bodyMedium.copyWith(color: c.textPrimary),
            ),
          ),
          TextButton(
            onPressed: () => context.go('/settings'),
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeView(BuildContext context) {
    final c = AppSemanticColors.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge([
        _glowController,
        _particleController,
        _typewriterController,
      ]),
      builder: (context, _) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // ── 浮动粒子背景 ──
            ..._buildParticles(c),
            // ── 主内容 ──
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 呼吸光圈 + Logo
                _buildGlowingLogo(c),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  '智鸮 Owl',
                  style: AppTypography.titleLarge.copyWith(
                    fontSize: 24,
                    color: c.textPrimary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                // 打字机副标题
                Text(
                  _displayedSubtitle,
                  style: AppTypography.bodyMedium
                      .copyWith(color: c.textTertiary),
                ),
                if (!_typewriterDone)
                  Container(
                    width: 2,
                    height: 14,
                    margin: const EdgeInsets.only(left: 2),
                    color: c.primary.withValues(alpha: 0.8),
                  ),
                const SizedBox(height: AppSpacing.xxl),
                // 快捷操作按钮
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildQuickAction(
                      c,
                      icon: Icons.chat_bubble_outline,
                      label: '新对话',
                      onTap: () async {
                        await ref
                            .read(sessionControllerProvider)
                            .createSession('新对话');
                      },
                    ),
                    const SizedBox(width: AppSpacing.base),
                    _buildQuickAction(
                      c,
                      icon: Icons.upload_file_outlined,
                      label: '导入文档',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('导入文档功能即将上线')),
                        );
                      },
                    ),
                    const SizedBox(width: AppSpacing.base),
                    _buildQuickAction(
                      c,
                      icon: Icons.auto_awesome_outlined,
                      label: '知识库',
                      onTap: () {
                        GoRouter.of(context).go('/wiki');
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// 呼吸光圈 + Logo
  Widget _buildGlowingLogo(AppSemanticColors c) {
    final glowValue = _glowController.value;
    final glowAlpha = 0.08 + glowValue * 0.12; // 0.08 ~ 0.20
    final ringAlpha = 0.2 + glowValue * 0.3; // 0.2 ~ 0.5
    final ringScale = 1.0 + glowValue * 0.05; // 1.0 ~ 1.05

    return Transform.scale(
      scale: ringScale,
      child: Container(
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              c.primary.withValues(alpha: glowAlpha),
              c.primary.withValues(alpha: 0.0),
            ],
          ),
        ),
        child: Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.surface,
              border: Border.all(
                color: c.primary.withValues(alpha: ringAlpha),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: c.primary.withValues(alpha: glowAlpha),
                  blurRadius: 20 + glowValue * 10,
                  spreadRadius: 2 + glowValue * 3,
                ),
              ],
            ),
            child: Icon(
              Icons.psychology_outlined,
              size: 32,
              color: c.primary,
            ),
          ),
        ),
      ),
    );
  }

  /// 浮动粒子（8 个半透明圆点）
  List<Widget> _buildParticles(AppSemanticColors c) {
    final t = _particleController.value;
    final particles = <_ParticleData>[
      _ParticleData(0.15, 0.2, 3.0, 0.0),
      _ParticleData(0.85, 0.15, 2.5, 0.3),
      _ParticleData(0.3, 0.75, 2.0, 0.6),
      _ParticleData(0.7, 0.8, 3.5, 0.15),
      _ParticleData(0.5, 0.1, 2.0, 0.45),
      _ParticleData(0.2, 0.5, 2.8, 0.75),
      _ParticleData(0.8, 0.45, 2.2, 0.9),
      _ParticleData(0.45, 0.65, 3.0, 0.55),
    ];
    return particles.map((p) {
      final phase = (t + p.phase) % 1.0;
      final y = p.baseY - phase * 0.3; // 向上浮动
      final alpha = (0.15 + (p.baseY - y).abs() * 0.3).clamp(0.0, 0.35);
      return Positioned(
        left: MediaQuery.of(context).size.width * p.baseX,
        top: MediaQuery.of(context).size.height * y,
        child: Container(
          width: p.size,
          height: p.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.primary.withValues(alpha: alpha),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildQuickAction(
    AppSemanticColors c, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        splashColor: c.primary.withValues(alpha: 0.08),
        highlightColor: c.primary.withValues(alpha: 0.05),
        child: Container(
          width: 96,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: c.border, width: 0.5),
          ),
          child: Column(
            children: [
              Icon(icon, size: 22, color: c.primary),
              const SizedBox(height: AppSpacing.sm),
              Text(
                label,
                style: AppTypography.bodySmall
                    .copyWith(color: c.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageList(
    BuildContext context,
    List<Message> messages,
    bool isStreaming,
  ) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(
        top: AppSpacing.base,
        bottom: AppSpacing.base,
      ),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[index];
        final isUser = msg.role == MessageRole.user;
        return ChatBubble(
          role: isUser ? ChatBubbleRole.user : ChatBubbleRole.assistant,
          content: msg.content,
          reasoning: msg.reasoning,
          toolCalls: msg.toolCalls,
          isStreaming: index == messages.length - 1 && isStreaming && !isUser,
          onWikiRefTap: (ref) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('打开 Wiki: $ref')),
            );
          },
          onLongPress: () => _showMessageContextMenu(msg),
        );
      },
    );
  }

  void _showMessageContextMenu(Message msg) {
    final isUser = msg.role == MessageRole.user;
    final c = AppSemanticColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.copy, color: c.textSecondary),
              title: const Text('复制消息'),
              onTap: () => Navigator.pop(context),
            ),
            if (!isUser)
              ListTile(
                leading: Icon(Icons.refresh, color: c.textSecondary),
                title: const Text('重新生成回答'),
                onTap: () => Navigator.pop(context),
              ),
            ListTile(
              leading: Icon(Icons.search, color: c.textSecondary),
              title: const Text('在 Wiki 中搜索'),
              onTap: () => Navigator.pop(context),
            ),
            if (!isUser)
              ListTile(
                leading:
                    Icon(Icons.bookmark_add_outlined, color: c.textSecondary),
                title: const Text('添加到 Wiki'),
                onTap: () => Navigator.pop(context),
              ),
          ],
        ),
      ),
    );
  }
}

/// 粒子数据（位置 + 大小 + 相位偏移）
class _ParticleData {
  const _ParticleData(this.baseX, this.baseY, this.size, this.phase);
  final double baseX;
  final double baseY;
  final double size;
  final double phase;
}