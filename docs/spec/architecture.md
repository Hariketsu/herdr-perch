# 技术架构（v1）

> 2026-10-20 第二版。v1 只做"看状态 + 跳转"，不含刘海内交互（见 product.md 第 1 节）。实测依据见 research.md 第 9 节。
> 本文第 3～6 节的类型与函数签名是**测试契约**：测试按它编写，实现必须满足它。改签名要先改本文。

## 1. 原则

1. **Herdr 是唯一权威**：状态只来自 `session.snapshot`。事件只表示"有东西变了，再读一次"，从不把事件 payload 写进状态。
2. **事件加速，轮询兜底**：逐 pane 订阅状态事件以获得 Herdr 级延迟；轮询只是兜底，只有两档。
3. **零额外进程、零 CLI**：App 直接连 Unix socket；Session 发现靠扫描 socket 文件，不调用 `herdr` CLI。
4. **不写 Herdr**：产品代码只调用 `ping`、`session.snapshot`、`events.subscribe`，以及用户点击触发的 `workspace.focus / tab.focus / pane.focus`。
5. **没有本地状态机**：显示状态是 `agent_status` 的直接映射。唯一的本地记录是"首次观察到某个 `state_change_seq` 的时间"，只用于显示时长和排序。

## 2. 工程结构

```
herdr-perch/                    SwiftPM, swift-tools 6.0, macOS 14+, 无第三方依赖, swift-testing
├── Package.swift
├── Sources/
│   ├── PerchCore/              无 AppKit/SwiftUI 依赖的全部逻辑
│   │   ├── Herdr/              SocketConnection, HerdrClient, Models, Subscription
│   │   ├── Discovery/          SessionEndpoint, SessionScanner
│   │   ├── Sync/               RefreshScheduler, SubscriptionPlan, PollingPolicy
│   │   ├── State/              DisplayStatus, AgentRow, RowBuilder, StatusClock, SessionHealth
│   │   └── Runtime/            SessionRuntime, SessionRegistry, PerchStore, Jumper, StateTrace
│   ├── PerchApp/               AppKit + SwiftUI（可执行）
│   │   ├── App/                main, AppDelegate, MenuBar, LoginItem, Preferences
│   │   ├── Window/             NotchPanel, NotchGeometry, NotchWindowController
│   │   ├── Presentation/       PresentationState, CompactSummary（纯逻辑，可测）
│   │   ├── Views/              CollapsedView, ListView, PixelBird, Palette, Motion
│   │   └── Platform/           TerminalActivator
│   └── perchctl/               调试与测试用 CLI：dump / watch / jump（只链接 PerchCore）
├── Tests/
│   ├── PerchCoreTests/         单元测试 + 进程内假 server + Fixtures/
│   ├── PerchAppTests/          PresentationState, CompactSummary, NotchGeometry
│   └── E2E/                    Python（uv + pytest），驱动命名测试 Session
├── scripts/                    bundle.sh, smoke.sh
├── LICENSE                     GPL-3.0
├── NOTICE
└── LICENSES/NotchAgent-Apache-2.0.txt
```

把 Runtime 放进 `PerchCore` 的原因：App 和 `perchctl` 共用同一份运行时，E2E 通过 `perchctl watch` 就能端到端验证发现、订阅、刷新和状态推导，不需要驱动 UI。

## 3. 数据流

```
SessionScanner（每 1s 扫 socket 文件）
   │ 新 socket → ping 通过 → 建 Runtime；socket 消失 → 移除 Runtime
   ▼
SessionRuntime × N（actor，每个 Herdr server 一个）
   ├─ 事件流：events.subscribe(SubscriptionPlan.make(snapshot))
   │     任意事件 ──┐            计划变化 → 关闭旧流、按新计划重订阅
   ├─ 兜底定时器 ───┼──▶ RefreshScheduler（50ms 合并、串行、读取中再触发则追加一次）
   │                │          │
   │                │          ▼ session.snapshot（2s 超时）
   │                │      SessionState 整体替换（snapshot + health）
   ▼
PerchStore（@MainActor）：RowBuilder.rows(所有 SessionState, StatusClock) → [AgentRow]
   │
   ├─▶ PerchApp：CollapsedView / ListView ── 点击 ──▶ Jumper
   └─▶ StateTrace（环境变量 PERCH_TRACE=<path> 时写 NDJSON，供冒烟/E2E 使用）
```

