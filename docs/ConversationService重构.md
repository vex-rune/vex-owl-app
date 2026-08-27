# ConversationService 存废讨论 + 重构需求

> **写这份文档的动机**:在 v2 简化后,`ConversationService` 已经从"门面服务"瘦成"几个 Repository + Agent 的胶水层",很多人(包括我)会问:
>
> - 既然它不再做任何翻译 / 编排,直接用 Provider 组合几个 Repository + Agent 不就行了?
> - 这个 Service 是不是多余的抽象?
> - 如果保留,它的边界到底是什么?
>
> 这份文档把"需求 / 当前状态 / 问题 / 重构方向"摊开,让你判断要不要保留、以及保留的话应该长什么样。

---

## 1. 需求回顾(从对话上下文提炼)

### 1.1 用户视角的核心需求

1. **整轮 assistant 回复 = 1 条 Message**
   - 不再拆 thinking / text / tool_call / tool_result 多行;
   - content 用 Markdown 自定义块(`<think>...</think>`、`:::tool_call`、`:::tool_result`)表达异构内容;
   - 不同块用不同渲染方式(Markdown / 代码块 / 折叠面板等)。

2. **doOnEach 落库**
   - 流式期间,每来一段 AgentResponse → 转成 Markdown delta → appendDelta 落库;
   - doOnComplete → finalize(收尾 streaming=false + bumpRound);
   - 用户可见的"边生成边显示"由 DB watch 自动驱动,UI 不再单独维护 agentMessages 流。

3. **Page 退出 ≠ run 取消**
   - 用户在生成过程中退出 Page,run 继续在后台跑,DB 持续更新;
   - 下次进入 Page 直接看到最新状态。

### 1.2 衍生需求

- **Agent 层与 DB 解耦**:Agent 不接触 MessageRepository / Message 实体;
- **历史回读干净**:从 DB 读历史时,直接拿「单条 Message(content=Markdown)」,无需解析多行事件;
- **落库逻辑归属**:落库 / 累积 / 渲染调度的代码放在哪里?
  - 用户明确说:**放在 chat_page.dart**,不要塞到 Service;
- **Service 只做**:启动 run、读历史、起名、Session CRUD。

---

## 2. 当前状态(v2 简化后的 ConversationService)

### 2.1 它做的事

| 方法 | 职责 | 备注 |
|------|------|------|
| `create/findById/snapshot/watch` | Session CRUD | 直接转发 SessionRepository |
| `rename/pin/unpin/delete` | Session 修改 | 包了一层 RepositoryError 翻译 |
| `enqueueUserMessage` | 用户消息落库 | 直接调 messageRepository.append |
| `loadHistory` | 历史读取 | 直接转发 messageRepository |
| `runAgent` | 启动 AgentRun | 翻译历史 Message → AgentResponse |
| `generateTitle` | 会话起名 | 调 SessionNameAgent + rename |
| `bumpRound` | 增加轮次 | 上一步新增,直接转发 |

### 2.2 它**不**做的事(已删)

- ~~订阅 AgentRun 的事件~~
- ~~把 AgentResponse 翻译成 Message 落库~~
- ~~提供 `agentMessages` 流给 UI~~
- ~~维护 `pendingWrites` / `waitForIdle`~~

### 2.3 它**仍然**保留的"门面"价值

- **一处依赖注入**:把 5 个底层对象(SessionRepository / MessageRepository / ConfigRepository / Agent / SessionNameAgent)打包成一个对象;
- **错误翻译**:RepositoryError 用 `_translate` 统一包装;
- **业务方法命名**:ChatPage 不直接 `messageRepository.append` 而是 `conversation.enqueueUserMessage`。

---

## 3. 问题:ConversationService 必要性

### 3.1 反方观点(它没必要)

