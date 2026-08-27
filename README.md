# Owl

A new Flutter project.

## 设计概要

### 1. 产品定位

本地实时 AI 对话应用。所有对话数据、配置信息均在设备本地完成,保障数据隐私。

### 2. 核心特性

| # | 特性 | 简述 |
|---|------|------|
| 1 | 本地实时对话 | 与 AI Agent 进行即时问答,基于流式响应 |
| 2 | 单 Agent 快速问答 | 当前内置一个通用问答 Agent,负责快速问答场景 |
| 3 | 对话历史持久化 | 自动压缩历史上下文,存储到本地数据库 |
| 4 | 对话完成事件 | 每次对话结束发出单事件(含对话 ID、轮次、事件类型等元数据) |
| 5 | 模型配置 | 提供设置页配置 AI 模型的 API Key 与 baseUrl,后续可扩展 |
| 6 | 配置文件落盘 | 配置文件存放在设备根目录下的 `.vex/owl_setting.json` |

### 3. 数据存储

**本地数据库**(应用沙盒内,SQLite)

- 用途:存储对话消息、压缩后的上下文摘要、轮次、时间戳
- 触发:每轮对话结束时写入

**配置文件** `<root>/.vex/owl_setting.json`

```json
{
  "ai": {
    "provider": "minimax",
    "model": "minimax-M3",
    "apiKey": "",
    "baseUrl": ""
  }
}
```

> 说明:`<root>` 在 Android 上指向应用可访问的外部存储根(`/storage/emulated/0`)。
> 应用首次启动时若该文件不存在,会创建默认配置。

### 4. 事件契约

每次对话完成时,Agent 抛出一个对话完成事件,字段示例:

```json
{
  "conversationId": "uuid",
  "round": 3,
  "event": "conversation.completed",
  "timestamp": "2026-08-23T10:30:00Z",
  "agentId": "fast-qa",
  "usage": {
    "promptTokens": 0,
    "completionTokens": 0
  }
}
```

字段说明:

| 字段 | 类型 | 说明 |
|------|------|------|
| `conversationId` | string | 本次会话唯一 ID |
| `round` | int | 当前对话所在轮次 |
| `event` | string | 事件类型,当前固定 `conversation.completed` |
| `timestamp` | string(ISO8601) | 事件发生时间 |
| `agentId` | string | 触发的 Agent ID |
| `usage` | object | Token 用量等元数据 |

事件订阅者:本地数据库持久化模块(写入历史)、UI 层(刷新会话列表)。

### 5. 后续扩展

- 多 Agent 编排:规划 Agent、工具调用 Agent、检索 Agent 等
- 多模型 Provider:OpenAI、Anthropic、本地 Ollama 等
- 上下文压缩策略可配置(摘要、滑动窗口、关键消息保留)
- 对话导出 / 分享
- `.vex` 目录下的扩展配置文件(`owl_history.json`、`owl_prompt.json` 等)

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.