/// 数据层模块导出文件
///
/// 统一导出数据层的所有子模块，包括：
/// - 仓库接口与实现（i_wiki_repository、wiki_repository）
/// - Agent 定义（chat_agent_spec、image_agent_spec）
/// - LLM Provider 抽象与注册表（llm、provider_registry）
///
/// 自 v3.0 起，全部 SQLite / Drift 已被移除，所有结构化数据
/// 通过 Markdown 文件持久化到 `wiki/` 目录下。
export 'repository/i_wiki_repository.dart';
export 'repository/wiki_repository.dart';
export 'agents/agent_spec.dart';
export 'agents/chat_agent_spec.dart';
export 'agents/image_agent_spec.dart';
export 'llm/llm.dart';
