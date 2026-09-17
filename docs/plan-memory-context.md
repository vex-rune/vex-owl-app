# 计划：LLM-Wiki 知识库结构规范

**文档版本**：5.0
**修订日期**：2026 年 09 月 17 日
**所属项目**：Owl（vex-owl-app）
**状态**：待实施

---

## 0. 文档目的

定义 Owl 项目的 **LLM-Wiki 本地知识库结构规范**，作为整个项目的存储基石：

- `wiki/` 目录是**唯一被代码写入的知识容器**
- 所有 Wiki 文件使用**统一 front-matter** 规范
- 通过 `.meta/wiki.lock` 防止并发写冲突
- 文件命名稳定（用 UUID / entityId）便于跨文档 `[[wikilink]]` 引用

---

## 1. 根目录结构

```
<应用文档目录>/
└── .owl/                          ← App 根目录（隐藏目录）
    └── wiki/                      ← ★ 唯一可编辑目录（代码只能写入这里）
        │
        ├── .meta/                 ← 【程序私有目录，用户不直接编辑】
        │   ├── wiki.lock          ← 文件锁，防止 Ingest/Compressor 并发写 md
        │   └── export-meta.json   ← 元数据镜像（数据库导出备份）
        │
        ├── schema.md              ← 不可变，初始化写入；用户只读，程序永不修改
        ├── index.md               ← 【人类可读目录】仅自动增量追加，不作为主索引
        ├── profile.md             ← 用户画像；LLM 黑名单，仅用户 / Ingest 可修改
        │
        ├── todos/                 ← ★ 改成目录，一个 todo 一个 md，解决并发覆盖！
        │   ├── todo-{uuid}.md
        │   └── .archive/
        │
        ├── sessions/              ← ★ 短期记忆摘要 + 近期消息（Compressor 写）
        │   ├── {sessionId}.md
        │   └── .archive/          ← 归档过期会话
        │
        └── concepts/              ← ★ 长期知识（Ingest 写）
            └── {entityId}.md
```

---

## 2. `.meta/` 私有目录

> 用户和 LLM **禁止**读写此目录。所有访问走 `MetaService`。

### 2.1 `wiki.lock` 文件锁

```json
{
  "version": 1,
  "lock_id": "uuid-v4",
  "owner": "ingest|compressor|user_edit|export",
  "acquired_at": "2026-09-17T10:30:00Z",
  "expires_at": "2026-09-17T10:35:00Z",
  "operation": "ingest_session_abc123"
}
```

**规则**：
- 任何写入 Wiki 文件的操作前必须 `acquire lock`（带 TTL，5 分钟）
- 写入完成后立即 `release`
- TTL 过期自动失效（防崩溃遗留死锁）
- 同一时刻只允许一个写者；多个读者可并发

### 2.2 `export-meta.json` 元数据镜像

```json
{
  "version": 1,
  "exported_at": "2026-09-17T10:30:00Z",
  "owl_version": "0.4.0",
  "schema_version": 1,
  "stats": {
    "profile": { "exists": true, "size_bytes": 1024, "updated_at": "..." },
    "todos_active": 5,
    "todos_archived": 12,
    "sessions_active": 3,
    "sessions_archived": 8,
    "concepts": 27
  },
  "file_index": {
    "todos": ["todo-aaa.md", "todo-bbb.md", "..."],
    "sessions": ["abc-123.md", "..."],
    "concepts": ["concept-iot.md", "..."]
  }
}
```

**用途**：导出整个 `.owl/` 时快速比对、校验完整性、版本追踪。

---

## 3. `schema.md`（不可变）

初始化时由 App 写入；用户可读但不可编辑，程序**永不修改**。

文件内容保持 Owl 默认规则（LLM Wiki 编写规范），与 `lib/data/repository/wiki_repository.dart` 中 `_defaultSchema` 常量一致。

---

## 4. `index.md`（人类可读目录）

> **不是主索引**，仅作为展示用，每次 Ingest/Lint 自动增量追加，**不允许删改历史条目**。

**格式**：

