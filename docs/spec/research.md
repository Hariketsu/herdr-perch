# 研究报告：NotchAgent 源码与 Herdr API

> 研究对象：`ref/notchagent`（GitHub `ykushch/notchagent`，作者 Yuri Kushch，Apache-2.0，commit `32cd6cb`，约 17.9k 行 Swift）
> 对照环境：本机 Herdr **0.9.5 / protocol 22**。NotchAgent 的协议结论是在 Herdr 0.7.4 / protocol 16 上验证的，下文凡与 0.9.5 不同处均已标注，并用只读请求（`ping`、`session.snapshot`、`events.subscribe`、`herdr api schema --json`）实测过。
> 日期：2026-10-19

---

## 1. 结论速览

1. **Herdr 已经提供了我们需要的大部分"权威状态"**：Agent 识别、`idle / working / blocked / done / unknown` 五态、`state_change_seq`、`completion_seq`、pane 拓扑、聚焦、读屏、按键发送和事件流。Perch 不需要、也不应该再维护一套 Agent 状态机。
2. **Herdr 不提供的东西**：
   - 待处理提示的结构化描述（问题文本、选项），以及 Approve / Deny API；
   - Session 列表的 socket 方法（只有 CLI `herdr session list --json`）；
   - 把终端 App 拉到前台的能力。

   这三块正是 NotchAgent 自己实现、且值得复用的部分。
3. NotchAgent 的价值集中在四块：**屏幕交互解析 + 指纹复核的安全响应链路**、**多 Session 运行时**、**刘海窗口几何与动画骨架**、**跳转（focus 链 + 激活终端）**。其余（屏保、SSH、OpenCode HTTP、更新、热键、模式切换、空闲输入框）都不在 Perch 范围内。
4. 复用比例估算：HerdrClient 约 60% 可直接或小改复用，NotchApp 约 25%（窗口骨架），Views 基本重写。

---

## 2. NotchAgent 架构

```
SwiftPM (tools 6.0, macOS 14+, 无外部依赖, swift-testing)
├── HerdrClient (library)   协议客户端 + 状态 + 交互解析/响应   ← 核心复用对象
├── NotchApp (executable)   AppKit 面板 + SwiftUI 视图 + 多 Session 运行时
├── ScreenSaveKit (library) 屏保渲染                              ← 删除
├── notchctl (executable)   调试 CLI（list/watch/capture/dry-run/reply/jump）
└── NotchScreenSaver        非 SwiftPM，由 scripts/build-screensaver.sh 构建   ← 删除
```

运行时对象关系：

```
NotchViewModel (@MainActor, 聚合所有 Session)
 ├─ SessionRegistry ── 每 10s `herdr session list --json` → 增删 SessionRuntime
 └─ SessionRuntime × N (每个 Herdr server 一个)
     ├─ HerdrClient (每次请求新建 socket 连接)
     ├─ StateStore (pane 表 + 派生状态)
     ├─ InteractionCoordinator → InteractionResponder → Planner / ScreenAdapters
     └─ PaneActivityCoordinator / AgentMode / CompletionSummary / OpenCodeNative
NotchWindowController ── NotchPanel(NSPanel) + NotchGeometry + NotchSurfaceState + NotchPresentation
```

---

## 3. Herdr Socket API（以 0.9.5 实测为准）

### 3.1 传输

| 事实 | 来源 |
|---|---|
| Unix domain socket，NDJSON：一行一个请求，一行一个响应 | 官方 socket-api 文档，`SocketConnection.swift` |
| 请求 `{"id","method","params"}`；成功 `{"id","result":{"type":...}}`；失败 `{"id","error":{"code","message"}}` | schema |
| **一个连接只处理一个请求**，响应后服务端关闭连接；第二次写入会触发 `EPIPE` | 0.9.5 实测（Broken pipe） |
| `events.subscribe` 是例外：同一连接上先回 `subscription_started`，之后持续推送事件 | 实测 |
| `ping` 返回 `version`、`protocol` 和 `capabilities` | 实测 |

### 3.2 Socket 路径与 Session 发现

