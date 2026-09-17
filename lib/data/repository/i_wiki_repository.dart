/// Wiki 知识库仓库抽象接口
///
/// 封装 LLM-Wiki 文件系统的读写操作，与具体文件系统实现解耦。
/// 默认使用 path_provider 实现（[WikiRepository]）。
///
/// 文件结构遵循 v5.0 规范：
/// - 根目录：`<appDocs>/.owl/wiki/`
/// - `.meta/` — 私有目录（wiki.lock + export-meta.json + .audit.log）
/// - `.backup/` — 自动备份目录
/// - `schema.md` — 给 LLM 的编写规则（不可变）
/// - `index.md` — 人类可读展示目录
/// - `profile.md` — 用户画像
/// - `todos/todo-{uuid}.md` — 多文件待办
/// - `sessions/{sessionId}.md` — 短期记忆 + 摘要
/// - `concepts/{entityId}.md` — 长期知识
/// - `raw/` — 原始素材（只读）
/// - `context-settings.md` — 应用设置（保留旧兼容）
/// - `api-configs.md` — API 配置（保留旧兼容）
abstract class IWikiRepository {
  /// 初始化 Wiki 目录结构（v5.0）
  ///
  /// 创建 `.owl/wiki/` 根目录及所有子目录、`.meta/` 锁目录；
  /// 首次写入 schema.md / index.md / profile.md；
  /// 如检测到旧 `llm-wiki/` 数据，执行一次性迁移。
  Future<void> initialize();

  /// Wiki 根目录绝对路径
  Future<String> getRootPath();

  /// 读取全局索引 index.md
  Future<String> readIndex();

  /// 覆写 index.md（完整内容）
  Future<void> writeIndex(String content);

  /// 读取指定 Wiki 页面内容（支持任意相对路径）
  ///
  /// [fileName] 如 `profile.md`、`todos/todo-uuid.md`、`concepts/proj-vex.md`
  Future<String> readPage(String fileName);

  /// 写入/覆盖指定 Wiki 页面（任意相对路径）
  ///
  /// 内部走 [WikiFileWriter]，含锁、原子写、备份、审计日志
  Future<void> writePage(
    String fileName,
    String content, {
    String? sourceRawPath,
  });

  /// 列出所有 Wiki 页面文件名（不含 raw/、.meta/、.backup/）
  Future<List<String>> listPages();

  /// 列出 raw/ 原始素材文件相对路径
  Future<List<String>> listRawFiles();

  /// 删除 Wiki 页面
  Future<void> deletePage(String fileName);

  /// 重命名 Wiki 页面
  Future<void> renamePage(String oldName, String newName);

  /// 检查 Wiki 页面是否存在
  Future<bool> pageExists(String fileName);

  // ── 应用设置文件（wiki/context-settings.md，保留旧兼容） ──

  Future<String?> readContextSettings();
  Future<void> writeContextSettings(String content);
  Future<bool> contextSettingsExists();

  // ── Agent 配置（每个模型 = 独立 Agent，存到 export-meta.json） ──

  /// 从 `.meta/export-meta.json.api_agents` 读取 Agent 列表
  Future<List<Map<String, dynamic>>> readAgentConfigsJson();

  /// 把 Agent 列表写回 `.meta/export-meta.json.api_agents`
  Future<void> writeAgentConfigsJson(List<Map<String, dynamic>> agents);

  // ── 多文件 Todos API（v5.0 新增） ──

  /// 列出 todos 目录下所有 todo 文件名（含活跃 + 归档）
  Future<List<String>> listTodoFiles({bool includeArchived = false});

  /// 读取单个 todo 文件（不含 front-matter 块）
  Future<String> readTodo(String fileName);

  /// 写入单个 todo 文件（含完整 front-matter）
  Future<void> writeTodo(
    String fileName,
    String content, {
    Map<String, dynamic>? frontMatterExtras,
  });

  /// 移动 todo 到归档目录
  Future<void> archiveTodo(String fileName);

  /// 取消归档（移回 todos/ 根目录）
  Future<void> unarchiveTodo(String fileName);

  /// 删除 todo 文件
  Future<void> deleteTodo(String fileName);

  // ── 元数据 API（v5.0 新增） ──

  /// 读取 `.meta/export-meta.json`
  Future<Map<String, dynamic>?> readExportMeta();

  /// 写入 `.meta/export-meta.json`
  Future<void> writeExportMeta(Map<String, dynamic> meta);
}