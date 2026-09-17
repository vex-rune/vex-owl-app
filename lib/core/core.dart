/// 核心模块 barrel 文件。
///
/// 统一导出 core 层的所有子模块，方便外部统一引用。
library;

// 数据模型
export 'model/api_config.dart';
export 'model/api_configs.dart';
export 'model/app_settings.dart';
export 'model/llm_tool_call.dart';
export 'model/message.dart';
export 'model/session.dart';
export 'model/wiki_page.dart';
export 'model/wiki_file.dart';
export 'model/wiki_front_matter.dart';

// 提示词模板
export 'prompt/ingest_prompt.dart';
export 'prompt/query_prompt.dart';
export 'prompt/session_name_prompt.dart';
export 'prompt/memory_prompt.dart';

// 工具类
export 'util/token_counter.dart';
export 'util/talker_service.dart';