`[AgentRow]` 是唯一的数据出口，View 不直接接触 Herdr 类型。

## 4. 模块契约

### 4.1 Herdr 协议层（`PerchCore/Herdr`）

```swift
public enum AgentStatus: String, Sendable, Equatable {
    case idle, working, blocked, done, unknown
    // 解码时未知字符串 → .unknown
}

public struct AgentInfo: Sendable, Equatable {
    public var paneID: String            // pane_id
    public var tabID: String             // tab_id
    public var workspaceID: String       // workspace_id
    public var agent: String             // agent，例如 "claude"
    public var displayAgent: String?     // display_agent
    public var name: String?             // name
    public var status: AgentStatus       // agent_status；缺失或未知字符串 → .unknown
    public var stateChangeSeq: UInt64    // state_change_seq，缺失时 0
    public var completionSeq: UInt64?    // completion_seq
    public var title: String?            // title ?? terminal_title_stripped（title 是 metadata 覆盖值，优先）
    public var stateLabels: [String: String]  // state_labels，缺失时 [:]
    public var cwd: String?              // foreground_cwd ?? cwd
    public var focused: Bool             // 缺失 → false
}

public struct PaneInfo: Sendable, Equatable {
    public var paneID: String, tabID: String, workspaceID: String
}

public struct Snapshot: Sendable, Equatable {
    public var protocolVersion: Int      // protocol
    public var panes: [PaneInfo]
    public var agents: [AgentInfo]
    /// 从完整响应行（`{"id","result":{"type","snapshot":{...}}}`）解码。
    /// panes/agents 按元素容错：缺少必需字段（pane_id/tab_id/workspace_id/agent）的元素被跳过，其余字段缺失用默认值。
    public static func decode(response: Data) throws -> Snapshot
}

public struct PingInfo: Sendable, Equatable { public var version: String; public var protocolVersion: Int }

public struct Subscription: Hashable, Sendable {
    public var type: String              // 例如 "pane.created"
    public var paneID: String?           // 仅 pane.agent_status_changed 需要
}

public enum HerdrError: Error, Equatable, Sendable {
    case connectFailed(Int32)            // errno；ENOENT/ECONNREFUSED 等
    case timeout
    case closedByPeer                    // 未收到完整一行就被关闭；或写入时对端已关闭（EPIPE / ECONNRESET）
    case malformedResponse
    case server(code: String, message: String)
    case eventsLost
    case unsupportedProtocol(Int)        // protocol < 22
}

public enum EventSignal: Equatable, Sendable {
    case started                         // 收到 subscription_started
    case event                           // 任意事件行；不解析内容
}

public struct HerdrClient: Sendable {
    public static let minimumProtocol = 22
    public init(socketPath: String, timeout: Duration = .seconds(2))
    public func ping() async throws -> PingInfo           // protocol < 22 抛 unsupportedProtocol
    public func snapshot() async throws -> Snapshot
    public func focusWorkspace(_ id: String) async throws
    public func focusTab(_ id: String) async throws
    public func focusPane(_ id: String) async throws
    /// 长连接。首个元素必为 .started；之后每个事件行产出 .event。
    /// error 响应映射为 .server / .eventsLost 并结束流；对端关闭以 closedByPeer 结束。
    public func subscribe(_ subscriptions: [Subscription]) -> AsyncThrowingStream<EventSignal, any Error>
}
```

传输要求：

