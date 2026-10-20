# 产品 Spec：Herdr Perch

> **A quiet companion for Herdr.**
> Keep an eye on your coding agents from your MacBook's notch.
> See who's working, know who needs you, and respond without leaving your flow.

## 1. 定位与边界

Perch 是 Herdr 的一扇小窗：**看状态、接住求助、一键回去**。它只读取 Herdr，在用户明确点击时，才让 Herdr 聚焦对应的 pane。

> **v1 范围（2026-10-20 确认）**：只做"看状态 + 跳转"。刘海内的 Approve / Deny / Answer 推迟到 v1 之后（见第 5 节），v1 中 Blocked 行点击后同样跳回 Herdr。

| 做 | 不做 |
|---|---|
| 刘海中展示所有本地 Herdr Session 的 Agent 状态 | 终端模拟、输出流、聊天历史 |
| Blocked 时克制地提醒 | 屏保、Telegram、Web Dashboard、云账号 |
| v1 之后：在刘海里 Approve / Deny / Answer（带有效性校验） | 远程或 SSH 机器管理、工作流编排 |
| 点击跳回对应的 Herdr pane | 启动、停止、新建 Agent，向空闲 Agent 发 prompt |
| 自动发现 Session 的新增、退出和重连 | 向 Agent 注入 Hooks、安装 Herdr integration、改 Herdr 配置 |
| | BridgeServer、Relay、自有状态机、配置系统 |

**Herdr 是唯一权威。** Perch 显示的每个状态都能在 `herdr agent list` 里找到对应项。Perch 不会"猜"一个 Herdr 没有说的状态。

## 2. 状态定义

Perch 展示 4 种状态，全部由 Herdr 的 `agent_status` 直接映射：

| Perch 状态 | Herdr `agent_status` | 含义 | 视觉 |
|---|---|---|---|
| **Blocked** | `blocked` | 等待权限批准或回答问题 | 琥珀色，柔和呼吸光（唯一会"动"的颜色） |
| **Working** | `working` | 正在执行 | 冷白色，细小的流动指示 |
| **Finished** | `done` | 完成一轮且尚未查看 | 薄荷绿实心点 |
| **Idle** | `idle`、`unknown` | 等待输入，或 Herdr 无法判定 | 灰色空心点；`unknown` 的副标题显示 "Unrecognized" |

规则：

- **Finished 的消退**：完全以 Herdr 为准。用户在 Herdr TUI 里看过该 tab，或通过 Perch 跳转（focus API），Herdr 都会把 `done` 改为 `idle`（2026-10-20 实测，research.md 第 9.1 节）。Perch 没有本地已读记录。
- **排序**：Blocked > Finished > Working > Idle；同一状态内，按最近一次状态变化时间倒序。
- **分组**：只有一个 Session 时不显示分组；多个 Session 时，在每行末尾显示 Session 名称的小标签。

## 3. 两种形态（收起 / 展开）

> 以 `docs/prototype/` 为准（2026-10-20 用户认可方向）。视觉蓝本是 vibeisland.app。

- **收起态**：刘海顶带高 32pt，中间约 186pt 是摄像头区域，内容放在两耳。
  - 左耳：像素小鸟，颜色随最紧急的状态变化；
  - 右耳：按设置显示 A（小鸟 + 数量）、B（每个 Agent 一个点，默认）或 C（按状态计数）；
  - 没有 Agent 时整个面板隐藏。
- **展开态**：宽 400pt，高度随内容变化。
  - 第一行是大行：鸟 + 标题 + 标签 + 状态副行；
  - 其余是普通行：点 + 标题 + Blocked/Finished 时的状态小字 + 标签 + 时长；
  - 状态副行来自 Herdr 的 `state_labels`，没有时用 `terminal_title_stripped`；
  - 点击任意行都跳回 Herdr。
- **开合**：hover 停留 120ms 展开，离开 280ms 后收起；点击刘海钉住或取消钉住；点击外部收起。

## 4. 提醒策略（醒目但克制）

| 事件 | 行为 |
|---|---|
| 某 Agent 变为 Blocked，且刘海处于收起态 | 自动展开列表（只自动打开这一次；设置可关闭） |
| 自动打开的列表 8s 内没有任何指针交互 | 平滑收起回收起态，琥珀色呼吸光继续提示 |
| 用户 hover 或点击过自动打开的列表 | 视为已介入，不再自动收起 |
| Agent 变为 Finished | **不自动展开列表**；收起态刘海短暂加宽约 2s，显示"✓ 标题"（对应 vibeisland 的 approved 层，2026-10-20 确认），然后恢复 |
| 全屏 App 或演示中 | 面板位于 `.statusBar` 层级，并带 `fullScreenAuxiliary`，仍然可见；提醒仍只是自动展开 |