- 默认 Session：`~/.config/herdr/herdr.sock`
- 命名 Session：`~/.config/herdr/sessions/<name>/herdr.sock`
- 解析顺序：`--session`，然后 `HERDR_SOCKET_PATH`，然后 `HERDR_SESSION`，最后默认路径（`SocketPath.swift:12-43`）
- **权威列表只能通过 CLI 获取**：`herdr session list --json`，返回 `{"sessions":[{"name","running","session_dir","socket_path","default"}]}`。没有对应的 socket 方法。
- GUI App 启动时 PATH 很短，需要 `ExecutableLocator` 来定位 `herdr`（`CommandRunner.swift:110-165`，会查 `/opt/homebrew/bin`、`~/.cargo/bin` 等路径）。

### 3.3 Perch 需要的方法

| 方法 | 用途 | 备注 |
|---|---|---|
| `ping` | 健康检查、版本与能力 | |
| `session.snapshot` | 全量引导与对账 | 返回 `workspaces / tabs / panes / layouts / agents`，以及 `focused_*`、`version`、`protocol` |
| `events.subscribe` | 失效信号 | 见 3.5 |
| `agent.get` | 响应前复核 status 和 `state_change_seq` | 0.9.5 新增可用字段 |
| `pane.read` | 读屏解析提示 | `source`：`detection`（纯文本，主路径）和 `visible`（`format: ansi`，`strip_ansi: false`，用于定位高亮的 wizard tab） |
| `pane.send_keys` / `agent.send_keys` | 发送按键 | Herdr 先校验全部 key 再写入；不接受 `prefix+` 写法 |
| `pane.send_input` | **文本与按键在一次请求内原子提交** | NotchAgent 只定义了参数、没有调用，Perch 应改用它 |
| `workspace.focus` → `tab.focus` → `pane.focus` | 跳转 | 只调 `pane.focus` 可能停留在旧 tab（`Actions.swift:120-158`） |

### 3.4 Agent 数据模型（`AgentInfo`，来自 `session.snapshot.agents[]` 或 `agent.get`）

| 字段 | 含义 | 对 Perch 的意义 |
|---|---|---|
| `agent_status` | `idle \| working \| blocked \| done \| unknown` | **唯一的状态来源** |
| `state_change_seq` | 每次状态迁移递增 | 用于交互防误操作：同一次 blocked 的身份标识 |
| `completion_seq` | 当前空闲迁移对应的完成序号 | 用于 Finished 本地已读去重 |
| `agent` / `display_agent` / `name` | Agent 种类、展示名、用户命名 | 行标题 |
| `terminal_title_stripped` / `title` / `state_labels` | 当前任务标题、自定义状态文案 | 行副标题（由 Herdr 提供，不额外推导） |
| `cwd` / `foreground_cwd` | 工作目录 | 项目名 |
| `workspace_id` / `tab_id` / `pane_id` / `focused` / `revision` | 拓扑 | 跳转与刷新判断 |

关于 `done` 的语义：Herdr 以 server 端的 seen 状态区分 `done` 和 `idle`；显式的 focus 命令会把目标标记为已读，读取操作不会。各 TUI 客户端的 Done 徽标各自独立。
**0.9.5 中 `done` 是 per-pane 的一等状态**，所以 NotchAgent 用"working→idle 且未聚焦"推导出的 `finishedUnseen` 已经不再需要。

### 3.5 事件订阅（0.9.5 实测）

- `pane.agent_status_changed`、`pane.scroll_changed`、`pane.output_matched` **必须带 `pane_id`**。批量订阅中只要有一项无效，**整批会被拒绝，连接随即关闭**（实测返回 `invalid_request: missing field pane_id`）。
- 全局可订阅：`pane.created / closed / updated / exited / moved / focused / agent_detected`、`tab.*`、`workspace.*`、`layout.updated`。
- 官方恢复语义：
  - 事件历史不持久化。订阅者落后时，服务端回 `events_lost` 并关闭连接。
  - snapshot 与事件之间**没有共享序号**，因此不能把事件 payload 回放到 snapshot 上。
  - 推荐做法：**先订阅，再拉 snapshot 并整体替换缓存；把事件当作"需要再读一次"的失效信号；串行化刷新，读取期间来了事件就再刷一次**。
- NotchAgent 记录的"订阅时 Herdr 会重放早已关闭的 `pane_created`"，在 0.9.5 实测 6 秒内没有出现，文档也明确写了"不重放"。Perch 的设计本身不依赖事件 payload，因此不受这一行为影响。

### 3.6 NotchAgent 实际调用的方法