```markdown
# Wiki 全局目录

> 本文件由程序自动维护，展示用。每次 Ingest/Lint 增量追加，不删除历史。
> 主索引逻辑走 SQLite metadata（如 concepts/todos 的列表查询）。

---

## profile（用户画像）

- [[profile]] · 用户画像 · 个人基础信息与偏好

---

## concepts（长期知识）

- [[concept-iot]] · 物联网架构 · 多租户后端设计 · 2026-09-15
- [[concept-flutter]] · Flutter 笔记 · 状态管理与性能优化 · 2026-09-16
- [[concept-vex]] · VEX 项目 · 后端架构演进 · 2026-09-17

---

## sessions（短期记忆摘要）

- [[abc-123]] · 2026-09-16 记忆系统设计
- [[def-456]] · 2026-09-17 Ingest 流程优化

---

## todos（待办）

<!-- todos 增量小，不在此展示，详见 todos/ 目录 -->
共 5 项活跃 · 12 项已归档
```

**重要**：`index.md` 是只读的（程序增量 append），**不是数据源**。  
UI 列表的真实数据来源是 **SQLite metadata 表** + `listPages()` 扫描。

---

## 5. `profile.md`（LLM 黑名单）

```markdown
---
title: 用户画像
description: 个人基础信息、偏好、关注点
weight: 1
---

（用户画像正文，Markdown）
```

**权限**：
- 用户可编辑
- Ingest 可写入
- LLM 工具 ❌ 黑名单
- 其他写入前必须 validate `WikiPageSchema`

---

## 6. `todos/` 目录 ★ 改为多文件

> 解决 `todos.md` 单文件的并发覆盖问题。每条 todo 独立一个 md 文件。

### 6.1 文件命名

```
todos/todo-{uuid}.md
```

UUID v4，例如：`todo-a3f7e9b1-2c4d-4e5f-8a9b-1c2d3e4f5a6b.md`

**为什么不用时间戳？** 时间戳可读但易冲突（毫秒级并发）；UUID 全局唯一、不可猜测、便于引用。

### 6.2 单文件 front-matter 标准

```markdown
---
title: 修复登录页崩溃
description: 登录页在 Android 13 上闪退，需排查 SQLite 加密兼容
status: pending          # pending | in_progress | done | cancelled
priority: high           # low | medium | high | urgent
weight: 10               # 排序权重，UI 默认按 weight 升序
created_at: 2026-09-15T10:00:00Z
updated_at: 2026-09-16T14:30:00Z
due_at: 2026-09-20T00:00:00Z   # 可选
completed_at: null             # 完成时填写
tags: [bug, android, urgent]
todo_id: a3f7e9b1-2c4d-4e5f-8a9b-1c2d3e4f5a6b
---

# 修复登录页崩溃

## 背景

登录页在 Android 13 上偶发闪退，怀疑与 SQLite 加密兼容有关。

## 子任务

- [ ] 复现闪退路径
- [ ] 查看 logcat 错误堆栈
- [ ] 升级 sqflite_cipher 版本

## 关联

- [[concept-flutter]] · SQLite 加密笔记
- [[abc-123]] · 2026-09-14 调试 session

## 备注

> 创建：2026-09-15 | 来源：用户反馈
```

### 6.3 front-matter 字段定义

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `title` | string | ✓ | 任务标题，展示给用户 |
| `description` | string | △ | 一句话摘要，用于 index.md / 列表预览 |
| `status` | enum | ✓ | `pending` / `in_progress` / `done` / `cancelled` |
| `priority` | enum | ✓ | `low` / `medium` / `high` / `urgent` |
| `weight` | int | ✓ | 排序权重（默认 100），UI 按升序展示 |
| `created_at` | ISO8601 | ✓ | 创建时间 |
| `updated_at` | ISO8601 | ✓ | 最后修改时间 |
| `due_at` | ISO8601 | △ | 截止时间（可选） |
| `completed_at` | ISO8601 | △ | 完成时间（status=done 时填写） |
| `tags` | string[] | △ | 标签列表，用于筛选 |
| `todo_id` | UUID | ✓ | 与文件名一致，便于程序引用 |

### 6.4 归档

- 完成后（或取消后）移动到 `todos/.archive/`
- 文件保留 front-matter 不变，加 `archived_at` 字段
- 程序不删除，保留历史

### 6.5 并发写入策略

