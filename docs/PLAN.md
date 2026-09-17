# Owl v0.2 实施计划（最终版）

## 一、技术选型

| 维度 | 选型 | 说明 |
|------|------|------|
| **Agent 框架** | **agentlib** (`^1.1.0`) | 移动端原生 AI Agent SDK，支持 AgentSpec + Runner + Subagents + Skills + Hooks |
| 路由 | **GoRouter** (`^14.6.2`) | 声明式路由，ShellRoute 做底部导航 |
| 状态管理/DI | **GetX** (`^4.6.6`) | Controller 状态管理 + 依赖注入 |
| 数据库 | **Drift** (`^2.20.0`) | 会话/配置/Token 统计持久化 |
| LLM 底层 | agentlib 内置 providers | OpenAI / Anthropic / Google + 端侧模型 |
| 文件操作 | **path_provider** | 本地 LLM-Wiki 文件系统 |

### agentlib 集成优势
- **AgentSpec + Runner**: 开箱即用的 Agent 循环引擎，流式事件驱动
- **ModelRoute**: 多模型自动路由（`preferOnDevice` + cloud fallback）
- **Subagents**: 可并行派生子 Agent（对话、生图、Wiki 搜索）
- **Skills**: Markdown 描述式技能，渐进式加载，节省 Token
- **21 个 Hooks**: 生命周期感知（低电量、网络变化、暂停恢复）
- **MCP**: 支持 HTTP/WebSocket 协议的 Model Context Protocol

### 依赖变更
- **移除**: `flutter_riverpod`, `http`, `langchain`, `langchain_openai`
- **新增**: `get: ^4.6.6`, `agentlib: ^1.1.0`
- **保留**: `go_router`, `drift`, `path_provider`, `intl`

---

## 二、架构设计（面向接口 + 分层）

### 目标分层架构
```
lib/
├── core/                          ← 核心层
│   ├── model/                     ← 数据模型（不可变）
│   │   ├── message.dart           ← Message 模型
│   │   ├── session.dart           ← Session 模型
│   │   ├── api_config.dart        ← API 配置模型
│   │   └── wiki_page.dart         ← Wiki 页面模型
│   ├── prompt/                    ← Prompt 模板
│   │   ├── query_prompt.dart      ← Query 检索 Prompt
│   │   ├── ingest_prompt.dart     ← Ingest 摄入 Prompt
│   │   └── session_name_prompt.dart
│   └── util/                      ← 工具类
│       └── token_counter.dart     ← Token 计数
│
├── data/                          ← 数据层
│   ├── repository/                ← 仓库接口 + 实现
│   │   ├── i_session_repository.dart ← 接口
│   │   ├── i_config_repository.dart  ← 接口
│   │   ├── i_wiki_repository.dart    ← 接口
│   │   ├── session_repository.dart   ← Drift 实现
│   │   ├── config_repository.dart    ← Drift 实现
│   │   └── wiki_repository.dart      ← 文件系统实现
│   ├── agents/                    ← agentlib Agent 定义
│   │   ├── owl_agents.dart        ← AgentSpec 注册中心
│   │   ├── chat_agent_spec.dart   ← 对话 Agent 定义
│   │   ├── image_agent_spec.dart  ← 生图 Agent 定义
│   │   ├── wiki_search_agent_spec.dart ← Wiki 检索 Agent
│   │   └── tools/                 ← Agent 工具实现
│   │       ├── wiki_search_tool.dart
│   │       └── image_generate_tool.dart
│   ├── database/                  ← Drift 数据库
│   │   ├── app_database.dart
│   │   └── tables/
│
├── application/                   ← 应用层（GetX Controllers）
│   ├── controller/
│   │   ├── chat_controller.dart   ← 对话 + 流式渲染
│   │   ├── wiki_controller.dart   ← Wiki 管理
│   │   ├── settings_controller.dart ← 设置
│   │   └── session_controller.dart ← 会话管理 + 自动命名
│   └── service/
│       └── init_service.dart      ← 初始化编排
│
├── presentation/                  ← 表现层
│   ├── pages/
│   │   ├── home_page.dart
│   │   ├── chat_body.dart
│   │   ├── wiki_body.dart
│   │   └── settings_body.dart
│   ├── widgets/
│   └── router/
│       └── app_router.dart        ← GoRouter + ShellRoute
│
├── design_system/                 ← 设计系统（保持不变）
├── app.dart                       ← GetMaterialApp.router
└── main.dart                      ← 入口
```

### 关键接口（面向扩展）