| 项 | 要求 |
|---|---|
| 连接 | 每个请求新建连接（Herdr 一个连接只处理一个请求）；订阅是唯一的长连接 |
| SIGPIPE | `SO_NOSIGPIPE`；对端提前关闭时返回错误，进程不得被信号杀死 |
| 超时 | 连接、写、读整体 ≤ `timeout`，超时抛 `.timeout`；订阅流只对"等待 `subscription_started`"施加超时 |
| 读取 | 按 `\n` 分帧，支持跨多次 `recv` 的长行（snapshot 可达数百 KB） |
| socket 路径 | `sun_path` 上限 104 字节，超长时抛 `connectFailed(ENAMETOOLONG)` |

### 4.2 Session 发现（`PerchCore/Discovery`）

```swift
public struct SessionEndpoint: Hashable, Sendable {
    public var name: String              // "default" 或 sessions/<name>
    public var socketPath: String
    public var isDefault: Bool
}

public struct SessionScanner: Sendable {
    public init(root: URL)               // 产品中为 ~/.config/herdr
    /// <root>/herdr.sock → default；<root>/sessions/<name>/herdr.sock → name。
    /// 只认 socket 类型文件（S_IFSOCK）；普通文件、目录、符号链接都忽略。结果按 name 排序，default 在首位。
    public func scan() -> [SessionEndpoint]
}
```

`SessionRegistry` 每 1s 调用一次 `scan()`：

- 新 endpoint：`ping` 成功才创建 Runtime；失败（例如崩溃残留的 socket）下一轮再试。
- endpoint 从扫描结果中消失：立即移除 Runtime，行淡出。
- Runtime 报告不可达持续 30s：移除 Runtime；之后只有 `ping` 再次成功才会重建。
- `ping` 返回 `unsupportedProtocol`：创建一个只带 health 的占位 Runtime，列表显示 "Herdr update required"。

### 4.3 同步（`PerchCore/Sync`）

```swift
public enum SubscriptionPlan {
    /// 全局：pane.created, pane.closed, pane.exited, pane.moved, pane.agent_detected,
    ///       pane.focused, tab.closed, workspace.closed
    public static let global: Set<Subscription>
    /// global ∪ { pane.agent_status_changed(pane_id) | snapshot.panes 中的每个 pane }
    /// 订阅所有 pane（而不只是有 agent 的 pane），这样 pane 里新出现 agent 时不必重订阅。
    public static func make(for snapshot: Snapshot) -> Set<Subscription>
}

public enum PollingPolicy {
    /// streamHealthy：已收到 started 且流未结束。
    /// 可达：健康 3s，不健康 0.5s。不可达：1, 2, 4, 8, 10, 10… 秒（consecutiveFailures 从 1 起）。
    public static func interval(streamHealthy: Bool, consecutiveFailures: Int) -> Duration
}

public actor RefreshScheduler {
    /// sleep 用于注入假时钟；fetch 执行一次 snapshot 并发布结果。
    public init(coalesce: Duration = .milliseconds(50),
                sleep: @escaping @Sendable (Duration) async throws -> Void,
                fetch: @escaping @Sendable () async -> Void)
    /// 语义：空闲时请求 → 等待 coalesce 后执行 fetch，窗口内的多次请求合并为一次；
    /// fetch 进行中再请求 → 当前 fetch 结束后恰好再执行一次（无论期间请求多少次）。
    /// 任意时刻最多一个 fetch 在执行。
    public func request()
    /// 等待当前已排队的工作全部完成（测试用）。
    public func drain() async
}
```

订阅维护（`SessionRuntime` 内）：

- 每次 snapshot 后算 `SubscriptionPlan.make`，与当前流的计划不同时：关闭旧流，按新计划开新流。新流 `started` 之后立即请求一次刷新（补上切换空窗）。
- 流以 `.server(invalid_request…)` 结束（通常是 pane 刚关闭）：请求刷新，并用新计划重订阅；连续失败按 0.25s 起指数退避，上限 30s。期间只算"流不健康"，**不**标记 Session 断线。
- 流以 `.eventsLost` 或 `closedByPeer` 结束：重订阅，`started` 后刷新。
- 触发刷新的来源：任意 `.event`、兜底定时器、列表展开、跳转完成。