每个 todo 是独立文件，**天然支持并发**：
- LLM 可同时 `append_file` 两个不同 todo
- 不同用户的客户端可同时修改不同 todo
- 同一 todo 的并发：走 `.meta/wiki.lock` 串行化

---

## 7. `sessions/` 短期记忆 ★ 改为 sessionId

### 7.1 文件命名

```
sessions/{sessionId}.md
sessions/.archive/{sessionId}.md
```

**为什么用 sessionId 而非 `{date}-{name}`？**
- 重命名会话时不需要改文件名（避免链接失效）
- 文件名稳定，便于其他文档 `[[sessionId]]` 引用
- sessionId 在 SQLite 中也是主键，统一一致

### 7.2 单文件 front-matter 标准

```markdown
---
title: 2026-09-16 记忆系统设计
description: 讨论 Wiki 存储方案与 LLM 压缩策略
session_id: abc-123-def
archived: false
created_at: 2026-09-16T14:30:00Z
updated_at: 2026-09-16T16:45:00Z
message_count: 24
weight: 5
tags: [design, architecture]
---

# 2026-09-16 记忆系统设计

## 摘要

本次会话确定了 Owl 项目的核心存储方案：
1. SQLite 存配置与会话元数据
2. Markdown 存知识库内容
3. 文件锁防止并发写冲突

## 关键结论

- 配置文件 → SQLite（结构化、可加密）
- 知识文件 → Markdown（可读、可导出）
- 会话临时上下文 → SQLite `session_messages` 表

## 关联

- [[profile]]
- [[concept-flutter]]
- [[todo-a3f7e9b1]]

---

## 最近对话（最多 20 条，超出触发压缩）

### [2026-09-16 14:30:00] user
设计一个记忆系统

### [2026-09-16 14:30:05] assistant
好的，我来设计...

### [2026-09-16 14:31:00] user
那 Wiki 格式怎么定？
```

### 7.3 front-matter 字段

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `title` | string | ✓ | UI 显示名（可重命名，不影响文件） |
| `description` | string | △ | 一句话摘要 |
| `session_id` | UUID | ✓ | 与文件名一致 |
| `archived` | bool | ✓ | 是否归档 |
| `created_at` | ISO8601 | ✓ | |
| `updated_at` | ISO8601 | ✓ | |
| `message_count` | int | ✓ | 当前文件中的对话条数 |
| `weight` | int | ✓ | 排序权重 |
| `tags` | string[] | △ | |

### 7.4 归档

移动到 `sessions/.archive/`，front-matter 中 `archived: true` + 加 `archived_at`。

### 7.5 压缩策略

当 SQLite 中 `session_messages` 超过 N 条（N 默认 20，可配置）：
1. Compressor 调用 LLM 生成摘要
2. 写入 `sessions/{sessionId}.md` 的 `## 摘要` 段
3. SQLite 中保留最近 N 条消息详情（详情页用）
4. 摘要成为该 session 的"长期快照"

---

## 8. `concepts/` 长期知识

### 8.1 文件命名

```
concepts/{entityId}.md
concepts/.archive/{entityId}.md   # 极少用，标记为废弃的概念
```

`entityId` 是 Ingest 生成的稳定 ID（如：`concept-iot`、`concept-flutter-state`）。

### 8.2 单文件 front-matter 标准

```markdown
---
title: 物联网多租户架构
description: VEX 项目的 IoT 后端架构设计笔记
weight: 10
entity_id: concept-iot
created_at: 2026-09-10T10:00:00Z
updated_at: 2026-09-16T14:00:00Z
tags: [architecture, iot, backend, vex]
related: [[concept-flutter]] [[session-abc-123]]
---

# 物联网多租户架构

## 核心设计

### 多租户隔离

- 行级隔离：`tenant_id` 字段
- 数据库隔离：每租户独立 schema
- 应用隔离：每租户独立 deployment

### 设备接入

- MQTT 5.0 协议
- 设备影子（Device Shadow）模式

## 关联

- [[concept-flutter]] · 前端展示层
- [[session-abc-123]] · 2026-09-10 架构讨论 session

## 来源引用

> 来源：[[session-abc-123]] · 摄入时间：2026-09-10T14:30:00Z
```