`ping`、`session.snapshot`、`events.subscribe`、`pane.read`、`pane.get`、`pane.send_keys`、`pane.send_text`、`workspace.focus`、`tab.focus`、`pane.focus`。
CLI：`herdr session list --json`、`herdr status --json`。没有任何版本门控。

---

## 4. 各项能力的归属

| 能力 | Herdr 提供 | NotchAgent 实现 | Perch 需要 |
|---|---|---|---|
| PTY 和进程托管、Agent 识别 | ✅ | — | 直接使用 |
| Working / Idle / Blocked / Done 判定 | ✅（manifest 规则 + 官方 integration） | 额外推导 done-unseen | **只用 Herdr 的** |
| 任务标题和状态文案 | ✅ `terminal_title_stripped`、`state_labels` | 读屏提取完成摘要 | 只用 Herdr 字段 |
| Session 列表 | ✅ CLI | 10s 轮询 + Runtime 增删 | 复用 Runtime 增删；发现改为目录监听触发 |
| 状态同步 | snapshot + 事件 | 自适应轮询 + 事件，last-writer-wins | 复用轮询骨架，改为"事件即失效"模型 |
| 提示结构化（问题、选项、diff） | ❌ | `PromptClassifier` + `ScreenAdapters`（Claude、Codex） | **复用** |
| 安全响应（复核、规划按键、settle） | ❌（只提供 key 校验） | `InteractionResponder` / `Planner` / `Coordinator` | **复用并加强** |
| 跳转到 pane | ✅ focus 方法 | focus 链 + 激活终端 App | 复用 |
| 刘海窗口 | — | `NotchPanel` / `Geometry` / `SurfaceState` / `Presentation` | 复用骨架，UI 重写 |
| OpenCode 原生审批 | — | 直连 OpenCode HTTP | 删除（违反 "Herdr 唯一来源"） |
| 屏保、SSH 远程、更新、热键、模式切换、空闲输入框 | — | ✅ | 删除 |

---

## 5. 关键文件解读

### 5.1 交互识别（`HerdrClient`）

- **`PromptClassifier.swift`**：从 `detection` 文本中定位**最后一个** `1.` 选项，向上回溯到标题行，再扩展到分隔线（`─`/`╌` 连续 8 个以上），把 diff 卡片一并纳入。`parseOptionLine` 识别以下内容：
  - `❯ › >` 光标；
  - `[x] [✓]` 复选框；
  - 行尾 `✔`；
  - `(esc)`。
- **`ScreenAdapters.swift`**：按 `agent` id 精确路由，`claude` 交给 `ClaudeScreenAdapter`，`codex` 交给 `CodexScreenAdapter`，其余交给 `GenericScreenAdapter`。
  - **Claude**：必须命中以下 block marker 之一，并且至少有一个编号选项：
    - `do you want to proceed?`
    - `esc to cancel`
    - `enter to select`
    - `ready to submit`
    - ……

    交互类型分为 approval、question、reviewSubmit；操作机制分为 numberedShortcut、arrowNavigate、multiSelect。
  - **Codex**：approval 必须**恰好** 3 个选项，且快捷键为 `(y)`、`(p)`、`(esc)`，否则判为 `.ambiguous`，拒绝自动操作。question 依赖 `Question n/m` 头部和特定 footer。
  - **Generic**：`kind: .unknown`，`confidence: .fallback`，只允许手动操作。
- **`PendingInteraction.swift`**：结构化模型，外加 **fingerprint**——对 pane id、kind、标题、正文、各选项（kind、label、description、shortcut）、步骤和 evidence 做规范化拼接后取 SHA-256。光标、勾选状态等**展示态被刻意排除**，所以光标移动不会让一次响应失效，按键规划始终基于最新的光标位置。
- **`InteractionResponsePlanner.swift`**（纯函数）：把意图翻译成按键序列。
  - numbered：`["<n>","enter"]`
  - explicitShortcut：`["y"]`
  - arrow：`up/down × Δ` 后接 `enter`
  - deny：`["esc"]`
  - text：`send_text` 后接 `enter`
  - ambiguous：拒绝
