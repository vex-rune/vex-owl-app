# Core 包重构计划

> 本文是 `lib/core/` 包的架构改造蓝图。与 [架构设计.md](架构设计.md)、[服务层.md](服务层.md) 配套阅读。
>
> 背景:近期在排查「工具调用记录丢失」「QuickAgent 输出混入 DB 概念」「流式片段重复 `modelName`」等问题时,系统审查 `core/` 包,**发现 4 项 P0 + 11 项 P1 问题**。本文给出分阶段、可执行的修复计划。
>
> 状态:**待执行**(落地中)。
>
> 最后更新:2026-08-25。

---

## 目录

1. [问题清单](#1-问题清单)
2. [重构总览](#2-重构总览)
3. [Phase 1 — 删除腐烂代码](#phase-1--删除腐烂代码p0-3)
4. [Phase 2 — `MessageType` 改 sealed class](#phase-2--messagetype-改-sealed-classp0-1-p1-5-6-7)
5. [Phase 3 — `Message` 字段语义单一化](#phase-3--message-字段语义单一化p0-2)
6. [Phase 4 — 错误事件单源化](#phase-4--错误事件单源化p0-4)
7. [Phase 5 — `OwlConfig` 类型安全](#phase-5--owlconfig-类型安全p1-9-10)
8. [Phase 6 — `MemoryRepository` 拆分](#phase-6--memoryrepository-拆分p1-11-12-13)
9. [Phase 7 — `Log.classifyError` 类型化](#phase-7--logclassifyerror-类型化p1-14)
10. [Phase 8 — `AgentSignal` 命名对齐](#phase-8--agentsignal-命名对齐p1-15)
11. [Phase 9 — 内部类提为顶层](#phase-9--内部类提为顶层p1-16)
12. [Phase 10 — 移除 `metadata.usage` 冗余](#phase-10--移除-metadatausage-冗余p2-22)
13. [Phase 11 — `Session.round` 文档化](#phase-11--sessionround-文档化p1-8)
14. [执行节奏与验证](#执行节奏与验证)

---

## 1. 问题清单

| 级别 | 编号 | 主题 | 概述 |
|------|------|------|------|
| **P0** | #1 | `MessageType` 枚举混合多种语义 | 内容形态(text/thinking/error)+ 事件形态(toolCall/plan)+ 状态标记(system)混在一起 |
| **P0** | #2 | `Message.content` 一名六义 | 同字段在 6 种 role+type 组合下表达 6 种含义(text/plan 名/tool output/思考/错误/...) |
| **P0** | #3 | `PlanItem` 体系腐烂 | DB 表 / 字段已写但无产出 / 消费代码,持续腐烂 |
| **P0** | #4 | 错误事件双层定义 | `AgentFinishReason.error` 与 `MessageType.error` 重复表达同一概念 |
| **P1** | #5 | `MessageType.toolCall` 一名两职 | role=assistant vs role=tool 都用同一 type,语义模糊 |
| **P1** | #6 | `effectiveType` 防御性死代码 | `type: MessageType?` + `effectiveType` 让"穷举性"丢失 |
| **P1** | #7 | `MessageRole` 与 `MessageType` 无互斥约束 | `role=tool + type=text` 等非法组合代码不阻止 |
| **P1** | #8 | `Session.round` 含义不清 | "轮次"是回合数/模型调用/用户消息?注释误导 |
| **P1** | #9 | `OwlConfig.theme` / `memoryCompression` 用 String | 拼错运行时才崩 |
| **P1** | #10 | `OwlConfig.apiKey` 哨兵字符串 `'????'` | 反模式,应改为 `String?` |
| **P1** | #11 | `MemoryRepository` 职责混乱 | IO + 业务编排(query / buildContextPrompt)混 |
| **P1** | #12 | `MemoryRepository.query(scope, keyword)` scope 是 String | 应该用 `MemoryScope` 枚举 |
| **P1** | #13 | `buildContextPrompt` 暴露在仓储层 | 应放 Service 层 |
| **P1** | #14 | `Log.classifyError` 用字符串匹配 | `s.contains('SocketException')` 脆弱 |
| **P1** | #15 | `AgentSignal` / `AgentFinishReason` 后缀风格不统一 | `completed` vs `complete` / `errored` vs `error` |
| **P1** | #16 | 内部类下划线前缀影响可读性 | `_QuickAgentRun` / `_QuickAgentSubscription` 应提为顶层 + `@visibleForTesting` |
| **P2** | #22 | `metadata.usage` 与 `AgentFinish.usage` 重复 | 流式片段上 usage 不完整,可移除 |

---

## 2. 重构总览

| 指标 | 值 |
|------|----|
| 涉及文件 | **17 个** |
| 总步骤 | **56 步** |
| DB schema 影响 | 4 处(删列 + 加列 + 重新生成 `.g.dart`) |
| 风险等级 | **中高**(涉及 sealed class 重构 + DB schema 变更) |

### 重构顺序原则

按"**从底层到上层**":

```
数据模型(sealed class) → 仓储接口 → Service 翻译层 → Agent emit 形态 → Log 工具
```

理由:模型先定,后面所有代码按新模型编译;仓储接口随模型改;Service 翻译层、Agent emit 层同步适配;最后修横切关注点。

### 建议分 3 轮执行

| 轮 | 包含 Phase | 风险 | 收益 |
|----|------------|------|------|
| 第 1 轮 | Phase 1 + 4 + 8 + 10 + 11 | 低 | 快速见成果,纯删除 / 注释 |
| 第 2 轮 | Phase 5 + 6 + 7 + 9 | 中 | 类型 / 拆分 / 工具 |
| 第 3 轮 | Phase 2 + 3 | **高** | sealed class + DB 迁移,需全量回归 |

每轮结束跑 `flutter analyze` + `flutter run` 验证。

---

## Phase 1 — 删除腐烂代码(P0 #3)

**目标**:`MessageType.plan` / `Message.planItems` / `PlanItem` 类 / `PlanItemStatus` 枚举 / DB `planItems` 列全部清除。

| 步骤 | 文件 | 改动 |
|------|------|------|
| 1.1 | `lib/core/model/message.dart` | 删除 `class PlanItem` + `enum PlanItemStatus` |
| 1.2 | `lib/core/model/message.dart` | `Message.planItems` 字段删除 |
| 1.3 | `lib/core/model/message.dart` | `MessageType.plan` 枚举值删除 |
| 1.4 | `lib/data/storage/database/message_store.dart` | 删除 `TextColumn get planItems` |
| 1.5 | `lib/data/repository/drift_message_repository.dart` | `_toMessage` 中删除 `planItems` 字段处理 |
| 1.6 | `lib/data/repository/drift_message_repository.dart` | `_fromMessage` 序列化中删除 `planItems` |
| 1.7 | (本地) | `flutter pub run build_runner build --delete-conflicting-outputs` 重新生成 `.g.dart` |

**验证**:`grep "PlanItem\|planItems\|MessageType.plan"` → 0 命中。

---

## Phase 2 — `MessageType` 改 sealed class(P0 #1, P1 #5, #6, #7)

### 2.1 设计

```dart
sealed class MessageKind {}
final class MessageText extends MessageKind { final String content; }
final class MessageThinking extends MessageKind { final String content; }
final class MessageToolCall extends MessageKind { final ToolCallRecord call; }
final class MessageToolResult extends MessageKind { final ToolCallRecord result; }
final class MessageError extends MessageKind { final String message; }
final class MessageSystem extends MessageKind { final String prompt; }
```

设计要点:

- `MessageRole`(user / assistant / tool / system)保留不变,仍描述"对话角色"
- `MessageKind` 描述"内容形态",二者组合表达"这是什么事件"(e.g. `assistant + MessageToolCall` = assistant 决定调工具)
- 不再有 `MessageType.toolCall` 一名两职 —— `MessageToolCall` / `MessageToolResult` 各自明确

### 2.2 实施步骤

| 步骤 | 文件 | 改动 |
|------|------|------|
| 2.1 | `lib/core/model/message.dart` | 删除 `enum MessageType`,新建 `sealed class MessageKind` + 6 个 `final class` subtype |
| 2.2 | `lib/core/model/message.dart` | `Message.type: MessageType?` 改为 `kind: MessageKind`(非空) |
| 2.3 | `lib/core/model/message.dart` | 删除 `effectiveType` getter |
| 2.4 | `lib/core/model/message.dart` | `Message.role` 字段保留(仍是 user / assistant / tool / system) |
| 2.5 | `lib/core/model/message.dart` | 加工厂方法 `Message.text(role, content, ...)` / `Message.toolCall(role, record)` 等 |
| 2.6 | `lib/data/storage/database/message_store.dart` | 把 `type: text()` 列删除 —— 改由 `kindType: text() + kindJson: text()` 两列承载 sealed class 序列化 |
| 2.7 | `lib/data/storage/database/message_store.dart` | 增加 `kindType` / `kindJson` 列(`kindType` 是 `text()` 存 `"text"` / `"thinking"` / `"toolCall"` 等;`kindJson` 是 JSON 字符串,存 sealed class 内部数据) |
| 2.8 | `lib/data/repository/drift_message_repository.dart` | `_toMessage` 中改为按 `kindType` + `kindJson` 反序列化为 sealed class |
| 2.9 | `lib/data/repository/drift_message_repository.dart` | `_fromMessage` 中改为 sealed class → `kindType` + `kindJson` 序列化 |
| 2.10 | (本地) | 重新跑 build_runner |

**验证**:`grep "MessageType\."` → 全部 `MessageKind` 取代;`grep "effectiveType"` → 0。

---

## Phase 3 — `Message` 字段语义单一化(P0 #2)

### 3.1 字段映射

| 当前字段 | 问题 | 改为 |
|----------|------|------|
| `Message.content: String` | 一名六义 | 移除,改为 `MessageKind` 各自的 `content` / `message` / `prompt` / `ToolCallRecord` |
| `Message.toolCalls: List<ToolCallRecord>?` | 表达"toolCall 关联的工具"模糊 | 移除(已并入 `MessageKind`) |
| `Message.thinkingContent: String?` | 同上 | 移除(已并入 `MessageKind`) |
| `Message.streaming: bool` | 表达"是否还在生成" | 保留(仍有价值) |
| `Message.id` / `conversationId` / `createdAt` / `turnId` | DB 主键 / 外键 / 时间戳 / 聚合键 | 保留 |

### 3.2 实施步骤

| 步骤 | 文件 | 改动 |
|------|------|------|
| 3.1 | `lib/core/model/message.dart` | `Message.content: String required` 改为由 `kind` 内的字段承载 |
| 3.2 | `lib/core/model/message.dart` | `Message.toolCalls` / `thinkingContent` 删除 |
| 3.3 | `lib/application/conversation/conversation_service.dart` | 所有构造 `Message(...)` 改为 `Message.text(role, content, ...)` / `Message.toolCall(record)` 工厂 |
| 3.4 | `lib/application/conversation/conversation_service.dart` | `_toToolCallMessage` / `_toStreamingMessage` / `_toThinkingMessage` 等翻译函数重写,改为读 `kind` 子字段 |
| 3.5 | `lib/core/agent/quick_agent.dart` | `_toLcMessage` 已按 `AgentResponse` subtype switch(本轮前期已做完),不动 |
| 3.6 | `lib/presentation/pages/home_page.dart` | `_upsertMessage` 仍接受 `Message`(整体),不动 — 但读 `msg.content` 改为 `msg.kind` 下的字段 |

**验证**:全文 `grep "msg.content\|\.content,"` 排查所有调用方;`grep "toolCalls: "`:仅出现在 `MessageKind` 序列化场景。

---

## Phase 4 — 错误事件单源化(P0 #4)

### 4.1 错误单源化方案

`AgentFinish.errorMessage` → DB `Message(kind: MessageError(message: ...))`,只一层定义。

### 4.2 实施步骤

| 步骤 | 文件 | 改动 |
|------|------|------|
| 4.1 | `lib/application/conversation/conversation_service.dart` | `_toFinishErrorMessage` 改为构造 `Message(kind: MessageError(...))` |
| 4.2 | `lib/application/conversation/conversation_service.dart` | `markError` 流程不再构造 `type=error`,而是 `Message(kind: MessageError(...))` 直接 append |
| 4.3 | `lib/core/model/message.dart` | `MessageRole.assistant + kind=MessageError` 作为唯一表达"这一回合失败"的方式 |

**验证**:`grep "MessageType\.error\|MessageError"` → 0 旧引用;只有 `MessageError` 类。

---

## Phase 5 — `OwlConfig` 类型安全(P1 #9, #10)

### 5.1 实施步骤

| 步骤 | 文件 | 改动 |
|------|------|------|
| 5.1 | `lib/core/model/owl_config.dart` | `theme: String` 改为 `AppTheme` 枚举 |
| 5.2 | `lib/core/model/owl_config.dart` | `memoryCompression: String` 改为 `MemoryCompressionMode` 枚举 |
| 5.3 | `lib/core/model/owl_config.dart` | `apiKey: String` 改为 `apiKey: String?`,删 `apiKey: '????'` 哨兵 |
| 5.4 | `lib/core/model/owl_config.dart` | `factory OwlConfig.empty()` 删除;改用 `OwlConfig.initial()` 只填**安全默认值**,`apiKey` 留 null |
| 5.5 | `lib/data/repository/drift_config_repository.dart` | `fromJson` / `_toStorageMap` 适配新枚举 + nullable apiKey |
| 5.6 | (全文 grep) | 找 `OwlConfig.empty()` 调用方,改写为 `OwlConfig.initial()` |
| 5.7 | (全文 grep) | 找 `config.apiKey == '????'` 判断,改写为 `config.apiKey == null \|\| config.apiKey.isEmpty` |

**验证**:`grep "'????'"` → 0;`grep "config.theme == "` → 0(改为 `== AppTheme.system`)。

---

## Phase 6 — `MemoryRepository` 拆分(P1 #11, #12, #13)

### 6.1 拆分方案

```
MemoryFileRepository (IO only) → MemoryQueryService (业务编排)
                                       │
                                       ├─ query(scope, keyword)
                                       └─ buildContextPrompt(conversationId)
```

### 6.2 实施步骤

| 步骤 | 文件 | 改动 |
|------|------|------|
| 6.1 | `lib/core/model/memory.dart` | `MemoryQueryResult` 类保留 |
| 6.2 | `lib/core/model/memory.dart` | `MemoryScope.fileName` 中的 `'history'` 占位字符串改名为 `'history/'`(目录标识) |
| 6.3 | `lib/core/repository/memory_repository.dart` | 重命名为 `memory_file_repository.dart`,只保留 7 个 IO 方法 |
| 6.4 | `lib/core/repository/memory_repository.dart` | `query(String scope, ...)` 改 `query(MemoryScope scope, ...)` |
| 6.5 | (新建) `lib/core/repository/memory_query_service.dart` | 新建 `MemoryQueryService`,构造注入 `MemoryFileRepository`,承载 `query()` + `buildContextPrompt()` |
| 6.6 | `lib/application/providers.dart` | `memoryRepositoryProvider` 拆为 `memoryFileRepositoryProvider` + `memoryQueryServiceProvider` |
| 6.7 | (全文 grep) | 找 `memoryRepositoryProvider`,改调用方分别 inject |

**验证**:`grep "buildContextPrompt"` → 只在 `MemoryQueryService`;`grep "Future<String> readProfile"` → 只在 `MemoryFileRepository`。

---

## Phase 7 — `Log.classifyError` 类型化(P1 #14)

### 7.1 实施步骤

| 步骤 | 文件 | 改动 |
|------|------|------|
| 7.1 | `lib/core/util/log.dart` | 删 `classifyError` 整段实现 |
| 7.2 | `lib/core/util/log.dart` | 改写为用 `is SocketException` / `is HttpException` / 自定义 `ApiError` 子类判断 |
| 7.3 | (新建 `lib/core/util/api_error.dart`) | 新建 `ApiError` + 子类 `ApiAuthError` / `ApiRateLimitError` / `ApiServerError`,让 LangChain 抛错时统一包装 |
| 7.4 | (全文 grep) | 找 `classifyError` 调用方,改用 `is` 链 |

**验证**:`grep "contains.*SocketException"` → 0(已替换为 `is`)。

---

## Phase 8 — `AgentSignal` 命名对齐(P1 #15)

### 8.1 实施步骤

| 步骤 | 文件 | 改动 |
|------|------|------|
| 8.1 | `lib/core/agent/agent.dart` | `enum AgentSignal { completed, cancelled, errored }` 改为 `AgentSignal { complete, cancelled, error }`(与 `AgentFinishReason` 对齐) |
| 8.2 | (全文 grep) | 找 `_terminate(AgentSignal.completed)`,改写为 `_terminate(AgentSignal.complete)` |
| 8.3 | (全文 grep) | 找 `AgentSignal.errored` 改 `AgentSignal.error` |
| 8.4 | (全文 grep) | 找 `AgentSignal.cancelled` 不变 |

**验证**:`grep "AgentSignal\.\(completed\|errored\)"` → 0。

---

## Phase 9 — 内部类提为顶层(P1 #16)

### 9.1 实施步骤

| 步骤 | 文件 | 改动 |
|------|------|------|
| 9.1 | `lib/core/agent/quick_agent.dart` | `_QuickAgentRun` 提为顶层 `QuickAgentRun` |
| 9.2 | `lib/core/agent/quick_agent.dart` | `_QuickAgentSubscription` 提为顶层 `QuickAgentSubscription` |
| 9.3 | `lib/core/agent/quick_agent.dart` | 在顶部 import `package:meta/meta.dart`,加 `@visibleForTesting` 注解 |
| 9.4 | (全文 grep) | 找 `_QuickAgentRun\|_QuickAgentSubscription` → 改为新名 |

**验证**:`grep "_QuickAgent"` → 0。

---

## Phase 10 — 移除 `metadata.usage` 冗余(P2 #22)

### 10.1 实施步骤

| 步骤 | 文件 | 改动 |
|------|------|------|
| 10.1 | `lib/core/model/agent_response.dart` | `AgentResponseMetadata.usage: TokenUsage?` 删除 |
| 10.2 | `lib/core/agent/quick_agent.dart` | `metadata` 构造不再填 `usage` |
| 10.3 | (全文 grep) | 找 `metadata.usage` → 0 |

**验证**:`grep "metadata\.usage"` → 0。

---

## Phase 11 — `Session.round` 文档化(P1 #8)

### 11.1 实施步骤

| 步骤 | 文件 | 改动 |
|------|------|------|
| 11.1 | `lib/core/model/conversation.dart` | `Session.round` 注释明确为"完成助手回复的次数"(每次 `bumpRound` +1) |
| 11.2 | `lib/core/model/conversation.dart` | 删除"被 rename 后即视为已完成首轮"的语义(无对应代码,只是注释误导) |
| 11.3 | (全文 grep) | 找 `Session.round` 调用方,确认与新注释一致 |

**验证**:`grep "首轮\|rename 后"` → 0 误导注释。

---

## 执行节奏与验证

### 静态检查

```bash
flutter analyze --no-pub
# 期望:0 error,0 warning
```

### 编译(必须本地执行)

```bash
flutter pub run build_runner build --delete-conflicting-outputs
flutter run -d <device-id>
```

### 端到端验证点

| # | 场景 | 期望 |
|---|------|------|
| 1 | 启动 → 新建对话 → 发"今天天气" | 流式正常显示 |
| 2 | 触发工具(memory_query) | tool_call + tool_result 两行落库并显示 |
| 3 | 流式结束 | UI 终态(`streaming=false`) |
| 4 | 改坏 API key → 发送 | 显示 `MessageError` 卡片,UI 不崩 |
| 5 | 退出会话 → 重进 | 历史完整恢复,`turnId` 聚合正确 |
| 6 | Settings → 清空 apiKey → 保存 | 重启后 `apiKey == null`,UI 走"未配置"提示 |
| 7 | Settings → 改 theme 为 "xxx" 拼错 | 编译期报错(枚举校验) |
| 8 | Settings → 改 temperature → 保存 → 发消息 | 新 temperature 生效 |
| 9 | Memory:工具触发 history_query | 返回结果含 ISO8601 |
| 10 | 工具 `buildContextPrompt` 调一次 | 由 `MemoryQueryService` 提供,`MemoryFileRepository` 不含此方法 |
| 11 | 取消流 | `AgentSignal.cancelled` 触发,UI 回到 idle |
| 12 | 失败异常 → classifyError | 显示"网络异常"(基于 `is` 判断) |

### 迁移 / 兼容

- **DB 迁移**:删 `messages.planItems` 列 / 加 `messages.kindType` + `kindJson` 列 → 需要写 migration v1→v2,或允许 reset DB(开发期可接受,生产期需谨慎)。
- **JSON 兼容**:`OwlConfig.fromJson` 容忍旧数据(`theme: 'system'` → `AppTheme.system`)。

---

## 工作量评估

| Phase | 改动文件 | 主要风险 |
|-------|----------|----------|
| Phase 1 | 4 | 低(单纯删) |
| Phase 2 | 2 + DB | **高**(DB 迁移 + sealed class 影响 11 个翻译分支) |
| Phase 3 | 3 | **高**(`content` 字段影响 ~20 个引用点) |
| Phase 4 | 1 | 中(错误语义对齐) |
| Phase 5 | 2 | 中(枚举迁移) |
| Phase 6 | 3 + 新建 1 | 中(拆接口) |
| Phase 7 | 1 + 新建 1 | 低(类型判断) |
| Phase 8 | 1 + grep | 低(枚举重命名) |
| Phase 9 | 1 + grep | 低(类提升) |
| Phase 10 | 2 + grep | 低(字段删除) |
| Phase 11 | 1 | 低(注释) |

---

## 进度追踪

| Phase | 状态 | 负责人 | 完成日期 |
|-------|------|--------|----------|
| Phase 1 | ⏳ 待执行 | | |
| Phase 2 | ⏳ 待执行 | | |
| Phase 3 | ⏳ 待执行 | | |
| Phase 4 | ⏳ 待执行 | | |
| Phase 5 | ⏳ 待执行 | | |
| Phase 6 | ⏳ 待执行 | | |
| Phase 7 | ⏳ 待执行 | | |
| Phase 8 | ⏳ 待执行 | | |
| Phase 9 | ⏳ 待执行 | | |
| Phase 10 | ⏳ 待执行 | | |
| Phase 11 | ⏳ 待执行 | | |

> 状态图例:✅ 完成 | 🚧 进行中 | ⏳ 待执行 | ❌ 阻塞