### 8.3 front-matter 字段

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `title` | string | ✓ | |
| `description` | string | ✓ | 用于 index.md / 搜索预览 |
| `weight` | int | ✓ | 排序权重 |
| `entity_id` | string | ✓ | 与文件名一致 |
| `created_at` | ISO8601 | ✓ | |
| `updated_at` | ISO8601 | ✓ | |
| `tags` | string[] | △ | |
| `related` | wikilink[] | △ | 双向链接列表（程序维护） |

---

## 9. front-matter 通用规范

### 9.1 强制字段（所有 Wiki 文件）

| 字段 | 类型 | 说明 |
|---|---|---|
| `title` | string | 必填 |
| `description` | string | 必填，≤ 200 字 |
| `weight` | int | 必填，默认 100，UI 排序权重 |
| `updated_at` | ISO8601 | 必填，由 FileWriter 自动维护 |

### 9.2 文件类型专属字段

| 类型 | 专属字段 |
|---|---|
| profile | 无额外 |
| todos | `status` / `priority` / `due_at` / `todo_id` / `tags` |
| sessions | `session_id` / `archived` / `message_count` |
| concepts | `entity_id` / `tags` / `related` |

### 9.3 解析与序列化

所有 Wiki 文件的 front-matter 解析走统一服务：

```dart
class WikiFrontMatter {
  final String title;
  final String description;
  final int weight;
  final DateTime updatedAt;
  final Map<String, dynamic> extras;  // 类型专属字段

  static WikiFrontMatter parse(String yamlBlock);
  static String serialize(WikiFrontMatter fm);
}

class WikiFile {
  final WikiFrontMatter frontMatter;
  final String body;          // front-matter 之后的 Markdown 正文
  final String relativePath;  // 如 'todos/todo-xxx.md'

  static WikiFile read(String path);
  Future<void> write(WikiFile file);  // 自动维护 updated_at
}
```

### 9.4 写入规范

**`FileWriter.write(path, content)` 流程**：

```
1. 加锁 .meta/wiki.lock
2. 校验 path 必须在 wiki/ 白名单内
3. 校验 path 匹配对应 front-matter schema（todos/sessions/concepts/profile）
4. 解析现有 front-matter，合并新内容
5. 自动更新 updated_at = now()
6. 写 .tmp → fsync → rename
7. 备份原文件到 .backup/{path}.{ts}.bak
8. 追加 .audit.log（私有目录）
9. 释放锁
```

---

## 10. 权限矩阵

| 文件 / 目录 | App 读 | App 写 | LLM 工具 | 用户编辑器 |
|---|---|---|---|---|
| `.meta/` | ✅ | ✅ | ❌ | ❌ 隐藏 |
| `schema.md` | ✅ | ❌ 不可变 | ❌ | 只读 |
| `index.md` | ✅ | ✅ append | ❌ | 只读 |
| `profile.md` | ✅ | ✅ | ❌ 黑名单 | ✅ |
| `todos/` | ✅ | ✅ | ✅ 白名单 | ✅ |
| `sessions/` | ✅ | ✅ | ❌ 黑名单 | ✅ |
| `concepts/` | ✅ | ✅ | ⚠️ 仅 Ingest | ✅ |

---

## 11. 与 v3.0 的差异

| 项 | v3.0 | v5.0 |
|---|---|---|
| todos 存储 | `todos.md` 单文件 | `todos/todo-{uuid}.md` 多文件 |
| todos 并发 | 互相覆盖 | 文件级独立，可并发 |
| sessions 命名 | `{date}-{name}.md` | `{sessionId}.md` |
| 会话重命名 | 需要改文件名 | 文件名不变，仅改 front-matter |
| index.md | 主索引 | 仅展示用，主索引走 SQLite |
| 私有目录 | 无 | `.meta/`（锁 + 元数据镜像） |
| front-matter | YAML-like 简易 | 标准 `---` 块 + 必填字段 |
| 文件锁 | 无 | `.meta/wiki.lock` |
| settings 存储 | `wiki/context-settings.md` | SQLite `app_settings`（v4 引入） |
| api-configs 存储 | `wiki/api-configs.md` | SQLite `api_configs`（v4 引入） |
| 会话上下文存储 | `wiki/sessions/*.md` 内嵌 | SQLite `session_messages`（v4 引入） |

