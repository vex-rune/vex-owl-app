import 'dart:async';

import 'package:langchain/langchain.dart' as lc;

/// 工具注册表。
///
/// 按 langchain_openai 的标准:
/// * 每个工具是一个 [lc.ToolSpec](schema) + 同步执行的 [lc.Tool](含执行逻辑);
/// * 暴露给 [ChatOpenAIOptions.tools] 时用 [specs];
/// * 直接执行用 [execute]。
class ToolRegistry {
  final Map<String, lc.Tool> _tools = {};

  /// 注册一个工具。
  void register({
    required String name,
    required String description,
    required Map<String, dynamic> inputJsonSchema,
    required FutureOr<String> Function(Map<String, dynamic> input) func,
  }) {
    _tools[name] = lc.Tool.fromFunction<Map<String, dynamic>, String>(
      name: name,
      description: description,
      inputJsonSchema: inputJsonSchema,
      // OpenAI 的 tool_call 已经把 JSON 解析为 Map,这里直接透传;
      // 不写 getInputFromJson 会让 Tool 默认按 StringTool 行为拆字符串,出错。
      getInputFromJson: (json) => json,
      func: (input) async => func(input),
    );
  }

  /// 列出全部 [lc.ToolSpec],给 [ChatOpenAIOptions.tools]。
  List<lc.ToolSpec> specs() =>
      _tools.values.map((t) => t as lc.ToolSpec).toList(growable: false);

  /// 按 name 执行工具。
  Future<String> execute(String name, Map<String, dynamic> args) async {
    final tool = _tools[name];
    if (tool == null) return '错误:工具 "$name" 不存在';
    try {
      final result = await tool.invoke(args);
      return result.toString();
    } catch (e) {
      return '工具 "$name" 执行失败:$e';
    }
  }
}
