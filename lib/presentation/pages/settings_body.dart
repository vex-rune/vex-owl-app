import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/controller/provider_controller.dart';
import '../../application/controller/settings_controller.dart';
import '../../application/providers/app_providers.dart';
import '../../core/core.dart';
import '../../core/permission/permission_manager.dart';
import '../../data/llm/llm.dart';
import '../../design_system/design_system.dart';
import '../widgets/widgets.dart';

/// 设置页 Body 内容
///
/// 基于 Riverpod ChangeNotifierProvider，所有开关状态绑定到 [SettingsController]。
/// 不包含 Scaffold/AppBar，由 HomePage Shell 统一管理。
///
/// API 配置区域：
/// - 按 Provider 分组展示
/// - "添加配置"对话框包含供应商下拉（来自 [LlmProviderRegistry]）
/// - 模型预设自动填充 endpoint / modelName
/// - 每条配置：设为默认 / 测试连接 / 编辑 / 删除
class SettingsBody extends ConsumerStatefulWidget {
  const SettingsBody({super.key});

  @override
  ConsumerState<SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends ConsumerState<SettingsBody> {
  /// 行级测试状态：id -> 是否正在测试
  final Set<int> _testing = <int>{};

  /// 行级测试结果缓存：id -> (success, message)
  final Map<int, _TestResult> _testResults = <int, _TestResult>{};

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(settingsControllerProvider);
    final c = AppSemanticColors.of(context);

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      children: [
        // ── 权限管理 ──
        _buildPermissionManagementSection(),

        // ── API 配置 ──
        _buildApiConfigSection(context, controller),

        // ── 上下文管理（Phase 3 新增） ──
        _buildContextManagementSection(context, controller),

        // ── 记忆管理 ──
        _buildMemoryManagementSection(controller),

        // ── Token 偏好 ──
        _buildTokenPreferenceSection(context, controller),

        // ── 文件设置 ──
        _buildFileSettingsSection(controller),

        // ── 主题外观 ──
        _buildThemeSection(context),

        // ── 关于 ──
        _buildAboutSection(context),

        // ── 底部健康状态 ──
        Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.pageHorizontal,
            vertical: AppSpacing.sm,
          ),
          padding: const EdgeInsets.all(AppSpacing.base),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: c.border, width: 0.5),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle_outline,
                  size: AppSpacing.iconSizeSm, color: c.success),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Wiki 健康 · 无冲突',
                style: AppTypography.bodySmall.copyWith(color: c.success),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════
  //  权限管理
  // ═══════════════════════════════════════════

  Widget _buildPermissionManagementSection() {
    return SectionPanel(
      title: '权限管理',
      icon: Icons.security,
      children: [
        for (final perm in AppPermission.values)
          _buildPermissionRow(perm),
      ],
    );
  }

  Widget _buildPermissionRow(AppPermission perm) {
    final c = AppSemanticColors.of(context);
    return FutureBuilder<PermissionStatus>(
      future: PermissionManager.check(perm),
      builder: (context, snapshot) {
        final status = snapshot.data?.toUiState() ?? PermissionUiState.denied;
        return ListTile(
          leading: Icon(perm.icon, color: c.primary),
          title: Text(
            perm.label,
            style: AppTypography.bodyLarge
                .copyWith(color: c.textPrimary, fontSize: 15),
          ),
          subtitle: Text(
            perm.description,
            style: AppTypography.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: _buildPermissionStatusChip(status),
          onTap: () => _handlePermissionTap(perm, status),
        );
      },
    );
  }

  Widget _buildPermissionStatusChip(PermissionUiState state) {
    final c = AppSemanticColors.of(context);
    final color = switch (state) {
      PermissionUiState.granted => c.success,
      PermissionUiState.permanentlyDenied => c.error,
      _ => c.warning,
    };
    final label = switch (state) {
      PermissionUiState.granted => '已开启',
      PermissionUiState.permanentlyDenied => '永久拒绝',
      PermissionUiState.restricted => '受限',
      PermissionUiState.limited => '受限',
      _ => '未开启',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppTypography.bodySmall.copyWith(color: color, fontSize: 12),
      ),
    );
  }

  Future<void> _handlePermissionTap(
    AppPermission perm,
    PermissionUiState state,
  ) async {
    if (state == PermissionUiState.permanentlyDenied) {
      await PermissionManager.openAppSettingsPage();
    } else {
      await PermissionManager.request(perm);
    }
  }

  // ═══════════════════════════════════════════
  //  API 配置
  // ═══════════════════════════════════════════

  Widget _buildApiConfigSection(
    BuildContext context,
    SettingsController controller,
  ) {
    final c = AppSemanticColors.of(context);
    final providerController = ref.watch(providerControllerProvider);
    return SectionPanel(
      title: 'API 配置',
      icon: Icons.api_outlined,
      trailing: IconButton(
        icon: const Icon(Icons.add_circle_outline, size: AppSpacing.iconSizeSm),
        color: c.primary,
        tooltip: '添加新配置',
        onPressed: () => _showEditConfigDialog(context, controller, null),
      ),
      children: [
        if (controller.apiConfigs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base,
              vertical: AppSpacing.md,
            ),
            child: Text(
              '暂无 API 配置，请点击右上角 + 添加',
              style: AppTypography.bodySmall.copyWith(color: c.textTertiary),
            ),
          )
        else
          ..._buildGroupedConfigTiles(context, controller, providerController),
        const SizedBox(height: AppSpacing.sm),
        SectionItem(
          icon: Icons.add_circle_outline,
          title: '添加新配置',
          onTap: () => _showEditConfigDialog(context, controller, null),
        ),
      ],
    );
  }

  /// 按 Provider 分组构建配置列表
  List<Widget> _buildGroupedConfigTiles(
    BuildContext context,
    SettingsController controller,
    ProviderController providerController,
  ) {
    final configs = [...controller.apiConfigs];
    // 默认配置排在前面
    configs.sort((a, b) {
      if (a.isDefault && !b.isDefault) return -1;
      if (!a.isDefault && b.isDefault) return 1;
      return a.configName.compareTo(b.configName);
    });

    return configs
        .map((cfg) => _buildConfigTile(context, controller, providerController, cfg))
        .toList();
  }

  Widget _buildConfigTile(
    BuildContext context,
    SettingsController controller,
    ProviderController providerController,
    ApiConfig config,
  ) {
    final c = AppSemanticColors.of(context);
    final provider = providerController.resolveProvider(config);
    final isTesting = _testing.contains(config.id);
    final result = _testResults[config.id];
    final statusIcon = _buildStatusIcon(config, result);

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: c.surfaceVariant,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: config.isDefault ? c.primary : c.border,
          width: config.isDefault ? 0.8 : 0.5,
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusSm),
                    border: Border.all(
                      color: c.primary.withValues(alpha: 0.3),
                      width: 0.5,
                    ),
                  ),
                  child: Icon(
                    _iconForProvider(provider.id),
                    size: AppSpacing.iconSize,
                    color: c.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              config.configName,
                              style: AppTypography.bodyLarge.copyWith(
                                color: c.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          _buildProviderBadge(provider.displayName),
                          const SizedBox(width: 4),
                          _buildProviderTypeBadge(provider),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '${config.modelName} · ${config.redactedApiKey}',
                        style: AppTypography.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (statusIcon != null) statusIcon,
              ],
            ),
          ),
          if (result != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: result.success
                    ? c.success.withValues(alpha: 0.08)
                    : c.error.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(AppSpacing.radiusMd),
                  bottomRight: Radius.circular(AppSpacing.radiusMd),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    result.success
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    size: AppSpacing.iconSizeSm,
                    color: result.success ? c.success : c.error,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      result.message,
                      style: AppTypography.bodySmall.copyWith(
                        color: result.success ? c.success : c.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: c.divider.withValues(alpha: 0.6),
                  width: 0.5,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: 2,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildActionButton(
                      icon: config.isDefault ? Icons.star : Icons.star_border,
                      label: config.isDefault ? '已默认' : '默认',
                      enabled: !config.isDefault,
                      onTap: () => controller.setDefaultConfig(config.id!),
                    ),
                  ),
                  _vDivider(),
                  Expanded(
                    child: _buildActionButton(
                      icon: Icons.wifi_find,
                      label: isTesting ? '测试中' : '测试',
                      enabled: !isTesting,
                      loading: isTesting,
                      onTap: () => _runTestConnection(config),
                    ),
                  ),
                  _vDivider(),
                  Expanded(
                    child: _buildActionButton(
                      icon: Icons.edit_outlined,
                      label: '编辑',
                      onTap: () =>
                          _showEditConfigDialog(context, controller, config),
                    ),
                  ),
                  _vDivider(),
                  Expanded(
                    child: _buildActionButton(
                      icon: Icons.delete_outline,
                      label: '删除',
                      color: c.error,
                      onTap: () =>
                          _confirmDeleteConfig(context, controller, config),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vDivider() {
    final c = AppSemanticColors.of(context);
    return Container(
      width: 0.5,
      height: 20,
      color: c.divider,
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
    bool enabled = true,
    bool loading = false,
  }) {
    final c = AppSemanticColors.of(context);
    final btnColor = color ?? c.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 4,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              loading
                  ? SizedBox(
                      width: AppSpacing.iconSizeSm,
                      height: AppSpacing.iconSizeSm,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor: AlwaysStoppedAnimation<Color>(btnColor),
                      ),
                    )
                  : Icon(icon,
                      size: AppSpacing.iconSizeSm - 2, color: btnColor),
              const SizedBox(height: 2),
              Text(
                label,
                style: AppTypography.bodySmall.copyWith(
                  color: enabled ? btnColor : c.textDisabled,
                  fontSize: 11,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Provider 显示徽章
  Widget _buildProviderBadge(String name) {
    final c = AppSemanticColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: c.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(
          color: c.primary.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Text(
        name,
        style: AppTypography.labelMedium.copyWith(
          color: c.primary,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// 接入方式徽章：官方 / 自定义
  Widget _buildProviderTypeBadge(LlmProvider provider) {
    final c = AppSemanticColors.of(context);
    final isOfficial = provider.configSchema.endpointFixed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isOfficial
            ? c.primary.withValues(alpha: 0.12)
            : c.surfaceVariant,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOfficial ? Icons.verified_outlined : Icons.cloud_outlined,
            size: 10,
            color: isOfficial ? c.primary : c.textTertiary,
          ),
          const SizedBox(width: 3),
          Text(
            isOfficial ? '官方' : '自定义',
            style: AppTypography.bodySmall.copyWith(
              fontSize: 10,
              color: isOfficial ? c.primary : c.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildStatusIcon(ApiConfig config, _TestResult? result) {
    final c = AppSemanticColors.of(context);
    if (result != null && !result.success) {
      return Padding(
        padding: const EdgeInsets.only(left: AppSpacing.sm),
        child: Icon(
          Icons.warning_amber_rounded,
          color: c.error,
          size: AppSpacing.iconSize,
        ),
      );
    }
    if (config.isDefault) {
      return Padding(
        padding: const EdgeInsets.only(left: AppSpacing.sm),
        child: Icon(
          Icons.check_circle,
          color: c.success,
          size: AppSpacing.iconSize,
        ),
      );
    }
    if (result != null && result.success) {
      return Padding(
        padding: const EdgeInsets.only(left: AppSpacing.sm),
        child: Icon(
          Icons.check_circle_outline,
          color: c.success,
          size: AppSpacing.iconSize,
        ),
      );
    }
    return null;
  }

  /// 通过 Provider id 映射到 Material Icon
  IconData _iconForProvider(String id) {
    switch (id) {
      case 'minimax':
        return Icons.smart_toy;
      case 'deepseek':
        return Icons.psychology;
      case 'mimo':
        return Icons.phone_android;
      case 'openai':
        return Icons.bolt_outlined;
      default:
        return Icons.cloud_outlined;
    }
  }

  /// 运行连接测试
  Future<void> _runTestConnection(ApiConfig config) async {
    if (config.id == null) return;
    final id = config.id!;
    final providerController = ref.read(providerControllerProvider);
    setState(() {
      _testing.add(id);
      _testResults.remove(id);
    });
    bool success = false;
    String message = '';
    try {
      success = await providerController.testConnection(config);
      message = success ? 'API 连接正常' : 'API 连接失败';
    } catch (e) {
      success = false;
      message = 'API 连接异常：$e';
    }
    if (!mounted) return;
    setState(() {
      _testing.remove(id);
      _testResults[id] = _TestResult(success, message);
    });
  }

  void _confirmDeleteConfig(
    BuildContext context,
    SettingsController controller,
    ApiConfig config,
  ) {
    final c = AppSemanticColors.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(
          '删除配置',
          style: TextStyle(color: c.error, fontSize: 16),
        ),
        content: Text(
          '确定要删除配置「${config.configName}」吗?此操作不可恢复。',
          style: AppTypography.bodyMedium.copyWith(color: c.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: c.error),
            onPressed: () {
              controller.deleteConfig(config.id!);
              if (config.id != null) {
                _testing.remove(config.id);
                _testResults.remove(config.id);
              }
              Navigator.pop(ctx);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  /// 显示"添加 / 编辑配置"对话框
  void _showEditConfigDialog(
    BuildContext context,
    SettingsController controller,
    ApiConfig? existing,
  ) {
    final providerController = ref.read(providerControllerProvider);
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return _ConfigEditDialog(
          existing: existing,
          providerController: providerController,
          onSubmit: (cfg) async {
            await controller.saveConfig(cfg);
            if (ctx.mounted) Navigator.pop(ctx);
          },
          onTest: providerController.testConnection,
        );
      },
    );
  }

  // ═══════════════════════════════════════════
  //  记忆管理
  // ═══════════════════════════════════════════

  Widget _buildMemoryManagementSection(SettingsController controller) {
    return SectionPanel(
      title: '记忆管理',
      icon: Icons.memory_outlined,
      children: [
        SectionItem(
          icon: Icons.chat_outlined,
          title: '对话后自动触发 Ingest',
          subtitle: '收到完整响应后自动后台执行知识入库',
          trailing: Switch(
            value: controller.autoIngest,
            onChanged: (_) => controller.toggleAutoIngest(),
          ),
        ),
        SectionItem(
          icon: Icons.warning_amber_outlined,
          title: 'Ingest 前自动校验冲突',
          subtitle: '检测到新旧知识冲突时强制确认',
          trailing: Switch(
            value: controller.autoConflictCheck,
            onChanged: (_) => controller.toggleAutoConflictCheck(),
          ),
        ),
        SectionItem(
          icon: Icons.health_and_safety_outlined,
          title: '闲时自动巡检 Wiki',
          subtitle: '设备闲置、充电、WiFi 时后台执行 Lint',
          trailing: Switch(
            value: controller.autoLint,
            onChanged: (_) => controller.toggleAutoLint(),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════
  //  上下文管理（Phase 3 新增）
  // ═══════════════════════════════════════════

  Widget _buildContextManagementSection(
    BuildContext context,
    SettingsController controller,
  ) {
    final c = AppSemanticColors.of(context);
    final settings = controller.settings;
    final ctx = settings.context;

    return SectionPanel(
      title: '上下文管理',
      icon: Icons.layers_outlined,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base,
            vertical: AppSpacing.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '上下文策略',
                style: AppTypography.bodySmall.copyWith(
                  color: c.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              _buildStrategySelector(controller, ctx.strategy),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _strategyHint(ctx.strategy),
                style: AppTypography.bodySmall.copyWith(
                  color: c.textTertiary,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: AppSpacing.lg),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base,
            vertical: AppSpacing.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '上下文最大条数',
                style: AppTypography.bodySmall.copyWith(
                  color: c.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              _buildMaxMessagesSelector(context, controller, ctx.maxMessages),
            ],
          ),
        ),
        const Divider(height: AppSpacing.lg),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base,
            vertical: AppSpacing.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '压缩摘要长度（自动压缩时生效）',
                style: AppTypography.bodySmall.copyWith(
                  color: c.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              _buildSummaryCharsSelector(context, controller, ctx.summaryMaxChars),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: c.surfaceVariant,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: Border.all(color: c.border, width: 0.5),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline,
                  size: AppSpacing.iconSizeSm, color: c.textTertiary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  '自动压缩会消耗额外 API Token，超出条数的旧消息将被 LLM 滚动合并为摘要后写入 wiki/sessions/',
                  style: AppTypography.bodySmall.copyWith(
                    color: c.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStrategySelector(
    SettingsController controller,
    ContextStrategy current,
  ) {
    final c = AppSemanticColors.of(context);
    final options = [
      (ContextStrategy.truncate, '仅截断', Icons.content_cut),
      (ContextStrategy.compress, '自动压缩', Icons.compress),
      (ContextStrategy.nolimit, '不限制', Icons.all_inclusive),
    ];

    return Wrap(
      spacing: AppSpacing.xs,
      children: options.map((opt) {
        final selected = opt.$1 == current;
        return ChoiceChip(
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(opt.$3,
                  size: 14, color: selected ? Colors.white : c.textSecondary),
              const SizedBox(width: 4),
              Text(opt.$2),
            ],
          ),
          selected: selected,
          onSelected: (_) async {
            await controller.setContextStrategy(opt.$1);
          },
          selectedColor: c.primary,
          backgroundColor: c.surfaceVariant,
          labelStyle: AppTypography.bodySmall.copyWith(
            color: selected ? Colors.white : c.textPrimary,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMaxMessagesSelector(
    BuildContext context,
    SettingsController controller,
    int current,
  ) {
    final c = AppSemanticColors.of(context);
    return Wrap(
      spacing: AppSpacing.xs,
      children: ContextSettings.allowedMaxMessages.map((n) {
        final selected = n == current;
        return ChoiceChip(
          label: Text('$n'),
          selected: selected,
          onSelected: (_) async {
            await controller.setMaxMessages(n);
          },
          selectedColor: c.primary,
          backgroundColor: c.surfaceVariant,
          labelStyle: AppTypography.bodySmall.copyWith(
            color: selected ? Colors.white : c.textPrimary,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSummaryCharsSelector(
    BuildContext context,
    SettingsController controller,
    int current,
  ) {
    final c = AppSemanticColors.of(context);
    return Wrap(
      spacing: AppSpacing.xs,
      children: ContextSettings.allowedSummaryChars.map((n) {
        final selected = n == current;
        return ChoiceChip(
          label: Text('${n}字'),
          selected: selected,
          onSelected: (_) async {
            await controller.setSummaryMaxChars(n);
          },
          selectedColor: c.primary,
          backgroundColor: c.surfaceVariant,
          labelStyle: AppTypography.bodySmall.copyWith(
            color: selected ? Colors.white : c.textPrimary,
          ),
        );
      }).toList(),
    );
  }

  String _strategyHint(ContextStrategy s) {
    switch (s) {
      case ContextStrategy.truncate:
        return '超出上限时直接丢弃旧消息，不消耗 API Token（推荐）';
      case ContextStrategy.compress:
        return '超出上限时调用 LLM 生成滚动摘要并写入 wiki/sessions/';
      case ContextStrategy.nolimit:
        return '不做任何截断，可能消耗大量 Token，请谨慎使用';
    }
  }

  // ═══════════════════════════════════════════
  //  Token 偏好
  // ═══════════════════════════════════════════

  Widget _buildTokenPreferenceSection(
    BuildContext context,
    SettingsController controller,
  ) {
    return SectionPanel(
      title: 'Token 偏好',
      icon: Icons.token_outlined,
      children: [
        SectionItem(
          icon: Icons.chat_outlined,
          title: '单次对话 Token 阈值',
          subtitle: '超过阈值时发送前弹出确认框',
          trailing: _buildThresholdChip('${controller.chatTokenThreshold}'),
          onTap: () => _showThresholdEditDialog(
            context,
            title: '对话 Token 阈值',
            currentValue: controller.chatTokenThreshold,
            onSaved: controller.setChatTokenThreshold,
          ),
        ),
        SectionItem(
          icon: Icons.auto_awesome_outlined,
          title: 'Ingest Token 阈值',
          subtitle: '超过阈值时强制二次确认',
          trailing: _buildThresholdChip('${controller.ingestTokenThreshold}'),
          onTap: () => _showThresholdEditDialog(
            context,
            title: 'Ingest Token 阈值',
            currentValue: controller.ingestTokenThreshold,
            onSaved: controller.setIngestTokenThreshold,
          ),
        ),
      ],
    );
  }

  Widget _buildThresholdChip(String value) {
    final c = AppSemanticColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: c.surfaceVariant,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: c.border, width: 0.5),
      ),
      child: Text(
        value,
        style: AppTypography.labelMedium.copyWith(
          color: c.textSecondary,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  void _showThresholdEditDialog(
    BuildContext context, {
    required String title,
    required int currentValue,
    required ValueChanged<int> onSaved,
  }) {
    final c = AppSemanticColors.of(context);
    final ctrl = TextEditingController(text: currentValue.toString());
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(
          title,
          style: TextStyle(color: c.textPrimary, fontSize: 16),
        ),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          style: AppTypography.bodyMedium.copyWith(color: c.textPrimary),
          decoration: InputDecoration(
            hintText: '请输入 Token 数量',
            hintStyle: AppTypography.bodySmall.copyWith(color: c.textDisabled),
            filled: true,
            fillColor: c.surfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              borderSide: BorderSide(color: c.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              borderSide: BorderSide(color: c.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              borderSide: BorderSide(color: c.borderFocus),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final value = int.tryParse(ctrl.text);
              if (value != null && value > 0) {
                onSaved(value);
                Navigator.pop(ctx);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请输入有效的正整数')),
                );
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  文件设置
  // ═══════════════════════════════════════════

  Widget _buildFileSettingsSection(SettingsController controller) {
    return SectionPanel(
      title: '文件设置',
      icon: Icons.folder_outlined,
      children: [
        SectionItem(
          icon: Icons.backup_outlined,
          title: 'Wiki 文件自动备份',
          subtitle: '每次修改自动在 backup/ 下生成历史版本',
          trailing: Switch(
            value: controller.autoBackup,
            onChanged: (_) => controller.toggleAutoBackup(),
          ),
        ),
        SectionItem(
          icon: Icons.cleaning_services_outlined,
          title: 'Raw 文件自动清理',
          subtitle: '自动清理存入超过 30 天的原始素材',
          trailing: Switch(
            value: controller.autoCleanRaw,
            onChanged: (_) => controller.toggleAutoCleanRaw(),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════
  //  主题外观（与抽屉的切换器联动）
  // ═══════════════════════════════════════════

  Widget _buildThemeSection(BuildContext context) {
    final c = AppSemanticColors.of(context);
    final themeMode = ref.watch(themeModeProvider);
    final controller = ref.read(themeModeProvider.notifier);

    Widget segBtn(ThemeMode mode, IconData icon, String label) {
      final selected = mode == themeMode;
      return Expanded(
        child: Material(
          color: selected
              ? c.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            onTap: () => controller.set(mode),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon,
                      size: 18,
                      color: selected ? c.primary : c.textTertiary),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: AppTypography.bodySmall.copyWith(
                      fontSize: 11,
                      color: selected ? c.primary : c.textTertiary,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SectionPanel(
      title: '主题外观',
      icon: Icons.palette_outlined,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base,
            vertical: AppSpacing.sm,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: c.surfaceVariant,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.border, width: 0.5),
            ),
            child: Row(
              children: [
                segBtn(ThemeMode.light, Icons.light_mode_outlined, '白天'),
                segBtn(ThemeMode.dark, Icons.dark_mode_outlined, '夜晚'),
                segBtn(ThemeMode.system, Icons.brightness_auto_outlined, '自动'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════
  //  关于
  // ═══════════════════════════════════════════

  Widget _buildAboutSection(BuildContext context) {
    final c = AppSemanticColors.of(context);
    return SectionPanel(
      title: '关于',
      icon: Icons.info_outline,
      children: [
        SectionItem(
          icon: Icons.code_outlined,
          title: '查看 schema.md',
          subtitle: 'LLM Wiki 编写规则',
          trailing: Icon(Icons.chevron_right,
              color: c.textTertiary, size: AppSpacing.iconSizeSm),
        ),
        SectionItem(
          icon: Icons.storage_outlined,
          title: '存储统计',
          subtitle: 'Wiki 12 个页面 · Raw 3 个文件 · 256 KB',
          trailing: Icon(Icons.chevron_right,
              color: c.textTertiary, size: AppSpacing.iconSizeSm),
        ),
        SectionItem(
          icon: Icons.token_outlined,
          title: 'Token 消耗统计',
          subtitle: '今日: 12,480 tokens · 本月: 156,720 tokens',
          trailing: Icon(Icons.chevron_right,
              color: c.textTertiary, size: AppSpacing.iconSizeSm),
        ),
        const SizedBox(height: AppSpacing.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
          child: OutlinedButton(
            onPressed: () => _handleClearWiki(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: c.error,
              side: BorderSide(color: c.error, width: 0.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            ),
            child: const Text('清空 Wiki 知识库'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
          child: OutlinedButton(
            onPressed: () => _handleClearAll(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: c.error,
              side: BorderSide(color: c.error, width: 0.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            ),
            child: const Text('清空所有数据'),
          ),
        ),
        const SizedBox(height: AppSpacing.base),
        Center(
          child: Text(
            'Owl v0.1.0 · LLM-Wiki v1.0',
            style: AppTypography.bodySmall.copyWith(
              color: c.textTertiary,
              fontSize: 11,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }

  void _handleClearWiki(BuildContext context) {
    final c = AppSemanticColors.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text('清空 Wiki 知识库',
            style: TextStyle(color: c.error, fontSize: 16)),
        content: Text(
          '将删除 wiki/ 下所有页面，保留 raw/、schema.md、index.md。此操作不可恢复。',
          style: AppTypography.bodyMedium.copyWith(color: c.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: c.error),
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Wiki 知识库已清空')),
              );
            },
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
  }

  void _handleClearAll(BuildContext context) {
    final c = AppSemanticColors.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text('清空所有数据',
            style: TextStyle(color: c.error, fontSize: 16)),
        content: Text(
          '将删除整个 llm-wiki 目录，恢复初始化状态。所有知识、对话记录将被永久删除。',
          style: AppTypography.bodyMedium.copyWith(color: c.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: c.error),
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('所有数据已清空')),
              );
            },
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
  }
}

/// 单条配置的测试结果缓存
class _TestResult {
  const _TestResult(this.success, this.message);
  final bool success;
  final String message;
}

// ═══════════════════════════════════════════
//  添加 / 编辑 API 配置 对话框
// ═══════════════════════════════════════════

/// "添加 / 编辑 API 配置" 对话框
class _ConfigEditDialog extends StatefulWidget {
  const _ConfigEditDialog({
    required this.existing,
    required this.providerController,
    required this.onSubmit,
    required this.onTest,
  });

  final ApiConfig? existing;
  final ProviderController providerController;
  final Future<void> Function(ApiConfig config) onSubmit;
  final Future<bool> Function(ApiConfig config) onTest;

  @override
  State<_ConfigEditDialog> createState() => _ConfigEditDialogState();
}

class _ConfigEditDialogState extends State<_ConfigEditDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _modelCtrl;
  late final TextEditingController _endpointCtrl;
  late final TextEditingController _keyCtrl;
  late String _selectedProviderId;
  bool _isTesting = false;
  String? _testResultMsg;
  bool? _testResultSuccess;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.configName ?? '');
    _modelCtrl = TextEditingController(text: e?.modelName ?? '');
    _endpointCtrl = TextEditingController(text: e?.apiEndpoint ?? '');
    _keyCtrl = TextEditingController(text: e?.apiKey ?? '');
    _selectedProviderId = (e != null && e.providerId.isNotEmpty)
        ? e.providerId
        : (widget.providerController.providers.isNotEmpty
            ? widget.providerController.providers.first.id
            : 'auto');
    _applySchemaDefaults(_selectedProviderId);
  }

  /// 根据当前 Provider 的 schema 应用默认值（仅对空白字段生效）
  ///
  /// 配置名称自动同步为模型名称。
  void _applySchemaDefaults(String providerId) {
    final provider = widget.providerController.providerById(providerId);
    if (provider == null) return;
    final schema = provider.configSchema;
    if (widget.existing == null) {
      if (_modelCtrl.text.isEmpty) _modelCtrl.text = schema.modelDefault;
      if (_endpointCtrl.text.isEmpty) _endpointCtrl.text = schema.endpointDefault;
      // 配置名称 = 模型名称
      if (_nameCtrl.text.isEmpty) _nameCtrl.text = _modelCtrl.text;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _modelCtrl.dispose();
    _endpointCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _runTest() async {
    if (_modelCtrl.text.trim().isEmpty || _keyCtrl.text.trim().isEmpty) {
      setState(() {
        _testResultSuccess = false;
        _testResultMsg = '请先填写模型名称和 API Key';
      });
      return;
    }
    var cfg = _buildConfig();
    final provider = widget.providerController.providerById(_selectedProviderId);
    if (provider != null) {
      cfg = provider.resolveConfig(cfg);
    }
    setState(() {
      _isTesting = true;
      _testResultMsg = null;
    });
    bool ok = false;
    try {
      ok = await widget.onTest(cfg);
    } catch (err) {
      ok = false;
      _testResultMsg = '异常：$err';
    }
    if (!mounted) return;
    setState(() {
      _isTesting = false;
      _testResultSuccess = ok;
      _testResultMsg ??= ok ? 'API 连接正常 ✓' : 'API 连接失败';
    });
  }

  ApiConfig _buildConfig() {
    final e = widget.existing;
    final provider = widget.providerController.providerById(_selectedProviderId);
    final schema = provider?.configSchema ?? const ProviderConfigSchema();
    final modelName = _modelCtrl.text.trim().isNotEmpty
        ? _modelCtrl.text.trim()
        : schema.modelDefault;
    final endpoint = _endpointCtrl.text.trim().isNotEmpty
        ? _endpointCtrl.text.trim()
        : schema.endpointDefault;
    return ApiConfig(
      id: e?.id,
      configName: modelName,
      modelName: modelName,
      apiEndpoint: endpoint,
      apiKey: _keyCtrl.text.trim(),
      isDefault: e?.isDefault ?? false,
      providerId: _selectedProviderId,
    );
  }

  void _submit() {
    if (_modelCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择或输入模型名称')),
      );
      return;
    }
    if (_keyCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入 API Key')),
      );
      return;
    }
    var cfg = _buildConfig();
    final provider = widget.providerController.providerById(_selectedProviderId);
    if (provider != null) {
      cfg = provider.resolveConfig(cfg);
    }
    widget.onSubmit(cfg);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    final providers = widget.providerController.providers;
    final presets = widget.providerController.presetsFor(_selectedProviderId);
    final isEdit = widget.existing != null;
    final schema = widget.providerController
            .providerById(_selectedProviderId)?.configSchema ??
        const ProviderConfigSchema();
    return AlertDialog(
      backgroundColor: c.surface,
      title: Text(
        isEdit ? '编辑 API 配置' : '添加 API 配置',
        style: TextStyle(color: c.textPrimary, fontSize: 16),
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildLabel('供应商'),
              const SizedBox(height: AppSpacing.xs),
              _buildProviderDropdown(providers),
              const SizedBox(height: AppSpacing.md),
              if (schema.showModel) ...[
                _buildLabel('模型'),
                const SizedBox(height: AppSpacing.xs),
                _buildModelDropdown(presets),
                const SizedBox(height: AppSpacing.md),
              ],
              if (schema.showEndpoint && schema.endpointEditable) ...[
                _buildLabel('API 端点'),
                const SizedBox(height: AppSpacing.xs),
                _buildTextField(
                  controller: _endpointCtrl,
                  hint: 'https://api.example.com/v1',
                ),
                const SizedBox(height: AppSpacing.md),
              ] else if (schema.showEndpoint && !schema.endpointEditable) ...[
                _buildLabel('API 端点'),
                const SizedBox(height: AppSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: c.surfaceVariant,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    border: Border.all(color: c.border, width: 0.5),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline,
                          size: 14, color: c.textTertiary),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          _endpointCtrl.text.isEmpty
                              ? schema.endpointDefault
                              : _endpointCtrl.text,
                          style: AppTypography.bodyMedium
                              .copyWith(color: c.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              _buildLabel('API Key'),
              const SizedBox(height: AppSpacing.xs),
              _buildTextField(
                controller: _keyCtrl,
                hint: '请输入 API Key',
                obscure: true,
              ),
              if (_testResultMsg != null) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: (_testResultSuccess ?? false)
                        ? c.success.withValues(alpha: 0.1)
                        : c.error.withValues(alpha: 0.1),
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusSm),
                    border: Border.all(
                      color: (_testResultSuccess ?? false)
                          ? c.success.withValues(alpha: 0.3)
                          : c.error.withValues(alpha: 0.3),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        (_testResultSuccess ?? false)
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        size: AppSpacing.iconSizeSm,
                        color: (_testResultSuccess ?? false)
                            ? c.success
                            : c.error,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          _testResultMsg!,
                          style: AppTypography.bodySmall.copyWith(
                            color: (_testResultSuccess ?? false)
                                ? c.success
                                : c.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isTesting ? null : _runTest,
          child: _isTesting
              ? SizedBox(
                  width: AppSpacing.iconSizeSm - 4,
                  height: AppSpacing.iconSizeSm - 4,
                  child: const CircularProgressIndicator(strokeWidth: 1.5),
                )
              : const Text('测试连接'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }

  Widget _buildLabel(String text) {
    final c = AppSemanticColors.of(context);
    return Text(
      text,
      style: AppTypography.bodySmall.copyWith(
        color: c.textSecondary,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildProviderDropdown(List<LlmProvider> providers) {
    final c = AppSemanticColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: c.surfaceVariant,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: c.border, width: 0.5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: providers.any((p) => p.id == _selectedProviderId)
              ? _selectedProviderId
              : (providers.isNotEmpty ? providers.first.id : null),
          isExpanded: true,
          dropdownColor: c.surfaceVariant,
          iconEnabledColor: c.primary,
          style: AppTypography.bodyMedium.copyWith(color: c.textPrimary),
          items: providers
              .map((p) => DropdownMenuItem<String>(
                    value: p.id,
                    child: Row(
                      children: [
                        Icon(
                          _iconForProviderStatic(p.id),
                          size: AppSpacing.iconSizeSm,
                          color: c.primary,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(p.displayName),
                      ],
                    ),
                  ))
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _selectedProviderId = v;
            });
            _applySchemaDefaults(v);
          },
        ),
      ),
    );
  }

  Widget _buildModelDropdown(List<ProviderModelPreset> presets) {
    final c = AppSemanticColors.of(context);
    final hasPreset = presets.any((p) => p.id == _modelCtrl.text);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: c.surfaceVariant,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: c.border, width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: hasPreset ? _modelCtrl.text : null,
                isExpanded: true,
                dropdownColor: c.surfaceVariant,
                iconEnabledColor: c.primary,
                hint: Text(
                  '选择模型预设',
                  style: AppTypography.bodyMedium
                      .copyWith(color: c.textDisabled),
                ),
                style: AppTypography.bodyMedium.copyWith(color: c.textPrimary),
                items: presets
                    .map((p) => DropdownMenuItem<String>(
                          value: p.id,
                          child: Text(p.displayName),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _modelCtrl.text = v;
                    // 配置名称 = 模型名称
                    if (_nameCtrl.text.isEmpty || _nameCtrl.text == _modelCtrl.text) {
                      _nameCtrl.text = v;
                    }
                  });
                },
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 100,
            child: TextField(
              controller: _modelCtrl,
              style: AppTypography.bodyMedium
                  .copyWith(color: c.textPrimary, fontSize: 12),
              decoration: InputDecoration(
                hintText: '或自定义',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.sm,
                ),
                filled: true,
                fillColor: c.surface,
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusSm),
                  borderSide:
                      BorderSide(color: c.border, width: 0.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusSm),
                  borderSide:
                      BorderSide(color: c.border, width: 0.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusSm),
                  borderSide: BorderSide(color: c.borderFocus),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    bool obscure = false,
  }) {
    final c = AppSemanticColors.of(context);
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: AppTypography.bodyMedium.copyWith(color: c.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            AppTypography.bodySmall.copyWith(color: c.textDisabled),
        filled: true,
        fillColor: c.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          borderSide: BorderSide(color: c.borderFocus),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        isDense: true,
      ),
    );
  }

  IconData _iconForProviderStatic(String id) {
    switch (id) {
      case 'minimax':
        return Icons.smart_toy;
      case 'deepseek':
        return Icons.psychology;
      case 'mimo':
        return Icons.phone_android;
      case 'openai':
        return Icons.bolt_outlined;
      default:
        return Icons.cloud_outlined;
    }
  }
}