---

## 12. 与 v4.0（SQLite 拆分）的关系

v4.0 已将以下数据迁入 SQLite：

- `app_settings`：应用设置（KV 表）
- `api_configs`：API 配置（含加密 Key 的 BLOB 字段）
- `sessions`：会话元数据
- `session_messages`：会话消息（最多 20 条）

v5.0 在 v4.0 基础上进一步细化 **Wiki 文件目录结构**与 **front-matter 规范**。

**最终存储分层**：

| 数据 | 存储位置 | 原因 |
|---|---|---|
| 应用设置 | SQLite `app_settings` | KV 结构，频繁读写 |
| API 配置 | SQLite `api_configs` | 加密 BLOB，需事务 |
| 会话元数据 | SQLite `sessions` | 列表查询，按时间排序 |
| 会话消息详情 | SQLite `session_messages` | 最近 N 条明细，详情页用 |
| 会话摘要（历史快照） | `wiki/sessions/{sessionId}.md` | 长期快照，可读可编辑 |
| 用户画像 | `wiki/profile.md` | 可编辑、LTM 实体 |
| 用户待办 | `wiki/todos/todo-{uuid}.md` | 多文件，并发友好 |
| 长期知识 | `wiki/concepts/{entityId}.md` | 可导出 Obsidian |
| 知识库目录 | `wiki/index.md` | 人类可读展示 |

---

## 13. 实施清单

### Phase 1：基础（1 天）

1. 新建 `WikiFrontMatter` / `WikiFile` 模型（统一 front-matter）
2. 新建 `WikiLockService`（基于 `wiki.lock` 文件锁）
3. 新建 `WikiFrontMatterParser`（YAML 解析，可选 `yaml` 包）
4. 改造 `WikiRepository.initialize()`：创建 `.meta/` 目录 + 锁文件

### Phase 2：迁移（1 天）

1. **todos**：把 `wiki/todos.md` 拆分为 `todos/todo-{uuid}.md`
2. **sessions**：把 `{date}-{name}.md` 改名为 `{sessionId}.md`，加 `session_id` front-matter
3. **profile**：加标准 front-matter（`title`/`description`/`weight`）
4. **concepts**：加 `entity_id` front-matter
5. **index.md**：改写为「人类可读目录」展示格式

### Phase 3：写入器（1 天）

1. 新建 `WikiFileWriter`：写前加锁 + 解析 front-matter + 自动更新 `updated_at` + 原子写 + 备份
2. 改造 `WikiRepository.writePage`：走 `WikiFileWriter`
3. 新建 `.audit.log`（私有目录）

### Phase 4：UI 适配（1 天）

1. `wiki_body.dart`：列表展示新增 `weight` 排序、status badge
2. `todo` 列表组件：每条 todo 独立卡片，状态/优先级标签
3. 编辑器：实时 front-matter 编辑面板（折叠展示）

---

## 14. 修订记录

| 版本 | 日期 | 修订人 | 修订内容 |
|---|---|---|---|
| 1.0 | 2026-09-16 | AI Assistant | 初稿（SQLite + JSON 混合） |
| 2.0 | 2026-09-16 | AI Assistant | 全面迁移到本地 JSON 文件，移除 SQLite |
| 2.1 | 2026-09-16 | AI Assistant | 时间戳统一由文件系统承载，JSON 内不再冗余存储 |
| 2.2 | 2026-09-16 | AI Assistant | 新增文件工具章节（LLM 工具调用 + 用户编辑器） |
| 2.3 | 2026-09-16 | AI Assistant | 新增「数据校验与防护」章节，三层防护 + Schema 注册表 |
| 3.0 | 2026-09-16 | AI Assistant | 代码写入权限收敛到 `wiki/`：setting.json 拆分，会话 JSON 迁入 |
| 4.0 | 2026-09-17 | AI Assistant | 存储拆分：设置/会话/API 配置迁入 SQLite，知识文件保留 Markdown |
| 5.0 | 2026-09-17 | AI Assistant | **Wiki 结构 v5.0**：`todos/` 多文件化、`sessions/{sessionId}`、新增 `.meta/` 私有目录、统一 front-matter 标准 |
