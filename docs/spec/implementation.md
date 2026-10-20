# 实现计划（v1）

> 2026-10-20 第二版。v1 = 看状态 + 跳转。**测试先行**：每个阶段先由测试作者（codex）提交失败的测试，再由实现者（Claude）实现到全绿。接口契约见 architecture.md 第 4、6 节。
> "搬运"指从 `ref/notchagent` 复制文件后修改，并写署名头（见 Phase 0）。

## 分工与流程

| 角色 | 负责 | 不碰 |
|---|---|---|
| 测试作者（codex，独立 tab） | `Tests/**`、`scripts/smoke.sh`、`Tests/E2E/**`、测试用 fixture | `Sources/**`（只读） |
| 实现者（Claude） | `Sources/**`、`Package.swift`、`scripts/bundle.sh` | 已提交的测试断言（只能和测试作者商量后修改） |

每个阶段的流程：

1. 测试作者按契约写测试，`swift build --build-tests` 能编译（实现可以是空桩），`swift test` 失败；
2. 实现者实现，直到该阶段测试全绿，且之前阶段的测试不退化；
3. 契约有歧义时，先改 architecture.md，再改测试和实现。

## 三类测试

| 类别 | 运行方式 | 依赖 | 用途 |
|---|---|---|---|
| 单元测试 | `swift test` | 无（不连真实 Herdr） | 每个模块的契约，含进程内假 Herdr server |
| 冒烟测试 | `scripts/smoke.sh` | 本机 Herdr（只读） | 构建并打包 .app、启动、不出现在 Dock、StateTrace 与 `herdr agent list` 一致、退出干净 |
| 端到端测试 | `uv run --project Tests/E2E pytest` | 命名测试 Session `perch-e2e`（测试自己创建和删除） | 用 `pane.report_agent` 驱动状态，通过 `perchctl watch` 验证延迟和生命周期 |

E2E 约束：

- 只操作 `perch-e2e` Session；结束时 `herdr session stop` + `herdr session delete`，失败也要清理（fixture teardown）。
- **绝不**对 default Session 做写操作，**绝不**运行 `herdr server stop`。
- 状态驱动方法见 research.md 第 9.4 节。
- 断言时只看 `session == "perch-e2e"` 的行（用户的 default Session 也会被扫描到）。

---

## Phase 0：工程骨架与合规

- `git init`；SwiftPM：`PerchCore`、`PerchApp`、`perchctl`、`PerchCoreTests`、`PerchAppTests`。
- 按 architecture.md 第 4、6 节写出全部公开类型和函数的**空桩**（`fatalError("unimplemented")` 或返回占位值），保证测试能编译。
- `LICENSE`（GPL-3.0）、`NOTICE`、`LICENSES/NotchAgent-Apache-2.0.txt`。派生文件头模板：
  ```swift
  // Derived from NotchAgent Sources/<Target>/<File>.swift
  // https://github.com/ykushch/notchagent — Copyright Yuri Kushch — Apache-2.0
  // Modified by Herdr Perch.
  ```
- `scripts/bundle.sh`：打包 `.app`，`LSUIElement = YES`，ad-hoc 签名。

**验收**：`swift build` 通过；`swift test` 能运行（可以为 0 个测试）。

---

## Phase 1：协议层（`PerchCore/Herdr`）

**测试先行（单元）**：

- `Snapshot.decode`：
  - 0.9.5 真实响应 fixture（从 `perch-e2e` 录制，天然不含用户数据）；
  - NotchAgent 旧 `snapshot.json`；
  - 单个 agent 缺 `pane_id` 时被跳过、其余正常；
  - 未知 `agent_status` → `.unknown`；
  - 缺 `state_labels`、`completion_seq` 时取默认值；
  - `foreground_cwd` 优先于 `cwd`。
- 假 server（进程内 Unix socket，路径放在 `/tmp` 下以免超过 104 字节）：
  - 请求成功；
  - server 返回 error → `.server(code,message)`；
  - 接受连接不回应 → 2s 内 `.timeout`（测试里用更短的 timeout）；
  - 回半行就关闭 → `.closedByPeer`，进程不收到 SIGPIPE；
  - 跨多次写入的长行（≥256KB）正确拼接；
  - socket 不存在 → `connectFailed(ENOENT)`；
  - 路径超长 → `connectFailed(ENAMETOOLONG)`。