- **`InteractionResponder.swift:175-218`**：安全边界，流程如下。
  1. 重新读屏并重新解析；
  2. 比对 fingerprint，不一致就报 `staleInteraction`，**一个字节都不发**；
  3. 用 per-kind 白名单校验意图，`unknown` 和 `freeText` 一律拒绝；
  4. 基于最新解析结果规划按键；
  5. 逐条发送；
  6. settle：最多轮询 8 次、每次间隔 160ms，直到连续两次读屏一致且与原屏不同。

  多选场景下，每次移动光标后要等光标稳定再发 `enter`。
- **`InteractionCoordinator.swift`**：
  - 以 pane 为键维护状态，阶段为 `idle / reading / responding / settling`；
  - 用 `blockedSequence` 做代际守卫，代际变化后丢弃过期结果；
  - 只有在 phase 为 idle 且 pane 仍处于 blocked 时才允许响应；
  - 没有任何自动应答逻辑。

### 5.2 状态与运行时

- **`SessionRuntime.swift`**：`pollOnce` 依次执行 `session.snapshot`、`store.reconcileTransitions`、交互和活动的 reconcile，最后通知 host。事件只用作加速器。
- **`SnapshotPollingPolicy.swift`**：unavailable 时 1.0s；展开或存在 blocked 时 0.65s；存在 working 时 1.2s；其余 2.5s。后台时间隔 ×2。
- **`StateStore.swift`**：pane 表加上 `finishedUnseen / workingSince / blockedSince`。没有 revision 排序，采用 last-writer-wins。
- **`SessionRegistry.swift`**：`apply()` 负责停掉消失的 Runtime、重建 endpoint 变化的 Runtime、启动新出现的 Runtime。发现失败时保留现有 Runtime。

### 5.3 刘海窗口（`NotchApp`）

- **`NotchPanel`**：
  - `[.borderless, .nonactivatingPanel]`，`level = .statusBar`；
  - `[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`；
  - `canBecomeKey` 只在展开时为 true，因为输入框需要成为 key window；
  - App 使用 `.accessory` 激活策略。
- **`NotchGeometry`**：
  - 判断有无刘海用 `safeAreaInsets.top > 0`；
  - 刘海宽度 = `auxiliaryTopRightArea.minX − auxiliaryTopLeftArea.maxX`，只接受 80～400pt 的结果；
  - 无刘海的屏幕用 190pt 浮动胶囊；
  - 展开态宽度取 `min(520, 屏宽−24)`。
- **`NotchSurfaceState`**：hover 时立即展开，离开后延迟 280ms 收起；高度通过 PreferenceKey 测量。
- **`NotchWindowController`**：
  - 变大时先改窗口 frame 再做形状动画，变小时先做形状动画再改 frame，用 `transitionRevision` 丢弃过期回调；
  - 外部点击用 local 和 global `NSEvent` monitor 检测（不需要辅助功能权限）；
  - 监听屏幕参数变化后立即重新定位。
- **`NotchPresentation`**：`compact | overview | focused(origin, hasUserEngaged)`。新出现 blocked 时只会从 compact 自动聚焦；自动打开的卡片在交互解决后收起，用户主动介入过的除外。

### 5.4 跳转

- **`Actions.jump`**：依次 `workspace.focus`、`tab.focus`、`pane.focus`，然后 `terminal.present()`，sleep 120ms 后再执行一遍 focus 链。错误信息包含 "detached" 时返回 `.needsAttach`。
- **`TerminalActivator`**：
  - 支持 Ghostty、Terminal、iTerm2、kitty、WezTerm、Alacritty、Warp；
  - 前台 App 是终端就用它；否则当且仅当只有一个终端在运行时用它；
  - 激活方式是 `NSRunningApplication.activate`，加上在主线程上**同步**执行 `/usr/bin/open -b`（这是缺陷）。

---

## 6. 已发现的缺陷与风险（复用时必须修）

