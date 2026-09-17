/// Wiki 知识库仓库抽象接口
///
/// 封装 LLM-Wiki 文件系统的读写操作，与具体文件系统实现解耦。
///
/// v6.4 变更：
/// - 配置读写（应用设置 / Agent 配置）已迁移到 ConfigStorage，
///   本接口不再负责。
abstract class IWikiRepository {
  /// 初始化 Wiki 目录结构
  Future<void> initialize();

  /// Wiki 根目录绝对路径
  Future<String> getRootPath();

  /// 读取全局索引 index.md
  Future<String> readIndex();

  /// 覆写 index.md（完整内容）
  Future<void> writeIndex(String content);

  /// 读取指定 Wiki 页面内容（支持任意相对路径）
  Future<String> readPage(String fileName);

  /// 写入/覆盖指定 Wiki 页面（任意相对路径）
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

  // ── 多文件 Todos API ──

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

  // ── 元数据 API ──

  /// 读取 `.meta/export-meta.json`
  Future<Map<String, dynamic>?> readExportMeta();

  /// 写入 `.meta/export-meta.json`
  Future<void> writeExportMeta(Map<String, dynamic> meta);
}