```dart
// 仓库接口 - 独立于实现
abstract class ISessionRepository {
  Future<Session> create(String name);
  Future<void> updateContext(String id, List<Message> context);
  Future<List<Session>> listAll();
  Future<void> delete(String id);
  Future<void> archive(String id);
}

abstract class IConfigRepository {
  Future<List<ApiConfig>> listAll();
  Future<void> save(ApiConfig config);
  Future<void> delete(int id);
  Future<void> setDefault(int id);
}

abstract class IWikiRepository {
  Future<String> readIndex();
  Future<String> readPage(String fileName);
  Future<void> writePage(String fileName, String content);
  Future<List<String>> listPages();
  Future<void> deletePage(String fileName);
}
```

### agentlib Agent 定义示例

```dart
// 对话 Agent - 基于 agentlib AgentSpec
final chatAgentSpec = AgentSpec(
  name: 'owl-chat',
  instructions: chatSystemPrompt,
  model: ModelRoute.preferOnDevice(
    onDevice: [/* 端侧模型 */],
    fallback: [OpenAIProvider(apiKey: config.apiKey)],
  ),
  tools: [wikiSearchTool],
);

// 生图 Agent - 独立 Agent
final imageAgentSpec = AgentSpec(
  name: 'owl-image',
  instructions: '根据用户描述生成图片',
  model: ModelRoute.cloudOnly([OpenAIProvider(apiKey: config.apiKey)]),
  tools: [imageGenerateTool],
);
```

---

## 三、PRD 对照检查

### ✅ 本次实现范围
| PRD 章节 | 功能 | 实现方式 |
|----------|------|---------|
| 3.2 | 首次初始化 | main.dart 启动检测 + 目录创建 |
| 3.3 | Query 对话主流程 | agentlib Runner + 流式事件 + Wiki 索引检索 |
| 3.1.1 | 数据持久化 | Drift 数据库（3 表） |
| 3.1.2 | Token 计数 + 告警 | agentlib 内置 + GetX Controller |
| 3.7 | 会话管理 | GetX SessionController + Drift |
| 3.8.1 | API 配置管理 | GetX SettingsController + Drift |
| **新增** | 会话自动命名 | agentlib Subagent（命名 Agent） |
| **新增** | 简单生图 | agentlib AgentSpec + Image Agent |

### ⏳ 延后至 v0.3
| PRD 章节 | 功能 | 原因 |
|----------|------|------|
| 3.4 | Ingest 知识摄入 | 依赖 Wiki 编辑器先完成 |
| 3.5 | Lint 知识巡检 | PRD 标注 V2 版本 |
| 3.6.1 | Wiki 浏览器（真实数据） | 需要 WikiRepository 实现 |
| 3.6.2 | Wiki Markdown 编辑器 | 复杂度高，独立迭代 |
| 3.6.3 | Wiki 备份与导出 | 依赖 Wiki 完整功能 |

---

## 四、实施顺序

### Phase 1: 基础架构
1. pubspec.yaml 依赖变更 + pub get
2. core/model/ 数据模型（Message, Session, ApiConfig, WikiPage）
3. core/prompt/ Prompt 模板
4. core/util/ Token 计数器
5. data/database/ Drift 数据库定义
6. data/repository/ 接口定义 + Drift 实现
7. data/agents/ agentlib AgentSpec 定义
8. data/agents/tools/ Agent 工具（Wiki 搜索、生图）

### Phase 2: 应用层 + 路由
9. application/controller/ GetX Controllers（4 个）
10. application/service/ 初始化编排
11. presentation/router/ GoRouter 路由配置
12. app.dart 改为 GetMaterialApp.router
13. main.dart 入口初始化

### Phase 3: 对话核心
14. ChatController 对话逻辑（Query 流程 + agentlib Runner）
15. chat_body.dart 接入真实数据（GetX Obx）
16. 流式消息渲染（打字机效果）
17. 会话自动命名（Subagent）
18. 会话列表真实数据 + 切换

### Phase 4: 扩展功能
19. 生图 Agent + 生图 UI（对话内展示图片）
20. API 配置管理 CRUD + 连通性测试
21. Token 实时预估 + 超限告警弹窗
22. 首次初始化流程 + 权限引导

### Phase 5: 收尾
23. Wiki/Settings 页面接入真实数据
24. UI/UX 打磨
25. PRD 文档更新
26. 编译验证 + 修复

---

## 五、风险

| 风险 | 缓解措施 |
|------|---------|
| agentlib API 与预期不符 | 先做 PoC 验证核心流程 |
| Drift 代码生成 | Phase 1 完成后 `dart run build_runner build` |
| 端侧模型不可用 | agentlib ModelRoute 自动 fallback 到云端 |
| 本次范围过大 | 严格按 Phase 执行，Phase 3-4 核心功能优先 |