| # | 问题 | 位置 | 处理 |
|---|---|---|---|
| 1 | App 内请求**没有超时**，Herdr 卡住时轮询会永久挂起，UI 也不会显示断线 | `SessionRuntime` 创建 `HerdrClient(endpoint:)` 时没有传入超时 | 默认 2s 超时 |
| 2 | **没有 `SO_NOSIGPIPE`**，Herdr 重启时 App 可能被 SIGPIPE 杀掉（0.9.5 实测第二次写入就是 EPIPE） | `SocketConnection` | 设置 `SO_NOSIGPIPE` |
| 3 | 订阅被拒后每 0.5s 无限重试 | `SessionRuntime.startEventTask` | 指数退避，并以 snapshot 作为兜底 |
| 4 | 断线后旧状态继续显示，横幅只在全部 Session 断开时出现 | `pollOnce` catch | 显式标记 per-session stale |
| 5 | `PaneInfo` 严格解码，单个异常 pane 会导致整个 snapshot 失败，表现为"Herdr 不可达" | `Snapshot.swift` | 按元素容错解码 |
| 6 | 事件与轮询 last-writer-wins，旧数据可能覆盖新数据 | `StateStore` | 事件不写状态，只触发刷新 |
| 7 | fingerprint 不包含 revision，**内容相同的新提示**（例如同一命令再问一次）能通过复核 | `InteractionResponder` | 加入 `state_change_seq` 复核 |
| 8 | 文本与回车分两次发送，不是原子操作 | `Actions.reply` | 改用 `pane.send_input` |
| 9 | 全局热键在刘海收起时仍能批准用户看不见的提示 | `HotkeyMonitor` | 删除 |
| 10 | `stripAnsi` 只处理 `ESC…m`，遇到非 SGR 序列会吞文本 | `PromptClassifier.swift:111` | 改用完整的 CSI/OSC 正则；主路径本来就用 `strip_ansi: true` |
| 11 | 主线程同步执行 `open -b` 并 `waitUntilExit` | `TerminalActivator` | 只用 `activate`，必要时放到后台执行 |
| 12 | `herdr session list` 没有超时 | `ProcessCommandRunner` | 3s 超时后 terminate |
| 13 | Claude 编号选项发送 `["1","enter"]`；如果新版 Claude 收到数字就立即生效，多出的 `enter` 会落到下一屏 | Planner | v1 先用现有 fixture；上线后若发现回车落空，再录制新 fixture 修正 |
| 14 | 屏幕文案启发式依赖 Agent UI 版本 | ScreenAdapters | 识别不出时降级为"仅跳转"；fixture 回归测试 |
| 15 | 免打扰检测已失效（读的是旧的 DND key） | `SoundEngine` | 不复用 |

---

## 7. 可复用模块清单（保留 / 修改 / 删除）

> 原则：交互解析与安全响应链路是"经过 fixture 验证"的资产，**尽量原样搬运**；运行时和网络层修掉第 6 节的缺陷；UI 只保留窗口骨架。

### HerdrClient → `PerchCore`

| 文件 | 结论 | 说明 |
|---|---|---|
| `SocketPath.swift` | 保留 | |
| `JSONValue.swift` | 保留 | |
| `AgentRef.swift` | 保留 | `(sessionID, paneID)`，跨 Session 的唯一标识 |
| `Models/Enums.swift` / `Events.swift` / `Params.swift` | 保留 | 去掉不用的类型 |
| `Models/Snapshot.swift` | 修改 | 容错解码；新增 `AgentInfo` 的 `state_change_seq`、`completion_seq`、`terminal_title_stripped`、`name` |
| `SocketConnection.swift` | 修改 | 只保留 Unix socket；`SO_NOSIGPIPE`；修正 errno 判断；删除 TCP |
| `HerdrClient.swift` | 修改 | 默认超时；订阅错误分类（`events_lost`、`invalid_request`）；保留 backoff |
| `SessionDescriptor.swift` / `SessionDirectory.swift` | 修改 | 删除 SSH 与 remote |
| `CommandRunner.swift` | 修改 | 加超时；保留 `ExecutableLocator` |
| `StateStore.swift` | **大改** | 删除 done 推导、计时器和 outputMatched；改为 snapshot 整体替换 + 本地 ack |
| `SnapshotPollingPolicy.swift` | 修改 | 删除 remote 倍率；增加"事件流健康时降频" |
| `PendingInteraction.swift` | 保留 | drafts 可删 |
| `PromptClassifier.swift` | 保留（修 `stripAnsi`） | |
| `ScreenAdapters.swift` | 保留 | |
| `InteractionResponsePlanner.swift` | 保留 | |
| `InteractionResponder.swift` | 修改 | 增加 `agent.get` 复核（status 仍为 blocked、`agent` 和 `state_change_seq` 不变）；文本改用 `send_input` |
| `InteractionCoordinator.swift` | 修改 | 删除 completionSummaries 和 drafts，保留代际守卫 |
| `InteractionDisplayModel.swift` | 修改 | 只保留按钮可用性；删除 OpenCode model badge |
| `Actions.swift` | 修改 | 保留 `sendRawKeys` 和 `jump`；`reply` 改为 `send_input`；删除 `interrupt` 和 `cycleAgentMode` |
| `TerminalActivator.swift` | 修改 | 去掉同步 `open` |
| `SHA256Digest.swift` | 删除 | 改用 CryptoKit `SHA256` |
| `OpenCodeNativeProvider.swift` | 删除 | 直连 OpenCode HTTP，违反"Herdr 唯一来源" |
| `PaneActivity.swift` / `AgentMode.swift` / `CompletionSummary.swift` | 删除 | 超出范围（终端尾部输出、模式切换、完成摘要） |
| `SSHTunnel.swift` | 删除 | |
| `HerdrDiagnostics.swift` / `InteractionDiagnostics.swift` | 删除（v1） | 调试工具，以后如有需要再引入 |
| `PaneCapture.swift` / `PaneFixtureExtractor.swift` | 移入测试工具 | 用于录制新 fixture |

