/// api-configs.md 解析器。
///
/// 文件结构：
/// ```markdown
/// ---
/// version: 1
/// ---
/// # API 配置
///
/// ## ⚙️ 配置 1（默认）
/// - id：1
/// - 配置名称：我的 MINIMAX
/// - 模型：MiniMax-M3
/// - 端点：https://api.minimax.cn/v1
/// - API Key：encrypted:xxx
/// - 温度：0.7
/// - Top-P：1.0
/// - 最大 Token：4096
/// - 最大完成 Token：4096
/// - 启用思考：off
/// - 是否默认：on
/// - Provider：minimax
///
/// ## ⚙️ 配置 2
/// ...
/// ```
///
/// 负责 [ApiConfigs] ↔ Markdown 双向转换，解析失败时静默回退。
library;

import '../../core/model/api_config.dart';
import '../../core/model/api_configs.dart';
import 'markdown_writer.dart';

class ApiConfigsParser {
  /// 段落标题前缀：识别「`## ⚙️ 配置 N`」段落
  static final _sectionPattern = RegExp(r'^⚙️\s*配置\s*(\d+)(.*)$');

  /// Markdown → [ApiConfigs]
  static ApiConfigs parse(String content) {
    final (frontMatter, body) = MarkdownParser.parseFrontMatter(content);
    final sections = MarkdownParser.parseSections(body);

    final configs = <ApiConfig>[];
    for (final s in sections) {
      final m = _sectionPattern.firstMatch(s.title);
      if (m == null) continue;
      configs.add(_parseConfig(s));
    }

    return ApiConfigs(version: frontMatter.version, configs: configs);
  }

  /// [ApiConfigs] → Markdown
  static String serialize(ApiConfigs data) {
    final frontMatter = FrontMatter(version: data.version);

    final sections = <MarkdownSection>[];
    for (var i = 0; i < data.configs.length; i++) {
      final cfg = data.configs[i];
      final section = MarkdownSection('⚙️ 配置 ${cfg.id ?? (i + 1)}${cfg.isDefault ? '（默认）' : ''}')
        ..set('id', '${cfg.id ?? (i + 1)}')
        ..set('配置名称', cfg.configName)
        ..set('模型', cfg.modelName)
        ..set('端点', cfg.apiEndpoint)
        ..set('API Key', cfg.apiKey)
        ..set('温度', _trimZero(cfg.temperature))
        ..set('Top-P', _trimZero(cfg.topP))
        ..set('最大 Token', '${cfg.maxTokens}')
        ..set('最大完成 Token', '${cfg.maxCompletionTokens}')
        ..set('启用思考', _bool(cfg.thinkingEnabled))
        ..set('是否默认', _bool(cfg.isDefault))
        ..set('Provider', cfg.providerId);
      sections.add(section);
    }

    return MarkdownWriter.serialize(
      frontMatter: frontMatter,
      sections: sections,
      title: 'API 配置',
    );
  }

  static String defaultContent() => serialize(const ApiConfigs());

  // ── 内部解析辅助 ──

  static ApiConfig _parseConfig(MarkdownSection s) {
    final id = _toInt(s.get('id'), 0);
    final isDefault = _toBool(s.get('是否默认'));

    return ApiConfig(
      id: id > 0 ? id : null,
      configName: s.get('配置名称') ?? '',
      modelName: s.get('模型') ?? '',
      apiEndpoint: s.get('端点') ?? '',
      apiKey: s.get('API Key') ?? '',
      temperature: _toDouble(s.get('温度'), 0.7),
      topP: _toDouble(s.get('Top-P'), 1.0),
      maxTokens: _toInt(s.get('最大 Token'), 4096),
      maxCompletionTokens: _toInt(s.get('最大完成 Token'), 4096),
      thinkingEnabled: _toBool(s.get('启用思考')),
      isDefault: isDefault,
      providerId: s.get('Provider') ?? 'auto',
    );
  }

  static bool _toBool(String? value) {
    final v = value?.trim().toLowerCase();
    return v == 'on' || v == 'true' || v == 'yes' || v == '1';
  }

  static String _bool(bool v) => v ? 'on' : 'off';

  static int _toInt(String? value, int fallback) {
    return int.tryParse(value?.trim() ?? '') ?? fallback;
  }

  static double _toDouble(String? value, double fallback) {
    return double.tryParse(value?.trim() ?? '') ?? fallback;
  }

  /// 去掉 double 末尾的 `.0`（让序列化输出更干净）
  static String _trimZero(double v) {
    final s = v.toString();
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }
}