### 4.4 状态（`PerchCore/State`）

```swift
public enum DisplayStatus: Int, Comparable, Sendable {
    case blocked = 0, finished, working, idle     // 排序优先级
    public init(_ status: AgentStatus)            // done→finished，idle/unknown→idle
}

public struct AgentRef: Hashable, Sendable { public var session: String; public var paneID: String }

public enum SessionHealth: Equatable, Sendable {
    case live
    case stale(since: Date)                       // 最近一次 snapshot 失败，但 socket 仍在
    case updateRequired(protocolVersion: Int)
}

public struct AgentRow: Identifiable, Equatable, Sendable {
    public var id: AgentRef
    public var status: DisplayStatus
    public var isUnrecognized: Bool               // agent_status == unknown
    public var title: String                      // name ?? title ?? displayAgent ?? agent
    public var subtitle: String?                  // stateLabels[原始状态] ?? title（与 title 相同时为 nil）
    public var agentLabel: String                 // displayAgent ?? 已知映射 ?? agent；映射：claude→Claude, codex→Codex, omp→OMP, opencode→OpenCode
    public var project: String?                   // cwd 的最后一级目录名
    public var since: Date                        // StatusClock 记录的进入当前状态的时间
    public var session: String
    public var showsSessionTag: Bool              // 存在 ≥2 个 Session 时为 true
    public var isStale: Bool                      // 所属 Session 为 stale
    public var workspaceID: String, tabID: String
}

public struct StatusClock: Sendable {
    /// 对每个 (AgentRef, stateChangeSeq) 记录首次观察时间；seq 变化时更新；
    /// 已不存在的 AgentRef 被清除。
    public mutating func observe(_ ref: AgentRef, seq: UInt64, now: Date) -> Date
    public mutating func retain(only refs: Set<AgentRef>)
}

public struct SessionState: Sendable, Equatable {
    public var endpoint: SessionEndpoint
    public var snapshot: Snapshot?               // 最近一次成功的 snapshot
    public var health: SessionHealth
}

public enum RowBuilder {
    /// 排序：status 优先级 → since 倒序 → session 名 → paneID（保证稳定）。
    public static func rows(_ sessions: [SessionState], clock: inout StatusClock, now: Date) -> [AgentRow]
}
```

### 4.5 运行时（`PerchCore/Runtime`）

```swift
public actor SessionRuntime {
    public init(endpoint: SessionEndpoint,
                client: HerdrClient,
                now: @escaping @Sendable () -> Date = { Date() },
                onChange: @escaping @Sendable (SessionState) -> Void)
    public func start()                  // 首次 snapshot + 订阅 + 兜底定时器
    public func stop()                   // 取消事件流与定时器；之后不再回调 onChange
    public func requestRefresh()
    public var state: SessionState { get }
}

public actor SessionRegistry {
    public init(scanner: SessionScanner,
                scanInterval: Duration = .seconds(1),
                unreachableTimeout: Duration = .seconds(30),
                clientTimeout: Duration = .seconds(2),
                now: @escaping @Sendable () -> Date = { Date() },
                onChange: @escaping @Sendable ([SessionState]) -> Void)
    public func start()                  // 每 scanInterval 调用一次 scanOnce
    public func stop() async             // 停止扫描与全部 Runtime
    public func refreshAll() async       // 对所有 Runtime 请求一次刷新
    public func scanOnce() async         // 一次完整的扫描 / 接入 / 移除（测试直接调用）
    public var sessions: [SessionState] { get }   // 顺序同 SessionScanner
}

@MainActor @Observable
public final class PerchStore {
    public init(root: URL, tracePath: String? = ProcessInfo.processInfo.environment["PERCH_TRACE"])
    public private(set) var rows: [AgentRow]
    public private(set) var sessions: [SessionState]
    public func start()
    public func stop()
    public func refreshAll()             // 列表展开时调用
    public func jump(_ row: AgentRow) async -> JumpOutcome
}
```