1. **胶水层太薄**:v2 之后只剩 CRUD 转发 + 启动 run + 起名,总共不到 200 行;
2. **Provider 体系下不必要**:Riverpod 直接 `ref.watch(messageRepositoryProvider)` / `ref.read(sessionRepositoryProvider)` 比注入一个 Service 更轻;
3. **抽象边界模糊**:Service 现在既转发 Repository,又调用 Agent,又调起名 Agent —— 它到底是"业务编排层"还是"Provider 包装层"?说不清;
4. **测试收益小**:这种薄 Service mock 起来成本和直接 mock Repository 一样;
5. **ChatPage 仍然很重**:用户要求把落库 / 累积 / 渲染逻辑放 Page,而 Service 现在提供的价值不多。

### 3.2 正方观点(它有必要)

1. **业务方法命名**:`conversation.enqueueUserMessage(...)` 比 `messageRepository.append(Message(...))` 表达力强;
2. **未来扩展空间**:多模态、跨 session 引用、Agent 切换、Tool 调用前后置钩子 —— 这些迟早会让 Service 重新变厚;
3. **错误统一包装**:Repository → Service → UI 的错误分层,Service 是合理的中转站;
4. **解耦 test 用例**:Page 测 mock `ConversationService` 比 mock 5 个 Repository 更稳;
5. **单一变更点**:Session 改名 / 起名 / 删除的策略(比如起名前的 prompt 改写、删除前清文件)只需要改 Service 一处。

### 3.3 我的倾向(综合判断)

**保留,但要做两件事:**

1. **明确 Service 的边界**:只做"业务门面"——给上层一个有命名、有错误处理、有默认行为的对象;不做任何订阅/编排/翻译;
2. **让 ChatPage 直接持有底层 Repository**:除了 Service,关键 Repository(主要是 MessageRepository)也通过 Provider 暴露给 Page,因为 Page 现在承担了"落库累积"的职责,直接读 Repository 比绕一层 Service 更顺。

---

## 4. 重构方案

### 4.1 方案 A:保留 Service,瘦化边界(推荐)

**Service 保留**,但只保留三件事:

1. **Session CRUD 业务方法**(create / findById / rename / pin / unpin / delete)
2. **runAgent**(翻译历史 → AgentHandle → Agent.run)
3. **generateTitle + bumpRound**(两个对 Session 元数据的特殊操作)

**Service 删掉**:

- `enqueueUserMessage` —— ChatPage 直接 `messageRepository.append(Message(...))`,更直白
- `loadHistory` —— 同上,直接 `messageRepository.loadHistory(...)`
- `_translate` 包装 —— 改为让底层 Repository 自己抛 RepositoryError,ChatPage 直接 catch

**Service 不做的事**:

- 不订阅 AgentRun
- 不翻译 AgentResponse
- 不维护流
- 不持有任何"业务状态"(如 _pendingWrites / activeTurnId)

### 4.2 方案 B:彻底删掉 Service(激进)

把 `ConversationService` 拆成两段:

- **SessionRepository 暴露更多业务方法**:rename / pin / unpin / delete / bumpRound / generateTitle(内部直接调 SessionNameAgent)
- **ChatPage 直接组合 Provider**:
  ```dart
  final sessionRepo = ref.watch(sessionRepositoryProvider);
  final messageRepo = ref.watch(messageRepositoryProvider);
  final agent = ref.watch(quickAgentProvider);
  ```
  业务方法调用 `sessionRepo.xxx(...)` / `messageRepo.xxx(...)` / `agent.run(...)`。

**优点**:少一层抽象,代码更短。

**缺点**:
- SessionRepository 变成"半个 Service",职责被污染;
- ChatPage 与底层耦合更深,后续多模态 / Agent 切换时 Page 改动大;
- 失去了"业务方法命名"的语义清晰度。

### 4.3 方案 C:Service 变身 Orchestrator(最厚)

把落库 / 累积 / 渲染调度从 ChatPage 收回 Service:

- Service 订阅 AgentRun,在 doOnEach 中调 messageRepository.appendDelta;
- 提供一个 `Stream<Message>` 给 UI(就是当前的 `agentMessages`);
- ChatPage 退化成"纯展示 + 触发发送"。