### NotchApp → `PerchApp`

| 文件 | 结论 | 说明 |
|---|---|---|
| `main.swift` | 保留 | |
| `AppDelegate.swift` | 修改 | 只保留面板、菜单栏和 registry 的装配 |
| `NotchPanel.swift` / `NotchGeometry.swift` / `NotchSurfaceState.swift` / `NotchPresentation.swift` / `Views/NotchHeightMeasurement.swift` | 保留 | 窗口骨架 |
| `NotchWindowController.swift` | 修改 | 删除 terminalDisplay 跟随模式 |
| `SessionRegistry.swift` / `SessionRuntime.swift` | 修改 | 删除 SSH、OpenCode、Activity 和 Mode；加入 stale 状态与"事件即失效"逻辑 |
| `NotchViewModel.swift` | 重写（参考） | 898 行，大部分功能已删除；保留聚合排序、选择、响应和跳转逻辑 |
| `MenuBarController.swift` / `MenuBarIcon.swift` / `LoginItem.swift` | 修改 / 保留 | 极简菜单 |
| `Settings.swift` | 大幅精简 | 3 个键 |
| `Views/*` | 重写 | 新 UI（见 product.md）；`InteractionDetailView` 的选项、diff 和命令证据渲染逻辑可参考 |
| `SettingsView.swift`、`HotkeyMonitor.swift`、`AgentModeCycling.swift`、`AgentNotifications.swift`、`SoundEngine.swift`、`AppLaunchMode.swift`、`GlobalKeyboardShortcut.swift`、`ScreenSaver*`、`ScreenSave*`、`SystemScreenSaverAutomation.swift`、`Updates/*`、`Views/ShortcutRecorder.swift`、`Views/ScreenSaveView.swift`、`Views/PaneActivityViews.swift` | 删除 | |
| `Resources/HerdrMark.svg`、`Views/HerdrBrandMark.swift` | 删除 | Herdr 商标授权不明；Perch 用自有的鸟形图标 |

### 其他

| 项 | 结论 |
|---|---|
| `ScreenSaveKit/*`、`NotchScreenSaver/*`、`scripts/build-screensaver.sh` | 删除 |
| `notchctl` | v1 删除；Phase 2 视需要提供 `perchctl dry-run` |
| `bundle.sh` | 修改：去掉屏保与 appcast |
| Tests | 保留：Models、SocketClient（自带 in-process 假 server）、StateStore（改写）、PromptClassifier、ScreenAdapter、PendingInteraction、Planner、Responder、Coordinator、SessionDirectory、ActionsTests，以及 NotchGeometry、SurfaceState、Presentation；fixture 全部保留（`Fixtures/prompts`、`interactions`、`claude-interactions`、`snapshot.json`、`sessions`） |

---

## 8. 许可证与署名