- `ping`：protocol 21 → `.unsupportedProtocol(21)`；22 → 成功。
- `subscribe`：
  - 首元素 `.started`，随后每行 `.event`；
  - error `events_lost` → 流以 `.eventsLost` 结束；
  - error `invalid_request` → `.server`；
  - server 关闭 → `closedByPeer`；
  - 发送的请求体包含 pane 级订阅的 `pane_id`。

**实现**：搬运并修改 `SocketConnection`、`HerdrClient`、`JSONValue`、`Models`（删除 TCP/SSH，加 `SO_NOSIGPIPE`、超时、容错解码、修正 errno 判断）。

---

## Phase 2：发现与同步（`PerchCore/Discovery`、`PerchCore/Sync`）

**测试先行（单元）**：

- `SessionScanner`（临时目录内创建真实 socket 文件）：
  - 只有 default；default 加两个命名 Session；
  - `sessions/x/` 存在但没有 socket；
  - 同名普通文件被忽略；
  - 符号链接被忽略；
  - 排序规则：default 在首位，其余按 name。
- `SubscriptionPlan.make`：包含全部 global；每个 pane 一条 `agent_status_changed`；pane 集合相同则计划相等。
- `PollingPolicy.interval`：健康 3s、不健康 0.5s、不可达时 1/2/4/8/10/10。
- `RefreshScheduler`（注入假 sleep）：
  - 单次请求恰好执行一次 fetch；
  - 合并窗口内 10 次请求只执行 1 次；
  - fetch 进行中来 5 次请求 → 之后恰好再执行 1 次；
  - 任意时刻并发 fetch 数 ≤ 1。

**实现**：新写，不搬运。

---

## Phase 3：状态与运行时（`PerchCore/State`、`PerchCore/Runtime`、`perchctl`）

**测试先行（单元）**：

- `DisplayStatus` 映射与排序。
- `RowBuilder`：
  - title、subtitle、agentLabel、project 的取值优先级；
  - subtitle 与 title 相同时为 nil；
  - 单 Session 时 `showsSessionTag == false`，多 Session 时为 true；
  - stale Session 的行 `isStale == true`；
  - 排序稳定。
- `StatusClock`：
  - seq 不变时时间不变；
  - seq 变化时更新为 now；
  - `retain` 清除消失的 ref。
- `SessionRuntime`（假 server 驱动）：
  - 首次连接即 snapshot；
  - 事件到达后 ≤100ms 内重新 snapshot；
  - pane 集合变化后用新计划重订阅；
  - `invalid_request` 后退避重订阅且 health 仍为 live；
  - `events_lost` 后重订阅并刷新；
  - snapshot 失败进入 stale，恢复后回到 live。
- `SessionRegistry`（临时目录 + 假 server）：
  - 新 socket 在一个扫描周期内被接入；
  - ping 失败的残留 socket 不接入；
  - socket 删除后 Runtime 被移除；
  - 不可达 30s 后移除（注入时钟）。
- `Jumper`：调用顺序依次为 workspace、tab、pane；中途失败即停止；错误含 detach 时返回 `.needsAttach`。

**测试先行（E2E，`perch-e2e`）**：