不使用系统通知中心（v1）。不做红点计数徽标。不做提示音：Herdr 自带提示音（2026-10-20 确认）。

## 5. 交互有效性（防误操作，v1 之后）

> v1 不实现。以下规则留给后续交互版本。

用户点击按钮后、发送任何按键之前，必须**全部**满足以下条件，否则不发送：

1. Herdr 报告该 pane 的 `agent_status` 仍为 `blocked`；
2. `agent` 种类不变，`state_change_seq` 与卡片渲染时相同（说明仍是同一次 blocked）；
3. 重新读屏并解析后，fingerprint 与卡片渲染时相同（说明提示内容没有变化）；
4. 该意图在此 kind 的白名单内，且解析置信度不是 `fallback`、操作机制不是 `ambiguous`。

不满足时：卡片原地刷新为最新内容，并显示一行琥珀色小字 "This prompt changed. Nothing was sent."。用户需要重新确认。

## 6. 跳转

- 点击任意行后：
  1. Herdr 依次 focus 该 pane 所在的 workspace、tab、pane；
  2. 激活终端 App；
  3. 收起刘海。
- 终端 App 的选择：如果当前前台 App 就是支持的终端，用它；否则用正在运行的唯一一个支持的终端；有多个时，用最近一次成功跳转用过的那个。
- 该 Session 没有 attach 任何客户端时，行内提示一句 "No Herdr window attached"。

## 7. 多 Session

- 自动发现所有本地运行中的 Herdr Session（default 和命名 Session）。
- **新增**：1.5s 内出现在列表中（每秒扫描 Herdr 的 Session socket）。
- **退出**：Session 停止后，其 Agent 行在 1.5s 内淡出。
- **断线**：Session 仍在列表中但 socket 不可达时，该 Session 的行保持原样，但变灰并显示 "Reconnecting…"。超过 30s 仍不可达则移除这些行；Herdr 未运行时面板隐藏，菜单栏菜单中显示 "Herdr isn't running"。
- **重连**：恢复后自动对账，不需要用户操作。

## 8. 设置

2026-10-20 调整：原型中的形态选项**作为用户设置提供**，不再由我们替用户选定（成熟产品让用户选形态）。

菜单栏放一个鸟形模板图标，菜单项：Show/Hide Perch、Settings…、About（含 NotchAgent 致谢）、Quit。

设置窗口（单页，SwiftUI `Settings` scene）：

| 分组 | 设置项 | 选项 | 默认 |
|---|---|---|---|
| 外观 | 收起态样式 | A 小鸟 + 数量 / B 每个 Agent 一个点 / C 按状态计数 | B |
| 外观 | 列表样式 | 大行 + 普通行 / 全部普通行 | 大行 + 普通行 |
| 行为 | Blocked 时自动展开 | 开 / 关 | 开 |
| 行为 | 显示器 | 内建刘海屏 / 主显示器 | 内建刘海屏 |
| 通用 | 登录时启动 | 开 / 关 | 关 |

不提供任何影响数据正确性的设置（例如轮询间隔、Herdr socket 路径）；那些由程序自己决定。

## 9. 视觉语言

以原型为准，token 来自 Vibe Island：

| 用途 | 值 |
|---|---|
| Blocked | `#f97316` |
| Working | `#3b82f6` |
| Finished | `#22c55e` |
| Idle | `#737373` |
| 动画曲线 | spring `cubic-bezier(.175,.885,.32,1.1)`，0.5s |
| 切层 | blur 6px + scale .96 淡入，延迟 60ms |

吉祥物是像素风小鸟，画法参照 Vibe Island 的像素宠物。

## 10. 验收口径

- 状态与 `herdr agent list` 保持一致。事件流健康时，状态延迟不超过 Herdr 事件 + 300ms（p95）；事件流断开时不超过 1s。
- 空闲时 CPU 平均低于 0.5%，内存低于 60MB。
- Herdr 停止、重启、新建或删除 Session 时，App 不崩溃、不卡死；Session 增删在 1.5s 内反映，卡死在 6s 内显示为 stale。
- 冒烟、单元、端到端三类测试全部通过（implementation.md）。