### 4.6 跳转（`PerchCore/Runtime/Jumper`）

```swift
public enum JumpOutcome: Equatable, Sendable { case focused, needsAttach, failed(String) }
public struct Jumper: Sendable {
    /// 依次 focusWorkspace → focusTab → focusPane；任一步失败即停止。
    /// 错误码或信息含 "detach" 时返回 .needsAttach。
    public func jump(_ row: AgentRow, client: HerdrClient) async -> JumpOutcome
}
```

`PerchApp` 在 `.focused` 后调用 `TerminalActivator.activate()`（只用 `NSRunningApplication.activate`，不同步调用 `open`），120ms 后再执行一次 focus 链，然后收起刘海。

### 4.7 StateTrace 与 perchctl

`PERCH_TRACE=<path>` 时，`PerchStore` 每次发布新的 `[AgentRow]`（与上次不同）就追加一行：

```json
{"t": 1792463895.713, "rows": [{"session":"perch-e2e","pane":"w1:p2","status":"working","title":"…","stale":false}], "sessions": [{"name":"perch-e2e","health":"live"}]}
```

`perchctl`（只链接 PerchCore）：

| 命令 | 行为 |
|---|---|
| `perchctl dump [--root <dir>]` | 扫描、每个 Session 一次 snapshot，输出一行上述 JSON 后退出 |
| `perchctl watch [--root <dir>]` | 运行完整 Runtime，每次变化输出一行 JSON（与 StateTrace 同格式） |
| `perchctl jump <session> <pane>` | 执行 Jumper（不激活终端 App），输出一行 `{"outcome":"focused"|"needsAttach"|"failed","message":<String?>}`；`focused` 时退出码 0，否则 1；找不到该行时 outcome 为 `failed` |

## 5. Session 生命周期

```
 (absent) ──scan 发现 + ping OK──▶ live ──snapshot 失败──▶ stale（行变灰，"Reconnecting…"）
                                    ▲                        │
                                    └──── snapshot 成功 ──────┤
                                                             │ 持续 30s
 socket 文件消失（任意状态）─────────▶ removed ◀───────────────┘
```

- Session 停止：事件流立即断开 → 刷新失败进入 stale → 270ms 内 socket 被删除 → 下一次扫描（≤1s）移除。目标 1.5s 内行淡出。
- Herdr 卡死（接受连接但不回应）：事件流不会断开，只能靠兜底轮询发现，最坏 3s 间隔 + 2s 超时，目标 6s 内进入 stale，UI 不冻结。

## 6. 窗口与呈现（`PerchApp`）

沿用 NotchAgent 骨架（`NotchPanel`、`NotchGeometry`、"变大先改 frame、变小后改 frame" + `transitionRevision`）。v1 去掉 `canBecomeKey`（没有输入框）。

```swift
enum Surface: Equatable { case hidden, collapsed, expanded(pinned: Bool, auto: Bool) }

struct PresentationState {
    // 时间常量
    static let hoverIntent: Duration = .milliseconds(120)
    static let hoverExitDelay: Duration = .milliseconds(280)
    static let autoCollapse: Duration = .seconds(8)
    init(autoExpandOnBlocked: Bool = true)
    // 纯 reducer：输入事件与当前时间，更新 surface；需要定时检查时设置 nextTick
    mutating func handle(_ event: PresentationEvent, now: ContinuousClock.Instant)
    private(set) var surface: Surface
    private(set) var nextTick: ContinuousClock.Instant?   // 调用方在该时刻发送 .tick
}

enum PresentationEvent {
    case rowsChanged(hasRows: Bool, newBlocked: Bool)   // newBlocked：出现了上次没有的 blocked AgentRef
    case pointerEntered, pointerExited, clicked, clickedOutside, rowActivated
    case tick
    case settingsChanged(autoExpandOnBlocked: Bool)
}
```

