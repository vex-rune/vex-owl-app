import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../application/service/thumbnail_generator.dart';

import '../../application/controller/chat_controller.dart';
import '../../application/controller/provider_controller.dart';
import '../../application/controller/session_controller.dart';
import '../../application/controller/settings_controller.dart';
import '../../core/core.dart';
import '../../data/llm/llm.dart';
import '../../design_system/design_system.dart';
import '../router/app_router.dart';
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

  /// 暴露 Composer 的 state key（图片上传后回传到预览区）
  final GlobalKey<_ComposerState> _composerStateKey = GlobalKey<_ComposerState>();

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
                : _MessageList(
                    scroller: _scroller,
                    streaming: isStreaming,
                    onCopyMessage: _copyMessage,
                    onSearchWiki: _searchInWiki,
                    onWikiRefTap: _openWikiRef,
                  ),
          ),
          _Composer(
            key: _composerStateKey,
            controller: _composer,
            onSend: _sendCurrent,
            onAttach: _onAttach,
            onPickModel: _showModelPicker,
            onPickFromCamera: _onPickFromCamera,
            onPickFromGallery: _onPickFromGallery,
            onShowRecents: _onShowRecents,
            onSendWithAttachments: _sendWithAttachments,
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

  /// 发送文本 + 附件（图片）
  Future<void> _sendWithAttachments({
    required String content,
    required List<MessagePart> parts,
  }) async {
    final text = content.trim().isEmpty ? '请分析这些图片' : content.trim();

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

    await chatCtrl.sendMessageWithParts(content: text, parts: parts);
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

  // ════════════════════════════════════════════════════════
  //  文件上传
  // ════════════════════════════════════════════════════════

  /// 选择并上传文件
  Future<void> _onAttach() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'txt', 'md', 'json', 'yaml', 'yml', 'csv', 'log',
          'jpg', 'jpeg', 'png', 'gif', 'webp',
          'pdf', 'doc', 'docx',
          'mp3', 'm4a', 'wav',
          'mp4', 'avi', 'mov', 'mkv',
        ],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final fileName = file.name;
        final extension = fileName.split('.').last.toLowerCase();

        // 文本文件：读取内容到输入框
        if (_isTextFile(extension)) {
          if (file.bytes != null) {
            final content = String.fromCharCodes(file.bytes!);
            _composer.text = content;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已加载: $fileName')),
            );
          }
        }
        // 图片文件：尝试上传到 MiniMax
        else if (_isImageFile(extension)) {
          await _handleImageUpload(file);
        }
        // 其他文件：提示不支持
        else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('暂不支持此格式: .$extension')),
          );
        }
      }
    } catch (e) {
      log.error('选择文件失败: $e', StackTrace.current);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择文件失败: $e')),
      );
    }
  }

  bool _isTextFile(String ext) {
    return ['txt', 'md', 'json', 'yaml', 'yml', 'csv', 'log'].contains(ext);
  }

  bool _isImageFile(String ext) {
    return ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext);
  }

  /// 从相机拍照（暂未实现 camera 能力，复用文件选择）
  Future<void> _onPickFromCamera() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('相机功能暂未集成，请使用"文件"上传图片')),
    );
  }

  /// 从相册选择图片（暂用 file_picker 代替）
  Future<void> _onPickFromGallery() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
      );
      if (picked == null) return;

      // 把 XFile 适配成 PlatformFile 复用 _handleImageUpload
      // image_picker 在 Android 13+ 使用系统 PhotoPicker，
      // 不会产生 cache 副本，从 content URI 流式获取图片
      final platformFile = PlatformFile(
        name: picked.name,
        path: picked.path,
        size: await picked.length(),
      );
      await _handleImageUpload(platformFile);
    } catch (e) {
      log.error('选择图片失败: $e', StackTrace.current);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择图片失败: $e')),
        );
      }
    }
  }

  /// 显示近期上传的项目（暂未实现持久化）
  Future<void> _onShowRecents() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('近期项目功能开发中')),
    );
  }

  /// 把图片从 file_picker 临时目录移动到 app 私有目录
  ///
  /// 已废弃：现在相册图片使用 image_picker，不产生 cache 副本。
  /// 任意文件上传由 file_picker 处理，上传后立即删除 cache 文件。
  @Deprecated('改用 image_picker，不再需要移动文件')
  Future<String?> _moveToPrivateDir({
    required String sourcePath,
    required String fileName,
  }) async {
    return null;
  }

  Future<void> _handleImageUpload(PlatformFile file) async {
    if (file.path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法读取图片路径')),
      );
      return;
    }

    // 检查是否使用 MiniMax
    final settingsCtrl = ref.read(settingsControllerProvider);
    final config = settingsCtrl.defaultConfig;
    if (config == null || config.providerId != 'minimax') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('图片上传仅支持 MiniMax 模型')),
      );
      return;
    }

    // 立刻添加上传中的占位（在预览框显示 loading icon）
    final attId = _composerStateKey.currentState?.addUploadingAttachment(
      localPath: file.path!,
      fileName: file.name,
      providerId: config.providerId,
    );

    if (attId == null) {
      log.error('无法访问 Composer state');
      return;
    }

    try {
      final provider = MinimaxProvider();

      // 1) 把原图从临时目录复制到 app 私有目录（持久化保留）
      final privateOriginalPath =
          await _copyToPrivateDir(file.path!, file.name);
      if (privateOriginalPath == null) {
        _composerStateKey.currentState?.markAttachmentFailed(id: attId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('保存图片失败')),
          );
        }
        return;
      }

      // 2) 上传到 MiniMax
      final fileId = await provider.uploadFile(
        filePath: privateOriginalPath,
        purpose: MiniMaxFilePurpose.videoGenerationInput,
        apiKey: config.apiKey,
      );

      if (fileId == null) {
        _composerStateKey.currentState?.markAttachmentFailed(id: attId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('图片上传失败')),
          );
        }
        return;
      }

      // 3) 生成缩略图（512px JPEG，存到私有目录）
      final thumbPath =
          await ThumbnailGenerator.generate(privateOriginalPath);

      // 4) 上传完成 → 更新预览状态为 ready
      _composerStateKey.currentState?.markAttachmentUploaded(
        id: attId,
        fileId: fileId,
        providerId: config.providerId,
        originalPath: privateOriginalPath,
        thumbnailPath: thumbPath,
      );

      // 5) 删除原临时文件（如果有）
      try {
        final tmp = File(file.path!);
        if (tmp.existsSync() && tmp.path != privateOriginalPath) {
          await tmp.delete();
          log.info('🗑️ 已清理临时文件: ${file.path}');
        }
      } catch (e) {
        log.error('❌ 清理临时文件失败: $e');
      }
    } catch (e) {
      log.error('图片上传失败: $e', StackTrace.current);
      _composerStateKey.currentState?.markAttachmentFailed(id: attId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图片上传失败: $e')),
        );
      }
    }
  }

  /// 把图片从临时目录复制到 app 私有目录
  ///
  /// 不使用 rename 是为了保留原始文件（部分场景下还可能需要访问）
  Future<String?> _copyToPrivateDir(String sourcePath, String fileName) async {
    try {
      final src = File(sourcePath);
      if (!src.existsSync()) {
        log.info('⚠️ 源文件不存在: $sourcePath');
        return null;
      }

      final docsDir = await getApplicationDocumentsDirectory();
      final mediaDir = Directory('${docsDir.path}/media');
      if (!await mediaDir.exists()) {
        await mediaDir.create(recursive: true);
      }

      final ts = DateTime.now().millisecondsSinceEpoch;
      final ext = fileName.contains('.')
          ? fileName.substring(fileName.lastIndexOf('.'))
          : '.jpg';
      final newName = '${ts}_$fileName';
      final destPath = '${mediaDir.path}/$newName';

      await src.copy(destPath);

      final dest = File(destPath);
      if (dest.existsSync()) {
        log.info('✅ 原图已保存到私有目录: $destPath');
        return destPath;
      }
      log.error('❌ 复制后目标不存在: $destPath');
      return null;
    } catch (e, st) {
      log.error('❌ 复制文件失败: $e', st);
      return null;
    }
  }

  // ════════════════════════════════════════════════════════
  // ════════════════════════════════════════════════════════
  //  Wiki 相关
  // ════════════════════════════════════════════════════════

  /// 打开 Wiki 引用
  void _openWikiRef(String ref) {
    goRouter.go('/wiki?ref=$ref');
  }

  /// 在 Wiki 中搜索
  Future<void> _searchInWiki(String query) async {
    if (query.isEmpty) return;
    goRouter.go('/wiki?search=${Uri.encodeComponent(query)}');
  }

  // ════════════════════════════════════════════════════════
  //  消息操作
  // ════════════════════════════════════════════════════════

  /// 复制消息到剪贴板
  Future<void> _copyMessage(String content) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制到剪贴板')),
      );
    }
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
  _MessageList({
    required this.scroller,
    required this.streaming,
    required this.onCopyMessage,
    required this.onSearchWiki,
    required this.onWikiRefTap,
  });
  final ScrollController scroller;
  final bool streaming;
  final void Function(String) onCopyMessage;
  final void Function(String) onSearchWiki;
  final void Function(String) onWikiRefTap;

  // 持有 container 用于在 callback 中读 Provider
  ProviderContainer? _container;

  /// 解析 MiniMax file_id → download_url
  ///
  /// 把 MiniMax API Key 缓存在这里，每次解析都从当前默认 Provider 配置取。
  Future<String?> _resolveMmFile(String fileId) async {
    final container = _container;
    if (container == null) return null;
    try {
      final settingsCtrl = container.read(settingsControllerProvider);
      final config = settingsCtrl.defaultConfig;
      if (config == null) return null;
      final provider = container.read(providerControllerProvider)
          .resolveProvider(config);
      if (provider is! MinimaxProvider) return null;
      return await provider.retrieveFileDownloadUrl(
        fileId: fileId,
        apiKey: config.apiKey,
      );
    } catch (e) {
      log.error('解析 mm_file:// 失败: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    _container = ProviderScope.containerOf(context);
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
          parts: msg.parts,
          resolveFileUrl: _resolveMmFile,
          reasoning: msg.reasoning,
          toolCalls: msg.toolCalls,
          toolResults: item.toolResults,
          isStreaming: i == displayItems.length - 1 &&
              streaming &&
              !isUser &&
              !item.isToolGroup,
          onWikiRefTap: onWikiRefTap,
          onLongPress: () => _showMsgMenu(
            context,
            content: msg.content,
            isUser: isUser,
            onCopy: () => onCopyMessage(msg.content),
            onSearchWiki: () => onSearchWiki(msg.content),
          ),
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

void _showMsgMenu(
  BuildContext context, {
  required String content,
  required bool isUser,
  required VoidCallback onCopy,
  required VoidCallback onSearchWiki,
}) {
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
            onTap: () {
              Navigator.of(sheetCtx).pop();
              onCopy();
            },
          ),
          ListTile(
            leading: Icon(Icons.search, color: c.textSecondary),
            title: const Text('在 Wiki 中搜索'),
            onTap: () {
              Navigator.of(sheetCtx).pop();
              onSearchWiki();
            },
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
    super.key,
    required this.controller,
    required this.onSend,
    required this.onAttach,
    required this.onPickModel,
    required this.onPickFromCamera,
    required this.onPickFromGallery,
    required this.onShowRecents,
    required this.onSendWithAttachments,
    required this.showTokenCount,
    required this.tokenCount,
    required this.modelLabel,
  });
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final VoidCallback onPickModel;
  final VoidCallback onPickFromCamera;
  final VoidCallback onPickFromGallery;
  final VoidCallback onShowRecents;
  final Future<void> Function({required String content, required List<MessagePart> parts})
      onSendWithAttachments;
  final bool showTokenCount;
  final int tokenCount;
  final String modelLabel;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

/// 附件状态：上传中 / 已就绪 / 失败
enum _AttachmentStatus { uploading, ready, failed }

/// 待发送的附件（图片上传后暂存，等待用户确认）
class _PendingAttachment {
  const _PendingAttachment({
    required this.id,
    required this.fileId,
    required this.localPath,
    required this.fileName,
    required this.status,
    required this.providerId,
    this.originalPath,
    this.thumbnailPath,
  });
  final String id;
  final String fileId;
  final String localPath;
  final String fileName;
  final _AttachmentStatus status;

  /// 此附件上传时使用的 provider ID
  /// 用于切平台时判定是否需要重新上传
  final String providerId;

  /// 原图路径（私有目录的完整路径）
  final String? originalPath;

  /// 缩略图路径（私有目录的完整路径）
  final String? thumbnailPath;

  bool get isReady => status == _AttachmentStatus.ready;
  bool get isUploading => status == _AttachmentStatus.uploading;
  bool get isFailed => status == _AttachmentStatus.failed;

  _PendingAttachment copyWith({
    String? id,
    String? fileId,
    String? localPath,
    String? fileName,
    _AttachmentStatus? status,
    String? providerId,
    String? originalPath,
    String? thumbnailPath,
  }) {
    return _PendingAttachment(
      id: id ?? this.id,
      fileId: fileId ?? this.fileId,
      localPath: localPath ?? this.localPath,
      fileName: fileName ?? this.fileName,
      status: status ?? this.status,
      providerId: providerId ?? this.providerId,
      originalPath: originalPath ?? this.originalPath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    );
  }
}

class _ComposerState extends ConsumerState<_Composer> {
  bool _panelOpen = false;

  /// 待发送的附件列表（上传成功后暂存，等待用户确认或自动发送）
  final List<_PendingAttachment> _pendingAttachments = [];

  /// 快捷问题建议（仅当有待发送图片时出现）
  static const _imageSuggestions = ['这是什么', '找同款', '详细分析'];

  void _togglePanel() {
    setState(() {
      _panelOpen = !_panelOpen;
    });
  }

  void _closePanel() {
    if (_panelOpen) {
      setState(() {
        _panelOpen = false;
      });
    }
  }

  /// 添加上传中的占位附件（图片已选但未完成上传）
  ///
  /// [providerId] 此附件上传使用的 provider ID，用于切平台时判定
  ///
  /// 返回该附件的 id（用 fileName+timestamp），用于上传完成后回调更新。
  String addUploadingAttachment({
    required String localPath,
    required String fileName,
    required String providerId,
  }) {
    final id = '${DateTime.now().microsecondsSinceEpoch}_$fileName';
    setState(() {
      _pendingAttachments.add(_PendingAttachment(
        id: id,
        fileId: '',
        localPath: localPath,
        fileName: fileName,
        status: _AttachmentStatus.uploading,
        providerId: providerId,
      ));
      _panelOpen = false;
    });
    return id;
  }

  /// 更新附件状态：上传完成（成功）
  void markAttachmentUploaded({
    required String id,
    required String fileId,
    required String providerId,
    String? originalPath,
    String? thumbnailPath,
  }) {
    setState(() {
      final idx = _pendingAttachments.indexWhere((a) => a.id == id);
      if (idx < 0) return;
      _pendingAttachments[idx] = _pendingAttachments[idx].copyWith(
        fileId: fileId,
        providerId: providerId,
        originalPath: originalPath,
        thumbnailPath: thumbnailPath,
        status: _AttachmentStatus.ready,
      );
    });
  }

  /// 更新附件状态：上传失败
  void markAttachmentFailed({required String id}) {
    setState(() {
      final idx = _pendingAttachments.indexWhere((a) => a.id == id);
      if (idx < 0) return;
      _pendingAttachments[idx] = _pendingAttachments[idx].copyWith(
        status: _AttachmentStatus.failed,
      );
    });
  }

  /// 处理上传结果（在 Composer 上方显示预览，附带快捷建议）
  ///
  /// 兼容旧接口：直接以 ready 状态添加附件。
  void onImageUploaded({
    required String fileId,
    required String localPath,
    required String fileName,
    required String providerId,
  }) {
    setState(() {
      _pendingAttachments.add(_PendingAttachment(
        id: '${DateTime.now().microsecondsSinceEpoch}_$fileName',
        fileId: fileId,
        localPath: localPath,
        fileName: fileName,
        status: _AttachmentStatus.ready,
        providerId: providerId,
      ));
      _panelOpen = false;
    });
  }

  /// 删除某个附件预览
  void _removeAttachment(int index) {
    setState(() {
      _pendingAttachments.removeAt(index);
    });
  }

  /// 点击快捷建议：填入输入框并发送（带附件一起）
  Future<void> _useSuggestion(String text) async {
    widget.controller.text = text;
    await _handleSend();
  }

  /// 点击发送按钮时，若有就绪的附件则一并发送
  Future<void> _handleSend() async {
    final ready = _pendingAttachments.where((a) => a.isReady).toList();
    if (ready.isNotEmpty) {
      // 把附件 parts 传给上层发送，附带缩略图路径和 providerId
      final parts = ready
          .map((a) => MiniMaxFileIdPart(
                a.fileId,
                'image',
                providerId: a.providerId,
                thumbnailPath: a.thumbnailPath,
              ))
          .toList();
      widget.onSendWithAttachments(
        content: widget.controller.text.trim().isEmpty
            ? '请分析这些图片'
            : widget.controller.text.trim(),
        parts: parts,
      );
      setState(() {
        _pendingAttachments.clear();
        widget.controller.clear();
      });
      return;
    }
    widget.onSend();
  }

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
          // 附件预览区（仅当有待发送图片时显示）
          if (_pendingAttachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: _AttachmentPreview(
                attachments: _pendingAttachments,
                onRemove: _removeAttachment,
              ),
            ),
          // 快捷问题建议（仅当附件全部 ready 时显示）
          if (_pendingAttachments.isNotEmpty &&
              _pendingAttachments.every((a) => a.isReady))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SuggestionBar(
                suggestions: _imageSuggestions,
                onPick: _useSuggestion,
              ),
            ),
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
              _AttachButton(
                isOpen: _panelOpen,
                onTap: _togglePanel,
              ),
              const SizedBox(width: 8),
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
                            onSubmitted: (_) => _handleSend(),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _SendButton(hasText: hasText, onTap: _handleSend),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: _panelOpen
                ? _AttachPanel(
                    onClose: _closePanel,
                    onPickFile: widget.onAttach,
                    onPickFromCamera: widget.onPickFromCamera,
                    onPickFromGallery: widget.onPickFromGallery,
                    onShowRecents: widget.onShowRecents,
                  )
                : const SizedBox.shrink(),
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

/// 附件预览区（图片缩略图 + 删除按钮 + 添加占位）
class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({
    required this.attachments,
    required this.onRemove,
  });
  final List<_PendingAttachment> attachments;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: attachments.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final att = attachments[i];
          return SizedBox(
            width: 88,
            height: 88,
            child: Stack(
              children: [
                // 图片缩略图
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(
                      File(att.localPath),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: c.surfaceVariant,
                        child: Icon(Icons.broken_image_outlined,
                            color: c.textTertiary),
                      ),
                    ),
                  ),
                ),
                // 上传中遮罩 + loading
                if (att.isUploading)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.5),
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                // 失败遮罩 + 重试按钮
                if (att.isFailed)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        color: Colors.red.withValues(alpha: 0.45),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.refresh_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                // 删除按钮
                Positioned(
                  top: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: () => onRemove(i),
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 快捷问题建议栏（豆包风格）
class _SuggestionBar extends StatelessWidget {
  const _SuggestionBar({
    required this.suggestions,
    required this.onPick,
  });
  final List<String> suggestions;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final text = suggestions[i];
          return InkWell(
            onTap: () => onPick(text),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: c.border, width: 0.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    text,
                    style: TextStyle(fontSize: 13, color: c.textPrimary),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded,
                      size: 14, color: c.textSecondary),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AttachButton extends StatelessWidget {
  const _AttachButton({required this.isOpen, required this.onTap});
  final bool isOpen;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isOpen ? c.primary.withValues(alpha: 0.12) : c.surfaceVariant,
          shape: BoxShape.circle,
          border: Border.all(
            color: isOpen ? c.primary : c.border,
            width: 0.5,
          ),
        ),
        child: AnimatedRotation(
          turns: isOpen ? 0.125 : 0,
          duration: const Duration(milliseconds: 200),
          child: Icon(
            Icons.add_rounded,
            size: 22,
            color: isOpen ? c.primary : c.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// 多功能面板：相机、相册、文件、近期项目
///
/// 点击加号后展开，再点加号收起。
class _AttachPanel extends StatelessWidget {
  const _AttachPanel({
    required this.onClose,
    required this.onPickFile,
    required this.onPickFromCamera,
    required this.onPickFromGallery,
    required this.onShowRecents,
  });
  final VoidCallback onClose;
  final VoidCallback onPickFile;
  final VoidCallback onPickFromCamera;
  final VoidCallback onPickFromGallery;
  final VoidCallback onShowRecents;

  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      decoration: BoxDecoration(
        color: c.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _PanelTile(
            icon: Icons.camera_alt_outlined,
            label: '相机',
            onTap: () {
              onClose();
              onPickFromCamera();
            },
          ),
          const SizedBox(width: 8),
          _PanelTile(
            icon: Icons.photo_library_outlined,
            label: '相册',
            onTap: () {
              onClose();
              onPickFromGallery();
            },
          ),
          const SizedBox(width: 8),
          _PanelTile(
            icon: Icons.attach_file_rounded,
            label: '文件',
            onTap: () {
              onClose();
              onPickFile();
            },
          ),
          const SizedBox(width: 8),
          _PanelTile(
            icon: Icons.history_rounded,
            label: '近期',
            onTap: () {
              onClose();
              onShowRecents();
            },
          ),
        ],
      ),
    );
  }
}

class _PanelTile extends StatelessWidget {
  const _PanelTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border, width: 0.5),
          ),
          child: Column(
            children: [
              Icon(icon, size: 22, color: c.textPrimary),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: c.textSecondary),
              ),
            ],
          ),
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