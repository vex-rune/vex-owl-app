import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/model/owl_config.dart';
import '../theme/app_theme.dart';

/// 设置页:模型配置 + 应用设置 + 关于。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late TextEditingController _apiKeyCtrl;
  late TextEditingController _baseUrlCtrl;
  late TextEditingController _modelCtrl;
  late TextEditingController _bochaApiKeyCtrl;
  bool _obscureKey = true;
  bool _obscureBochaKey = true;
  bool _loading = true;
  double _currentTemperature = 0.7;

  @override
  void initState() {
    super.initState();
    _apiKeyCtrl = TextEditingController();
    _baseUrlCtrl = TextEditingController();
    _modelCtrl = TextEditingController();
    _bochaApiKeyCtrl = TextEditingController();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final repo = await ref.read(configRepositoryProvider.future);
      final config = await repo.load();
      if (!mounted) return;
      _apiKeyCtrl.text = config.apiKey;
      _baseUrlCtrl.text = config.baseUrl;
      _modelCtrl.text = config.model;
      _bochaApiKeyCtrl.text = config.bochaApiKey;
      _currentTemperature = config.temperature;
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _baseUrlCtrl.dispose();
    _modelCtrl.dispose();
    _bochaApiKeyCtrl.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _apiKeyCtrl.text.trim().isNotEmpty && _baseUrlCtrl.text.trim().isNotEmpty;

  bool get _looksLikeUrl =>
      _baseUrlCtrl.text.trim().startsWith('http://') ||
      _baseUrlCtrl.text.trim().startsWith('https://');

  Future<void> _save() async {
    if (!_isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API Key 与 Base URL 不能为空')),
      );
      return;
    }
    if (!_looksLikeUrl) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Base URL 需以 http:// 或 https:// 开头')),
      );
      return;
    }
    final repo = await ref.read(configRepositoryProvider.future);
    // 取旧值作为 fallback,避免误清空(用户只改 model 不动 bocha 时)。
    final old = await repo.load();
    final config = OwlConfig(
      apiKey: _apiKeyCtrl.text.trim(),
      baseUrl: _baseUrlCtrl.text.trim(),
      model: _modelCtrl.text.trim().isNotEmpty
          ? _modelCtrl.text.trim()
          : 'minimax-M3',
      maxRounds: 5,
      theme: 'system',
      memoryCompression: 'off',
      bochaApiKey: _bochaApiKeyCtrl.text.trim(),
      temperature: _currentTemperature,
    );
    // 若 OwlConfig 缺省导致 bochaApiKey 仍为 '',沿用旧值(用户未输入 = 保留)。
    final resolvedBochaKey =
        config.bochaApiKey.isNotEmpty ? config.bochaApiKey : old.bochaApiKey;
    final config2 = config.copyWith(bochaApiKey: resolvedBochaKey);
    await repo.save(config2);
    // 触发下游重建:ChatOpenAI / quickAgent 都会拿到新 apiKey / model / temperature。
    ref.invalidate(configChangesProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('配置已保存')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('设置')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.space3),
        children: [
          const _SectionHeader(title: 'AI 模型'),
          _SettingItem(
            label: 'Model',
            child: TextField(
              controller: _modelCtrl,
              decoration: const InputDecoration(hintText: 'minimax-M3'),
            ),
          ),
          _SettingItem(
            label: 'API Key',
            child: TextField(
              controller: _apiKeyCtrl,
              obscureText: _obscureKey,
              decoration: InputDecoration(
                hintText: '请输入 API Key',
                suffixIcon: IconButton(
                  icon: Icon(_obscureKey
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined),
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                ),
              ),
            ),
          ),
          _SettingItem(
            label: 'Base URL',
            child: TextField(
              controller: _baseUrlCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: 'https://api.example.com',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space4, AppTheme.space2, AppTheme.space4, AppTheme.space4,
            ),
            child: FilledButton(
              onPressed: _save,
              child: const Text('保存'),
            ),
          ),
          const _SectionHeader(title: '联网搜索'),
          _SettingItem(
            label: '博查 API Key(可选)',
            child: TextField(
              controller: _bochaApiKeyCtrl,
              obscureText: _obscureBochaKey,
              decoration: InputDecoration(
                hintText: '留空 = 关闭联网搜索',
                suffixIcon: IconButton(
                  icon: Icon(_obscureBochaKey
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined),
                  onPressed: () =>
                      setState(() => _obscureBochaKey = !_obscureBochaKey),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.space4,
            ),
            child: Text(
              '在 bocha.cn 申请 API Key 后填入,'
              '模型即可在需要时调用 bocha_web_search 联网搜索。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space4, AppTheme.space2, AppTheme.space4, AppTheme.space4,
            ),
            child: FilledButton(
              onPressed: _save,
              child: const Text('保存'),
            ),
          ),
          const _SectionHeader(title: '关于'),
          _SettingItem(
            label: '版本',
            child: Text('v0.1.0', style: theme.textTheme.bodyMedium),
          ),
          _SettingItem(
            label: '开源协议',
            child: Text('MIT', style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space4, AppTheme.space4, AppTheme.space4, AppTheme.space2,
      ),
      child: Text(
        title,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _SettingItem extends StatelessWidget {
  final String label;
  final Widget child;
  const _SettingItem({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space4,
        vertical: AppTheme.space1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: AppTheme.space1,
              bottom: AppTheme.space1,
            ),
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          child,
          const SizedBox(height: AppTheme.space2),
        ],
      ),
    );
  }
}