- NotchAgent 的 `LICENSE` 是 Apache-2.0 原文，附录里的版权占位没有填写。仓库**没有 NOTICE 文件**，源文件里也**没有版权头**。作者身份可由 git 记录和 GitHub 仓库确认：Yuri Kushch，`ykushch/notchagent`。
- Perch 的义务（Apache-2.0 §4）：
  1. 分发时附带 Apache-2.0 许可证文本（`LICENSES/NotchAgent-Apache-2.0.txt`）；
  2. 新增 `NOTICE`：`Portions of this software are derived from NotchAgent (https://github.com/ykushch/notchagent), Copyright Yuri Kushch, licensed under the Apache License, Version 2.0.`；
  3. 每个复制或改写的文件头部注明：`Derived from NotchAgent <原路径> (Apache-2.0). Modified by Herdr Perch.`；
  4. App 的 About 菜单里列出 Acknowledgements。
- **Perch 采用 GPL-3.0**（2026-10-20 确认）。Apache-2.0 代码可以并入 GPLv3 作品，但**不能并入 GPLv2-only 作品**，因此必须是 GPLv3（或 "v3 or later"）。派生文件保留 Apache 署名头，整体以 GPL-3.0 分发。

---

## 9. 补充实测（2026-10-20，Herdr 0.9.5）

方法：tab2 启动 codex 作为实验对象，默认 Session 上只做只读订阅和 snapshot；需要写入的实验只在命名测试 Session（`perch-test`、`perch-e2e`）里做，结束后已 stop + delete。

### 9.1 事件与状态

| 问题 | 结果 |
|---|---|
| 只订阅全局事件能否捕捉状态变化 | **不能**。idle→working、working→done 都没有任何全局事件。`pane.updated` 只在 `terminal_title_stripped` 变化时触发，payload 中的状态可能已过时 |
| 逐 pane `pane.agent_status_changed` 的延迟 | 与 100ms 轮询看到变化的时间相差 < 25ms，即事件延迟 ≈ Herdr 自身判定延迟 |
| TUI 中手动聚焦是否清除 `done` | **会**。server 端立即变为 `idle`，`state_change_seq` 不变，同时推送 `agent_status_changed: idle` 和 `pane_focused / tab_focused / workspace_focused` |
| 事件名格式 | 不统一：状态事件为 `pane.agent_status_changed`，聚焦事件为 `pane_focused`、`tab_focused`。Perch 不解析事件名，任何事件行都视为失效信号 |

结论：Perch 不需要本地已读记录（AckLedger 删除）；要做到事件级延迟必须逐 pane 订阅。

### 9.2 开销

| 操作 | 平均耗时 |
|---|---|
| `ping`（连接 + 请求 + 关闭） | 0.06 ms |
| `session.snapshot`（3 个 Agent，13 KB） | 0.46 ms |
| `herdr session list --json`（起进程） | 6 ms |

### 9.3 Session 目录行为

| 事件 | 观察 |
|---|---|
| `herdr --session <name> server` 启动 | +14ms 创建 `sessions/<name>/`（`sessions/` 上有 kqueue 事件），+65ms 出现 `herdr.sock` |
| `herdr session stop <name>` | +270ms 删除 `herdr.sock`；目录保留；`sessions/` 上**无事件** |
| 根目录 `~/.config/herdr` | 空闲时也因 `session.json` 重写持续产生 kqueue 事件，监听它只有噪声 |

结论：Session 发现采用"每秒扫描 socket 文件 + ping"（见 architecture.md 第 4 节），不调用 CLI、不做目录监听。

### 9.4 用于测试的状态驱动

在测试 Session 中可以用 `pane.report_agent` 确定性地驱动 Agent 状态（无需真实 Agent）：

1. headless server 启动后没有 workspace，需要先 `workspace.create`；
2. 目标 pane 必须有前台进程（例如 `pane.send_input {text:"exec sleep 600", keys:["enter"]}`），否则报 `idle` 时 Agent 会被移除；
3. `state` 只接受 `idle | working | blocked | unknown`，每次报告 `state_change_seq` 递增；
4. 在**未聚焦的 tab** 中报 `idle` 得到 `done`（`completion_seq` 同步更新）；对该 tab 调 `tab.focus` 后变回 `idle`。

### 9.5 响应形状

- `ping` → `{"type":"pong","version":"0.9.5","protocol":22,"capabilities":{...}}`
- `session.snapshot` → `{"type":..., "snapshot":{version, protocol, focused_workspace_id, focused_tab_id, focused_pane_id, workspaces, tabs, panes, layouts, agents}}`
- 错误 → `{"error":{"code":"agent_not_found","message":...}}`