**优点**:Page 极薄,业务逻辑集中。

**缺点**:
- **违背用户的明确需求**:用户说"doOnEach 的逻辑应该在 chat_page.dart";
- Service 与 Page 又耦合回去;
- 流式组件的"DB watch 驱动 UI"模式不复存在,要回到"Service 推流 + Page 收流"的旧模式。

---

## 5. 推荐方案:方案 A

### 5.1 ConversationService 改造后

```dart
class ConversationService {
  ConversationService({
    required this.sessionRepository,
    required this.configRepository,
    required this.agent,
    required this.sessionNameAgent,
  });

  final SessionRepository sessionRepository;
  final ConfigRepository configRepository;
  final Agent agent;
  final SessionNameAgent sessionNameAgent;

  static const _tag = 'ConversationService';
  static const defaultTitle = '新对话';

  // ===== Session CRUD(纯转发,保留 RepositoryError 包装) =====
  Future<Session> create({...}) => sessionRepository.create(...);
  Future<Session?> findById(String id) => sessionRepository.findById(id);
  Future<List<Session>> snapshot() => sessionRepository.snapshot();
  Stream<List<Session>> watch() => sessionRepository.watch();
  Future<void> rename(String id, String newTitle) =>
      _translate(() => sessionRepository.rename(id, newTitle), '重命名');
  Future<void> pin(String id) =>
      _translate(() => sessionRepository.pin(id), '置顶');
  Future<void> unpin(String id) =>
      _translate(() => sessionRepository.unpin(id), '取消置顶');
  Future<void> delete(String id) =>
      _translate(() => sessionRepository.delete(id), '删除');

  // ===== Agent 启动 =====
  Future<AgentRun> runAgent({
    required String conversationId,
    required OwlConfig config,
  }) async {
    final historyMessages = await sessionRepository // 注:不再需要 messageRepository
        ...
  }

  // ===== 起名 + bumpRound =====
  Future<String> generateTitle(String conversationId) async {...}
  Future<void> bumpRound(String conversationId) async {...}
}
```

### 5.2 ChatPage 改动

- 直接 `ref.read(messageRepositoryProvider.future)` 做 enqueueUserMessage / appendDelta / findById;
- 不再走 `conversation.enqueueUserMessage(...)`;
- 其它逻辑不动。

### 5.3 Service 依赖瘦身

- 构造函数不再需要 `messageRepository` —— 只有 `runAgent` 用到,而 `runAgent` 改为接受"history"参数(由 Page 传入)或保留 messageRepository 但只作为内部使用。

---

## 6. 落地步骤

| 步骤 | 文件 | 改动 |
|------|------|------|
| 1 | `lib/application/conversation/conversation_service.dart` | 删 `enqueueUserMessage` / `loadHistory`,构造函数移除 `messageRepository` |
| 2 | `lib/presentation/pages/chat_page.dart` | `enqueueUserMessage` 改为直接调 `messageRepository.append(Message(...))`,自己处理 RepositoryError |
| 3 | `lib/application/providers.dart` | `conversationServiceProvider` 不再注入 messageRepository |
| 4 | `flutter analyze` + 跑测 | 验证编译通过 |
| 5 | 跑 dev 测一遍 | 验证发消息 / 历史读取 / 起名 三个流程正常 |

---

## 7. 决策记录

**待你拍板的问题**:

- [ ] 方案 A(保留 Service 瘦化) vs 方案 B(彻底删掉) vs 方案 C(Service 变 Orchestrator)?
- [ ] 如果选 A:`runAgent` 是否还要 messageRepository 注入?(影响 Service 的依赖图)

我的默认推荐是 **方案 A**,理由:

1. 与你"落库逻辑放 Page"的需求不冲突;
2. 保留了"业务方法命名"和"未来扩展点";
3. 改造量小、风险低,跑完 dev 就能确认效果。