| 用例 | 断言 |
|---|---|
| 状态延迟 | `report_agent` 后，`perchctl watch` 输出对应状态的时间 ≤ Herdr 事件时间 + 300ms（working、blocked、idle 各 20 次，取 p95） |
| Finished | 在未聚焦 tab 中报 idle → `finished`；`tab.focus` 后 → `idle` |
| 新 pane / 新 agent | 新建 tab 并报 working，无需等待兜底轮询即可在 ≤300ms 内出现 |
| Session 新增 | 启动另一个 `perch-e2e-2` server，≤1.5s 内出现（测试结束时清理） |
| Session 停止 | `herdr session stop`，≤1.5s 内该 Session 的行全部消失 |
| 卡死与恢复 | 用 `kill -STOP` 暂停 `perch-e2e` server 进程 → ≤3s 内行变为 stale；`kill -CONT` 后 ≤3s 回到 live（只针对测试 server 的 pid） |
| 跳转 | `perchctl jump perch-e2e <pane>` 后，snapshot 中 `focused_pane_id` 为该 pane；若目标在其他 tab，`focused_tab_id` 随之改变 |
| 一致性 | `perchctl dump` 中 `perch-e2e` 的行与 `herdr agent list`（指向该 Session）逐项一致 |

**实现**：新写 `State`；`SessionRuntime` / `SessionRegistry` 参考 NotchAgent 结构重写，去掉 SSH、OpenCode、Activity、Mode。

---

## Phase 4：窗口骨架（`PerchApp/Window`、`PerchApp/Presentation`）

**测试先行（单元）**：

- `PresentationState`：architecture.md 第 6 节规则表逐行一例，外加：
  - hover 不足 120ms 就离开，不展开；
  - 钉住时指针离开不收起；
  - 自动展开开关关闭时，新 blocked 不展开；
  - 无行时进入 hidden。
- `CompactSummary`：
  - 最紧急状态；
  - 8 个以上时的 overflow；
  - counts 只含非零项；
  - 全部 stale 时 `allStale`。
- `NotchGeometry`（搬运 NotchAgent 测试）：有刘海与无刘海屏、刘海宽度越界时回退。

**实现**：搬运 `NotchPanel`、`NotchGeometry`、`NotchWindowController`（删除 terminalDisplay 跟随、`canBecomeKey`）；新写 `PresentationState`；按形状实现 hitTest。

**手动验收**：

- 内建刘海屏与外接屏定位正确，插拔后立即重新定位；
- 收起态下点击耳朵以外的菜单栏区域不受影响；
- 全屏 App 中仍可见；
- 不抢焦点。

---

## Phase 5：UI（`PerchApp/Views`）与设置

- `CollapsedView`：A/B/C 三种样式，左耳像素鸟的颜色随最紧急状态变化；stale 时变灰。
- `ListView`：大行加普通行，或全部普通行；Blocked/Finished 时显示状态小字；多 Session 标签；页脚异常提示。
- `Motion`：spring `cubic-bezier(.175,.885,.32,1.1)` 0.5s，切层时 blur 加 scale 淡入，支持 Reduce Motion。
- 设置窗口与 `Preferences`：`compactStyle`、`listStyle`、`autoExpandOnBlocked`、`displayPlacement`、`launchAtLogin`。
- 菜单栏：Show/Hide Perch、Settings…、About（含致谢）、Quit。

**测试先行**：

- `Preferences` 的默认值和 UserDefaults 往返（单元）。
- `scripts/smoke.sh`：
  1. `swift build -c release`，`bundle.sh` 打包；
  2. 设置 `PERCH_TRACE` 启动 .app；
  3. 5s 内 trace 中出现 default Session 的行，且与 `herdr agent list` 一致；
  4. `lsappinfo info -only ApplicationType` 不是 Foreground（即不在 Dock 中）；
  5. 发送退出指令后 2s 内退出，退出码为 0；
  6. 运行 60s，空闲 CPU < 0.5%（`ps -o %cpu` 取平均），RSS < 60MB。

**手动验收**（视觉走查，对照原型）：

- 三态切换无跳变；
- 收起且无动态状态时 CPU 接近 0；
- 点击行后跳到对应 pane，终端 App 来到前台。

---

## Phase 6：发布准备

- README：安装、要求（Herdr ≥ 0.9.5）、"不安装任何 Hooks"、致谢。
- About 窗口致谢 NotchAgent。
- 全部三类测试通过，即为 v1 验收。

## 依赖关系

```
P0 ─▶ P1 ─▶ P2 ─▶ P3 ─▶ P5 ─▶ P6
P0 ─▶ P4 ───────────────┘
```

P4 只依赖 P0，可与 P1～P3 并行。
