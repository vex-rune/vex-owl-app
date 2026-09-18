import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/controller/provider_controller.dart';
import '../../application/controller/settings_controller.dart';
import '../../core/core.dart';
import '../../core/permission/permission_manager.dart';
import '../../data/llm/llm.dart';
import '../../design_system/design_system.dart';
import '../widgets/widgets.dart';

/// 设置页 Body 内容（v6.3：逐个添加 Agent）
///
/// 基于 Riverpod ChangeNotifierProvider，所有开关状态绑定到 [SettingsController]。
/// 不包含 Scaffold/AppBar，由 HomePage Shell 统一管理。
///
/// API 配置区域（v6.3 重写）：
/// - 按 Provider 分组（minimax / deepseek / mimo / openai）
/// - 每个 Provider 卡片底部有「添加 Agent」按钮，弹出该 Provider 尚未添加的模型列表
/// - 用户点击某个 Agent 可编辑 endpoint / apiKey / 温度 / topP / max_tokens / thinking
/// - 长按 Agent 可删除
/// - 「设为默认」= 当前对话默认使用这个 Agent
class SettingsBody extends ConsumerStatefulWidget {
  const SettingsBody({super.key});

  @override
  ConsumerState<SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends ConsumerState<SettingsBody> {
  /// 行级测试状态：key = providerId::modelName
  final Set<String> _testing = <String>{};

  /// 行级测试结果缓存：key -> (success, message)
  final Map<String, _TestResult> _testResults = <String, _TestResult>{};

  String _agentKey(ApiConfig a) => '${a.providerId}::${a.modelName}';

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(settingsControllerProvider);
    final c = AppSemanticColors.of(context);

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      children: [

        // ── API 配置（v6.2 重写） ──
        _buildApiConfigSection(context, controller),

        // ── 上下文管理 ──
        _buildContextManagementSection(context, controller),

        // ── 记忆管理 ──
        _buildMemoryManagementSection(controller),

        // ── Token 偏好 ──
        _buildTokenPreferenceSection(context, controller),

        // ── 文件设置 ──
        _buildFileSettingsSection(controller),
        
        // ── 权限管理 ──
        _buildPermissionManagementSection(),

        // ── 主题外观 ──
        _buildThemeSection(context),

        // ── 关于 ──
        _buildAboutSection(),

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
  //  API 配置（v6.3：逐个添加 Agent）
  // ═══════════════════════════════════════════

  Widget _buildApiConfigSection(
    BuildContext context,
    SettingsController controller,
  ) {
    final providerController = ref.watch(providerControllerProvider);
    final agentsByProvider = _groupAgentsByProvider(controller.agents);
    return SectionPanel(
      title: 'API 配置 · Agent',
      icon: Icons.api_outlined,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base,
            vertical: AppSpacing.sm,
          ),
          child: Text(
            '每个 Provider 可添加多个模型作为独立 Agent。'
            '点击「添加」选择模型，点击 Agent 配置参数。',
            style: AppTypography.bodySmall.copyWith(
                color: AppSemanticColors.of(context).textTertiary),
          ),
        ),
        for (final provider in providerController.providers)
          _buildProviderGroup(
            context,
            controller,
            provider,
            agentsByProvider[provider.id] ?? const [],
          ),
      ],
    );
  }

  Widget _buildProviderGroup(
    BuildContext context,
    SettingsController controller,
    LlmProvider provider,
    List<ApiConfig> agents,
  ) {
    final c = AppSemanticColors.of(context);
    final presets = ref.read(providerControllerProvider).presetsFor(provider.id);
    // 过滤掉已添加的模型
    final addedModels = agents.map((a) => a.modelName).toSet();
    final available =
        presets.where((p) => !addedModels.contains(p.id)).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.xs,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: c.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Provider header
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.base,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Icon(
                    _iconForProvider(provider.id),
                    size: AppSpacing.iconSizeSm,
                    color: c.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    provider.displayName,
                    style: AppTypography.bodyMedium.copyWith(
                      color: c.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _buildProviderTypeBadge(provider),
                  const Spacer(),
                  if (agents.isNotEmpty)
                    Text(
                      '${agents.length} 个',
                      style: AppTypography.bodySmall
                          .copyWith(color: c.textTertiary),
                    ),
                ],
              ),
            ),
            Divider(height: 0.5, color: c.divider),
            // Agent 列表
            if (agents.isNotEmpty)
              ...agents.map(
                (a) => _buildAgentTile(context, controller, a),
              ),
            // 添加 Agent 按钮
            if (available.isNotEmpty)
              InkWell(
                onTap: () =>
                    _showAddAgentDialog(context, controller, provider, available),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.add_circle_outline,
                          size: 18, color: c.primary),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        '添加 Agent',
                        style: AppTypography.bodyMedium.copyWith(
                          color: c.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // 无可用模型提示
            if (agents.isEmpty && available.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: Text(
                  '该 Provider 无可用模型',
                  style: AppTypography.bodySmall
                      .copyWith(color: c.textTertiary),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgentTile(
    BuildContext context,
    SettingsController controller,
    ApiConfig agent,
  ) {
    final c = AppSemanticColors.of(context);
    final key = _agentKey(agent);
    final isTesting = _testing.contains(key);
    final result = _testResults[key];

    return InkWell(
      onTap: () => _showAgentEditDialog(context, controller, agent),
      onLongPress: () => _showAgentDeleteMenu(context, controller, agent),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: agent.isDefault
                        ? c.primary.withValues(alpha: 0.15)
                        : c.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: agent.isDefault ? c.primary : c.border,
                      width: agent.isDefault ? 1 : 0.5,
                    ),
                  ),
                  child: Icon(
                    agent.isDefault
                        ? Icons.auto_awesome
                        : Icons.bolt_outlined,
                    size: 18,
                    color: agent.isDefault ? c.primary : c.textSecondary,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              agent.modelName,
                              style: AppTypography.bodyMedium.copyWith(
                                color: c.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (agent.thinkingEnabled) ...[
                            const SizedBox(width: 4),
                            _MiniBadge(
                              label: '思考',
                              color: c.accent,
                              icon: Icons.psychology_outlined,
                            ),
                          ],
                          if (!agent.enabled) ...[
                            const SizedBox(width: 4),
                            _MiniBadge(
                              label: '未启用',
                              color: c.textTertiary,
                              icon: Icons.visibility_off_outlined,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        agent.apiKey.isEmpty
                            ? '未配置 API Key'
                            : 'Key: ${agent.redactedApiKey}',
                        style: AppTypography.bodySmall
                            .copyWith(color: c.textTertiary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (isTesting)
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.sm),
                    child: SizedBox(
                      width: AppSpacing.iconSizeSm,
                      height: AppSpacing.iconSizeSm,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor: AlwaysStoppedAnimation<Color>(c.primary),
                      ),
                    ),
                  )
                else if (result != null)
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.sm),
                    child: Icon(
                      result.success
                          ? Icons.check_circle_outline
                          : Icons.warning_amber_rounded,
                      size: AppSpacing.iconSize,
                      color: result.success ? c.success : c.error,
                    ),
                  ),
                Icon(
                  Icons.chevron_right,
                  size: AppSpacing.iconSize,
                  color: c.textTertiary,
                ),
              ],
            ),
            if (result != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: result.success
                        ? c.success.withValues(alpha: 0.08)
                        : c.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Text(
                    result.message,
                    style: AppTypography.bodySmall.copyWith(
                      color: result.success ? c.success : c.error,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 打开 Agent 编辑面板
  void _showAgentEditDialog(
    BuildContext context,
    SettingsController controller,
    ApiConfig agent,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _AgentEditDialog(
        agent: agent,
        onSave: (next) async {
          await controller.saveAgent(next);
          if (ctx.mounted) Navigator.pop(ctx);
        },
        onTest: (cfg) async {
          final key = _agentKey(cfg);
          setState(() {
            _testing.add(key);
            _testResults.remove(key);
          });
          bool ok = false;
          String msg;
          try {
            ok = await ref
                .read(providerControllerProvider)
                .testConnection(cfg);
            msg = ok ? 'API 连接正常' : 'API 连接失败';
          } catch (e) {
            ok = false;
            msg = '异常：$e';
          }
          if (!mounted) return ok;
          setState(() {
            _testing.remove(key);
            _testResults[key] = _TestResult(ok, msg);
          });
          return ok;
        },
        onSetDefault: () async {
          await controller.setDefaultAgent(agent.providerId, agent.modelName);
        },
        onToggleEnabled: () async {
          await controller.setAgentEnabled(
            agent.providerId,
            agent.modelName,
            enabled: !agent.enabled,
          );
        },
      ),
    );
  }

  /// 长按 Agent 弹出删除菜单
  void _showAgentDeleteMenu(
    BuildContext context,
    SettingsController controller,
    ApiConfig agent,
  ) {
    final c = AppSemanticColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: c.textDisabled,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                agent.modelName,
                style: AppTypography.titleMedium
                    .copyWith(color: c.textPrimary),
              ),
            ),
            Divider(height: 0.5, color: c.divider),
            ListTile(
              leading: Icon(Icons.delete_outline, color: c.error),
              title: Text(
                '删除 Agent',
                style: AppTypography.bodyMedium.copyWith(color: c.error),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                await controller.deleteAgent(
                    agent.providerId, agent.modelName);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 弹出「添加 Agent」对话框：列出该 Provider 尚未添加的模型供选择
  void _showAddAgentDialog(
    BuildContext context,
    SettingsController controller,
    LlmProvider provider,
    List<ProviderModelPreset> available,
  ) {
    final c = AppSemanticColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: c.textDisabled,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                '添加 ${provider.displayName} Agent',
                style: AppTypography.titleMedium
                    .copyWith(color: c.textPrimary),
              ),
            ),
            Divider(height: 0.5, color: c.divider),
            for (final preset in available)
              ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child:
                      Icon(Icons.add_circle_outline, size: 18, color: c.primary),
                ),
                title: Text(
                  preset.displayName,
                  style: AppTypography.bodyMedium.copyWith(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  preset.description ?? preset.id,
                  style: AppTypography.bodySmall
                      .copyWith(color: c.textTertiary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await controller.addAgent(provider.id, preset.id);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
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
  //  上下文管理
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
                style: AppTypography.bodySmall.copyWith(color: c.textTertiary),
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
              _buildSummaryCharsSelector(
                  context, controller, ctx.summaryMaxChars),
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
                  style: AppTypography.bodySmall
                      .copyWith(color: c.textTertiary),
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
        return '超过最大条数时直接丢弃最旧消息，无额外 API 调用';
      case ContextStrategy.compress:
        return '超过最大条数时让 LLM 滚动合并为摘要，写入 wiki/sessions/';
      case ContextStrategy.nolimit:
        return '保留全部消息；适合调试与小上下文场景';
    }
  }

  // ═══════════════════════════════════════════
  //  Token 偏好
  // ═══════════════════════════════════════════

  Widget _buildTokenPreferenceSection(
    BuildContext context,
    SettingsController controller,
  ) {
    final c = AppSemanticColors.of(context);
    return SectionPanel(
      title: 'Token 偏好',
      icon: Icons.timeline_outlined,
      children: [
        _buildSliderRow(
          context,
          label: '对话告警阈值',
          subtitle: '单次对话 token 累计达此值时弹提示',
          value: controller.chatTokenThreshold.toDouble(),
          min: 1000,
          max: 32000,
          step: 1000,
          onChanged: (v) =>
              controller.setChatTokenThreshold(v.toInt()),
          display: '${controller.chatTokenThreshold}',
        ),
        _buildSliderRow(
          context,
          label: 'Ingest 告警阈值',
          subtitle: '单次素材摄入消耗 token 达此值时暂停',
          value: controller.ingestTokenThreshold.toDouble(),
          min: 1000,
          max: 32000,
          step: 1000,
          onChanged: (v) =>
              controller.setIngestTokenThreshold(v.toInt()),
          display: '${controller.ingestTokenThreshold}',
        ),
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
              Icon(Icons.tips_and_updates_outlined,
                  size: AppSpacing.iconSizeSm, color: c.warning),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Token 数据由 LLM 实际返回的 usage 字段累加得到；阈值只是提醒，不会阻断对话',
                  style:
                      AppTypography.bodySmall.copyWith(color: c.textTertiary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSliderRow(
    BuildContext context, {
    required String label,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required double step,
    required ValueChanged<double> onChanged,
    required String display,
  }) {
    final c = AppSemanticColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTypography.bodyMedium
                          .copyWith(color: c.textPrimary),
                    ),
                    Text(
                      subtitle,
                      style: AppTypography.bodySmall
                          .copyWith(color: c.textTertiary),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: c.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  display,
                  style: AppTypography.bodySmall.copyWith(
                    color: c.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: ((max - min) / step).toInt(),
            label: display,
            onChanged: onChanged,
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
          icon: Icons.auto_delete_outlined,
          title: '自动清理 raw/ 素材',
          subtitle: '摄入完成 7 天后删除 raw/ 原始文件',
          trailing: Switch(
            value: controller.autoCleanRaw,
            onChanged: (_) => controller.toggleAutoCleanRaw(),
          ),
        ),
        SectionItem(
          icon: Icons.backup_outlined,
          title: '写入前自动备份',
          subtitle: '每次写入 wiki 文件前在 .backup/ 留一份历史',
          trailing: Switch(
            value: controller.autoBackup,
            onChanged: (_) => controller.toggleAutoBackup(),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════
  //  主题外观
  // ═══════════════════════════════════════════

  Widget _buildThemeSection(BuildContext context) {
    final c = AppSemanticColors.of(context);
    return SectionPanel(
      title: '主题外观',
      icon: Icons.palette_outlined,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Icon(Icons.color_lens_outlined,
                  size: AppSpacing.iconSizeSm, color: c.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '主题由系统外观自动切换（v6.2）',
                  style: AppTypography.bodyMedium
                      .copyWith(color: c.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════
  //  关于
  // ═══════════════════════════════════════════

  Widget _buildAboutSection() {
    final c = AppSemanticColors.of(context);
    return SectionPanel(
      title: '关于',
      icon: Icons.info_outline,
      children: [
        ListTile(
          leading: Icon(Icons.android, color: c.primary),
          title: Text('LLM-Wiki · v6.2',
              style: AppTypography.bodyMedium
                  .copyWith(color: c.textPrimary)),
          subtitle: Text(
            'Agent 化的本地知识库引擎',
            style: AppTypography.bodySmall.copyWith(color: c.textTertiary),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════
  //  辅助组件
  // ═══════════════════════════════════════════

  Map<String, List<ApiConfig>> _groupAgentsByProvider(List<ApiConfig> all) {
    final map = <String, List<ApiConfig>>{};
    for (final a in all) {
      map.putIfAbsent(a.providerId, () => []).add(a);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.modelName.compareTo(b.modelName));
    }
    return map;
  }

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

  }

/// 单条 Agent 的测试结果
class _TestResult {
  const _TestResult(this.success, this.message);
  final bool success;
  final String message;
}

/// 紧凑徽章（用于 Agent 卡片右侧 chip）
class _MiniBadge extends StatelessWidget {
  const _MiniBadge({
    required this.label,
    required this.color,
    this.icon,
  });
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 2),
          ],
          Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════
//  Agent 编辑对话框
// ═══════════════════════════════════════════

class _AgentEditDialog extends StatefulWidget {
  const _AgentEditDialog({
    required this.agent,
    required this.onSave,
    required this.onTest,
    required this.onSetDefault,
    required this.onToggleEnabled,
  });

  final ApiConfig agent;
  final Future<void> Function(ApiConfig next) onSave;
  final Future<bool> Function(ApiConfig cfg) onTest;
  final Future<void> Function() onSetDefault;
  final Future<void> Function() onToggleEnabled;

  @override
  State<_AgentEditDialog> createState() => _AgentEditDialogState();
}

class _AgentEditDialogState extends State<_AgentEditDialog> {
  late TextEditingController _endpointCtrl;
  late TextEditingController _keyCtrl;
  late TextEditingController _maxTokensCtrl;
  late double _temperature;
  late double _topP;
  late bool _thinkingEnabled;
  late bool _enabled;
  late bool _isDefault;
  bool _isTesting = false;
  String? _testResultMsg;
  bool? _testResultSuccess;

  @override
  void initState() {
    super.initState();
    final a = widget.agent;
    _endpointCtrl = TextEditingController(text: a.apiEndpoint);
    _keyCtrl = TextEditingController(text: a.apiKey);
    _maxTokensCtrl = TextEditingController(text: '${a.maxCompletionTokens}');
    _temperature = a.temperature;
    _topP = a.topP;
    _thinkingEnabled = a.thinkingEnabled;
    _enabled = a.enabled;
    _isDefault = a.isDefault;
  }

  @override
  void dispose() {
    _endpointCtrl.dispose();
    _keyCtrl.dispose();
    _maxTokensCtrl.dispose();
    super.dispose();
  }

  ApiConfig _buildNext() {
    return widget.agent.copyWith(
      apiEndpoint: _endpointCtrl.text.trim().isNotEmpty
          ? _endpointCtrl.text.trim()
          : widget.agent.apiEndpoint,
      apiKey: _keyCtrl.text.trim(),
      temperature: _temperature,
      topP: _topP,
      maxCompletionTokens: int.tryParse(_maxTokensCtrl.text.trim()) ??
          widget.agent.maxCompletionTokens,
      thinkingEnabled: _thinkingEnabled,
      enabled: _enabled,
      isDefault: _isDefault,
    );
  }

  Future<void> _runTest() async {
    if (_keyCtrl.text.trim().isEmpty) {
      setState(() {
        _testResultSuccess = false;
        _testResultMsg = '请先填写 API Key';
      });
      return;
    }
    setState(() {
      _isTesting = true;
      _testResultMsg = null;
    });
    final ok = await widget.onTest(_buildNext());
    if (!mounted) return;
    setState(() {
      _isTesting = false;
      _testResultSuccess = ok;
      _testResultMsg = ok ? 'API 连接正常 ✓' : 'API 连接失败';
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.of(context);
    return AlertDialog(
      backgroundColor: c.surface,
      title: Text(
        widget.agent.modelName,
        style: TextStyle(color: c.textPrimary, fontSize: 16),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Provider · ${widget.agent.providerId}',
                style: AppTypography.bodySmall
                    .copyWith(color: c.textTertiary),
              ),
              const SizedBox(height: AppSpacing.md),
              _buildLabel('API 端点'),
              const SizedBox(height: AppSpacing.xs),
              _buildTextField(
                _endpointCtrl,
                hint: 'https://api.example.com/v1',
              ),
              const SizedBox(height: AppSpacing.md),
              _buildLabel('API Key'),
              const SizedBox(height: AppSpacing.xs),
              _buildTextField(
                _keyCtrl,
                hint: '请输入 API Key',
                obscure: true,
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: _buildSliderField(
                      label: '温度',
                      value: _temperature,
                      min: 0,
                      max: 2,
                      divisions: 20,
                      display: _temperature.toStringAsFixed(2),
                      onChanged: (v) => setState(() => _temperature = v),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _buildSliderField(
                      label: 'Top-P',
                      value: _topP,
                      min: 0,
                      max: 1,
                      divisions: 20,
                      display: _topP.toStringAsFixed(2),
                      onChanged: (v) => setState(() => _topP = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _buildLabel('最大完成 token 数'),
              const SizedBox(height: AppSpacing.xs),
              _buildTextField(
                _maxTokensCtrl,
                hint: '4096',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: AppSpacing.md),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text('启用深度思考',
                    style: AppTypography.bodyMedium
                        .copyWith(color: c.textPrimary)),
                subtitle: Text(
                  '开启后 DeepSeek 会使用 reasoning_effort；'
                  'DeepSeek 启用时不可同时设温度与 Top-P',
                  style: AppTypography.bodySmall
                      .copyWith(color: c.textTertiary),
                ),
                value: _thinkingEnabled,
                onChanged: (v) => setState(() => _thinkingEnabled = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text('启用此 Agent',
                    style: AppTypography.bodyMedium
                        .copyWith(color: c.textPrimary)),
                subtitle: Text(
                  '关闭后该 Agent 不参与默认/模型切换候选',
                  style: AppTypography.bodySmall
                      .copyWith(color: c.textTertiary),
                ),
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text('设为默认 Agent',
                    style: AppTypography.bodyMedium
                        .copyWith(color: c.textPrimary)),
                subtitle: Text(
                  '对话时未指定模型则使用此 Agent',
                  style: AppTypography.bodySmall
                      .copyWith(color: c.textTertiary),
                ),
                value: _isDefault,
                onChanged: (v) => setState(() => _isDefault = v),
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
          onPressed: () => widget.onSave(_buildNext()),
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

  Widget _buildTextField(
    TextEditingController controller, {
    required String hint,
    bool obscure = false,
    TextInputType? keyboardType,
  }) {
    final c = AppSemanticColors.of(context);
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style:
          AppTypography.bodyMedium.copyWith(color: c.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            AppTypography.bodySmall.copyWith(color: c.textDisabled),
        filled: true,
        fillColor: c.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: c.borderFocus),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
      ),
    );
  }

  Widget _buildSliderField({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String display,
    required ValueChanged<double> onChanged,
  }) {
    final c = AppSemanticColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: AppTypography.bodySmall
                  .copyWith(color: c.textSecondary),
            ),
            const Spacer(),
            Text(
              display,
              style: AppTypography.bodySmall.copyWith(
                color: c.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}