规则（与原型一致）：

| 场景 | 结果 |
|---|---|
| 无任何行 | `hidden` |
| 有行，初始 | `collapsed` |
| collapsed 时指针进入并停留 ≥120ms | `expanded(pinned:false, auto:false)` |
| 未钉住的 expanded 时指针离开 ≥280ms | `collapsed` |
| 点击刘海 | collapsed → `expanded(pinned:true)`；未钉住的 expanded（含 auto）→ `expanded(pinned:true)`；钉住的 expanded → `collapsed` |
| 点击外部 | `collapsed` |
| collapsed 时出现新 blocked 且设置开启 | `expanded(pinned:false, auto:true)` |
| auto 展开后 8s 内没有指针进入或点击 | `collapsed` |
| auto 展开期间指针进入或点击 | 去掉 auto 标记，按普通 expanded 处理 |
| 行被点击（跳转） | `collapsed` |

```swift
enum CompactStyle: String { case birdCount = "A", dots = "B", counts = "C" }   // 默认 B
struct CompactSummary: Equatable {
    var birdStatus: DisplayStatus?        // 最紧急的状态；无行时 nil
    var dots: [DisplayStatus]             // B：每个 Agent 一个点，按 RowBuilder 顺序，最多 maxDots(6) 个
    var overflow: Int                     // B：超出 6 个的数量（显示 +N）
    var counts: [DisplayStatus: Int]      // C：只含数量 > 0 的状态
    var total: Int                        // A
    var allStale: Bool                    // 有行且全部 stale；无行时为 false
    static let maxDots = 6
    static func make(_ rows: [AgentRow]) -> CompactSummary
    /// 每只耳朵的宽度（与原型 notch.jsx wingWidth 一致）：
    /// A = 40；B = max(40, min(total, 6) × 10 + 22)；C = max(40, counts.count × 24 + 16)
    func wingWidth(_ style: CompactStyle) -> CGFloat
}

struct NotchScreenMetrics: Equatable {
    var frame: CGRect
    var safeAreaTop: CGFloat
    var auxiliaryTopLeftArea: CGRect?
    var auxiliaryTopRightArea: CGRect?
    init(screen: NSScreen)               // 产品代码使用；测试直接用成员初始化
}

struct NotchGeometry: Equatable {
    static let fallbackBandHeight: CGFloat = 32   // 无刘海屏
    static let floatingCenterWidth: CGFloat = 190 // 无刘海屏的中间区域
    static let expandedWidth: CGFloat = 400
    static let maxExpandedHeight: CGFloat = 420
    init(metrics: NotchScreenMetrics)
    /// safeAreaTop > 0，且 auxiliaryTopRightArea.minX − auxiliaryTopLeftArea.maxX 在 (80, 400) 之间（搬自 NotchAgent）
    var hasNotch: Bool { get }
    var centerWidth: CGFloat { get }     // 有刘海：上述间距；否则 floatingCenterWidth
    var bandHeight: CGFloat { get }      // 有刘海：safeAreaTop；否则 fallbackBandHeight
    func collapsedSize(wingWidth: CGFloat) -> CGSize                 // (centerWidth + 2 × wing, bandHeight)
    /// 宽 = max(collapsed 宽, min(expandedWidth, frame.width − 24))；
    /// 高 = min(bandHeight + contentHeight, maxExpandedHeight, frame.height × 0.72)，四舍五入到偶数
    func expandedSize(contentHeight: CGFloat, wingWidth: CGFloat) -> CGSize
    func panelFrame(size: CGSize) -> CGRect   // 水平居中于 frame.midX，顶边贴 frame.maxY
}
```

```swift
enum ListStyle: String { case heroAndRows, rowsOnly }                    // 默认 heroAndRows
enum DisplayPlacement: String { case builtInNotch, mainDisplay }         // 默认 builtInNotch
struct Preferences: Equatable {
    var compactStyle: CompactStyle = .dots
    var listStyle: ListStyle = .heroAndRows
    var autoExpandOnBlocked = true
    var displayPlacement: DisplayPlacement = .builtInNotch
    var launchAtLogin = false
    var followReduceMotion = false   // 默认始终播放完整动画；开启后才跟随系统的"减少动态效果"（2026-10-20 确认）
    // 键名：compactStyle, listStyle, autoExpandOnBlocked, displayPlacement, launchAtLogin, followReduceMotion
    // 缺失或无法识别的值取默认值
    static func load(from defaults: UserDefaults) -> Preferences
    func save(to defaults: UserDefaults)
}
```

### 6.1 动效改造（v1.1，feat/notch-motion）

参考 open-vibe-island（GPL-3.0）的做法：窗口固定为最大尺寸，动画全部交给 SwiftUI 的单次事务；收起态窗口忽略鼠标事件，由全局和本地 `NSEvent` monitor 加几何判断产生指针事件。这样做有两个目的：一是消除 AppKit 改 frame 与 SwiftUI spring 不同步造成的卡顿；二是收起态不拦截刘海旁边的菜单栏点击。

```swift
extension NotchGeometry {
    static let maxWingWidth: CGFloat = 140        // 完成反馈显示"✓ 标题"时的耳宽（≥ C 样式 4 种状态的 112）
    static let canvasMargin: CGFloat = 36         // 给两层投影（0 8px 24px）和 pop 放大留的余量
    /// 固定画布：宽 = max(min(expandedWidth, frame.width − 24), centerWidth + 2 × maxWingWidth) + 2 × canvasMargin；
    /// 高 = min(maxExpandedHeight, frame.height × 0.72) + canvasMargin。面板只在屏幕变化时按它重设 frame。
    var canvasSize: CGSize { get }
    var canvasFrame: CGRect { get }              // panelFrame(size: canvasSize)
    // panelFrame(size:) 同时用作形状在屏幕坐标中的外接矩形（命中区域）
}

/// 由 mouseMoved / mouseDown 的屏幕坐标产生 PresentationEvent。纯逻辑。
struct PointerTracker {
    private(set) var isInside: Bool = false
    /// 区域按闭区间判断（含边缘：指针贴住屏幕顶边时 y == frame.maxY，也算在内）。
    /// 进入时返回 .pointerEntered，离开时返回 .pointerExited，状态不变时返回 nil。
    mutating func update(location: CGPoint, region: CGRect) -> PresentationEvent?
    /// 区域内点击 → .clicked；区域外点击且处于展开态 → .clickedOutside；否则 nil。区域同样按闭区间判断。
    static func click(at location: CGPoint, region: CGRect, expanded: Bool) -> PresentationEvent?
    // 区域变化（展开、收起导致形状尺寸改变）时，调用方用当前指针位置再调一次 update。
}

enum PresentationEvent { …
    case agentFinished(title: String)            // 某行新变为 Finished（由 NotchModel 比较前后两次的行得出）
}

extension PresentationState {
    static let completionDuration: Duration = .seconds(2)
    /// 完成反馈（对应 vibeisland 的 approved 层）：collapsed 时收到 agentFinished → completion = title，2s 后清除；
    /// 期间再收到则替换标题并重新计时。非 collapsed 时忽略；surface 离开 collapsed（展开、隐藏）时立即清除。
    /// nextTick 取"hover / 离开 / 自动收起的计时"与"completion 到期"中较早的一个；两者互不取消。
    var completion: String? { get }
    /// rowsChanged(hasRows: true, newBlocked: true) 没有引起自动展开时（自动展开设置关闭，或者已经处于展开态）加 1。
    /// 视图监听它的变化，播放一次 pop 动画（放大到 1.04，spring(response: 0.3, dampingFraction: 0.5)）。
    /// 隐藏态下（hasRows 为 false）不加；从隐藏态首次出现行且带新 blocked、又没有自动展开时，先变为 collapsed 再加 1。
    var pulse: Int { get }
}
```

视觉参数（不进单元测试）以 vibeisland.app 首页演示为准（`/tmp/vibe-ref/affiliate.*.css` 的 `.v6-notch` / `.v6-layer`，demo.js 的 `v()`）：

| 用途 | 参数 |
|---|---|
| 宽高（开与收共用） | `cubic-bezier(.175,.885,.32,1.1)`，0.5s |
| 底角半径 | 收起 10 → 展开 14，单独走 `easeOut` 0.4s |
| 肩膀 | 固定 6pt 内凹，画在形状外侧，不随展开变化 |
| 投影 | `0 2px 8px` 黑 60% + `0 8px 24px` 黑 30%；展开时加 `0 0 15px` 白 4%，存在 Blocked 时改加 `0 0 20px` 橙 15% |
| 层切换 | 非激活层 opacity 0、blur 6、scale .96；opacity 0.25s、blur 0.3s、scale 0.35s（同上曲线）；激活层延迟 60ms |
| 完成反馈 | 右耳加宽到 140，显示 ✓ 加标题，2s 后恢复；尺寸变化走同一条宽高曲线 |
| pop（新 blocked 未自动展开） | scale 1.04，`spring(response: 0.3, dampingFraction: 0.5)` |
| 层的挂载 | 收起层与展开层始终挂载，只切换激活状态（插入的层会以激活态出现，跳过淡入） |

其余窗口要求：

- 点击穿透：收起态 `hitTest` 只在刘海与两耳形状内返回视图，其余返回 nil。
- 屏幕变化：监听 `didChangeScreenParametersNotification` 立即重新定位；显示器设置只有内建刘海屏和主显示器两种。
- 层级：`.statusBar`，`[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`，App 为 `.accessory`。

## 7. 异常处理一览

| 场景 | 行为 |
|---|---|
| Herdr 未运行（无 socket） | 无行，`hidden`；菜单栏菜单中显示 "Herdr isn't running" |
| Herdr 重启（同一 socket） | stale → 恢复后整体替换；事件流退避重连 |
| Herdr 卡死 | 2s 超时 → stale |
| 某个 pane / agent 元素解码失败 | 跳过该元素 |
| 订阅被拒（`invalid_request`） | 刷新并重订阅，退避；不标记断线 |
| `events_lost` | 重订阅后刷新 |
| protocol < 22 | 该 Session 显示 "Herdr update required" |
| 跳转时没有 attach 的客户端 | 行内提示 "No Herdr window attached" |
| 终端 App 不唯一 | 前台是支持的终端就用它；否则唯一在运行的那个；否则最近一次成功用过的；都没有就只做 Herdr 侧 focus |

## 8. 资源预算

- 每个 Session：1 条订阅连接 + 每 3s 一次 snapshot（约 0.5ms）。扫描每 1s 一次 readdir + 少量 stat。
- 只在可见且存在 Working/Blocked 时运行动画；收起且全部 Idle/Finished 时不运行任何动画。
- 目标：空闲 CPU < 0.5%，内存 < 60MB。

## 9. v1 之后（不在本次范围）

刘海内交互（审批、提问、文本回复）沿用 NotchAgent 的 PromptClassifier → ScreenAdapters → Planner → Responder 链路，并加 `agent.get` 复核 `state_change_seq`、文本用 `pane.send_input`。届时作为独立模块 `PerchCore/Interaction` 接入，消费 `AgentRow` 中 blocked 的行，不改动上面的同步层。research.md 第 6、7 节的相关条目在那时再执行。
