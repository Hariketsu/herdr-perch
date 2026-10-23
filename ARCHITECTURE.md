# Architecture

This document describes the high-level architecture of Herdr Perch. If you want to find your way around the code, start here. It names modules and types rather than linking to them; use symbol search to jump to them.

## Overview

Perch is a macOS menu bar app that shows the state of every coding agent running in [Herdr](https://github.com/herdrdev/herdr) in the MacBook notch. It is a read-only companion: Herdr owns all agent state, and Perch's job is to mirror it with low latency and to surface what needs attention.

```
~/.config/herdr/herdr.sock                 one Herdr server per session
~/.config/herdr/sessions/<name>/herdr.sock
        │  NDJSON over Unix sockets
        ▼
PerchCore   SessionRegistry ─▶ SessionRuntime × N ─▶ PerchStore.rows: [AgentRow]
        │                                                   │
        ▼                                                   ▼
PerchApp    NotchModel ─▶ PresentationState ─▶ SwiftUI views in a NotchPanel
perchctl    the same runtime, printing rows as JSON (debugging, end-to-end tests)
```

Data flows one way. Each session runtime keeps the latest `session.snapshot` of its Herdr server; `PerchStore` turns all snapshots into one sorted list of `AgentRow`s, which is the only thing the UI ever sees. The only call that changes Herdr is focusing a pane after the user clicks a row.

## Code map

The package has three targets and no third-party dependencies.

### `PerchCore`

Everything that talks to Herdr and derives state. Shared by the app and `perchctl`, so end-to-end tests can exercise discovery, subscription and state without driving the UI.

**Architecture invariant:** `PerchCore` does not import AppKit or SwiftUI.

- `Herdr/` — the socket client. `SocketConnection` does one request per connection (Herdr closes a connection after one response); `HerdrClient` wraps `ping`, `session.snapshot`, `events.subscribe` and the three focus calls. `Models` decodes snapshots leniently: an agent or pane missing a required field is skipped, not fatal. Unknown status strings decode as `unknown`.
- `Discovery/` — `SessionScanner` lists sessions by looking for socket files: `<root>/herdr.sock` is the default session, `<root>/sessions/<name>/herdr.sock` are named ones. It never runs the `herdr` CLI and ignores symlinks.
- `Sync/` — when to refresh. `SubscriptionPlan` decides which events to subscribe to, `PollingPolicy` the fallback polling interval, and `RefreshScheduler` coalesces refresh requests (50 ms window, at most one snapshot in flight, one more if requests arrive during a read).
- `Runtime/` — `SessionRegistry` scans every second, starts a `SessionRuntime` (an actor) per reachable session and removes it when its socket disappears. `PerchStore` (main actor, `@Observable`) publishes rows and sessions. `Jumper` runs the focus chain. `StateTrace` writes every published row list as NDJSON when `PERCH_TRACE` is set.
- `State/` — pure derivation. `RowBuilder` turns session states into `AgentRow`s; `StatusClock` remembers when each agent was first seen in its current state (for durations and ordering); `TitleCleaner` strips prompt characters and icons from titles such as `π > 󰈙 …`.

**Architecture invariant:** Herdr is the only source of truth. Displayed state is a direct mapping of `agent_status` from the latest snapshot; event payloads are never applied to state. The only local memory is `StatusClock`.

### `PerchApp`

The executable: an `.accessory` app with a status item and a borderless panel over the notch.

- `App/` — `AppDelegate` wires the store, model and windows together. `Preferences` loads and saves settings in `UserDefaults`; `SettingsView` holds the one-page Settings window and the About window; `MenuBarController` owns the status item.
- `Presentation/` — pure logic, unit-tested without a window: `PresentationState` (the notch state machine, see [Presentation](#presentation)), `CompactSummary` (what the collapsed notch shows per style), `ListGroups`, `PeekLayout`, `PointerTracker` (turns mouse positions into enter/exit/click events), `HerdrStatus`.
- `Views/` — SwiftUI. `NotchModel` connects the store to the reducer and owns timers and sizing; `NotchRootView` draws the shape and its three always-mounted layers (collapsed band, peek cards, list); `ListView` holds the grouped list and the peek cards; `PixelRam` and `AgentIcon` draw the mascot and the agent marks.
- `Window/` — `NotchPanel` (a non-activating panel at status bar level, on all spaces and over full-screen apps), `NotchGeometry` (every size, derived from the screen), `NotchWindowController` (placement and mouse handling).
- `Platform/` — `TerminalActivator` brings the user's terminal forward after a jump.

**Architecture invariant:** types in `Presentation/` are pure. Time is passed in (`handle(_:now:)`), and the caller schedules a `.tick` at `nextTick`.

### `perchctl`

A small CLI over `PerchCore`: `dump` prints the current rows once, `watch` prints them on every change (same format as `StateTrace`), `jump <session> <pane>` runs the focus chain. Used for debugging and by the end-to-end tests.

### Elsewhere

- `scripts/` — `bundle.sh` builds `dist/Herdr Perch.app` (the version number lives here), `make-dmg.sh` packages it, `smoke.sh` and `perf.sh` exercise the packaged app, `demo.py` records the README GIFs, `make-icon.py` generates the app icon.
- `Tests/PerchCoreTests`, `Tests/PerchAppTests` — unit tests (swift-testing), with recorded Herdr responses in `Fixtures/`.
- `Tests/E2E` — end-to-end tests in Python (uv + pytest) against a disposable Herdr session.
- `Tests/Support/PointerDriver.swift` — posts mouse events and reads the notch through Accessibility, for `perf.sh`, `smoke.sh` and `demo.py`.

## Herdr boundary

Perch needs Herdr 0.9.5 or later (socket protocol 22). Facts about the protocol that shaped the design:

- **One request per connection.** Herdr answers one NDJSON request and closes the connection; writing again fails with `EPIPE`. `events.subscribe` is the only long-lived connection. Sockets set `SO_NOSIGPIPE`, and every request has a 2 s timeout.
- **Status changes have no global event.** `idle → working` or `working → done` only show up as `pane.agent_status_changed`, which must be subscribed per pane (a subscription without `pane_id`, or with an unknown pane, rejects the whole batch and closes the connection). `SubscriptionPlan` therefore subscribes to a set of global topology events plus status events for every pane in the snapshot, and resubscribes when the pane set changes.
- **Events are invalidation signals.** Snapshots and events share no sequence number, and Herdr does not replay history (`events_lost` means "start over"). The runtime subscribes first, then reads a snapshot and replaces its state wholesale; any event, of any name, just requests another snapshot.
- **`done` belongs to Herdr.** An agent that finished in a tab nobody has looked at is `done`; focusing the tab, in Herdr's TUI or through Perch's jump, turns it back into `idle`. Perch keeps no "seen" state of its own.
- **Titles and labels come from Herdr.** Row titles use `name`, then `title` / `terminal_title_stripped`; subtitles use `state_labels`. Perch does not read the screen.

**Architecture invariant:** Perch never writes to Herdr except `workspace.focus`, `tab.focus` and `pane.focus`, in that order, after a click. It installs no hooks, changes no configuration and starts no processes.

### Session lifecycle

```
(absent) ──socket found, ping ok──▶ live ──snapshot fails──▶ stale (rows grey, "Reconnecting…")
                                     ▲                         │
                                     └──── snapshot ok ────────┤ 30 s
socket removed (any state) ─────────────▶ removed ◀────────────┘
```

- A protocol older than 22 gives a placeholder session with health `updateRequired`.
- Polling is only a fallback: every 3 s while the event stream is healthy, 0.5 s while it is not, and 1, 2, 4, 8, 10 s while the server is unreachable.
- A rejected subscription (usually a pane that just closed) triggers a refresh and a resubscribe with backoff; it does not mark the session stale.
- Targets: a new session appears within 1.5 s, a stopped one disappears within 1.5 s, a hung server is marked stale within 6 s.

## Presentation

### States

The notch is in one of four surfaces:

| Surface | Shows |
|---|---|
| `hidden` | Nothing: no agents in any session. |
| `collapsed` | The band around the camera housing: the ram (coloured by the most urgent agent) and a summary in the chosen style (Clean, Dots, Counts). |
| `peek` | 440 pt wide: up to three cards for things that need attention, then "+N more". |
| `expanded(pinned:)` | 640 pt wide: status counts, then agents grouped into *Needs you*, *Done*, *Working* and a folded *Idle*. |

Transitions, all in `PresentationState`:

- Hovering for 120 ms opens the list from `collapsed` or `peek`; leaving an unpinned list closes it after 280 ms. Clicking pins or unpins it. Clicking a row jumps and collapses.
- Something new that needs attention (a newly blocked agent, a Herdr connection problem, or a newly finished agent when "Peek when an agent finishes" is on) moves `collapsed` to `peek` and adds a card. While the list is open, the matching row flashes instead.
- A peek closes on its own: 8 s after the last blocked card arrived, 6 s for connection cards, 4 s for finished ones. A card leaves as soon as its reason does (the agent is no longer blocked, the session reconnects), and an empty peek collapses at once. Clicking outside does not dismiss it.

**Architecture invariant:** Peek is the only way Perch asks for attention. It never opens the full list by itself.

New events are found by diffing consecutive `Attention` values (blocked agents, finished agents, system alert). On the first update, finished agents are taken as a baseline, so agents that were already done at launch stay quiet. Cards are ordered blocked, then system, then finished; newest first within a kind.

### Window

The panel keeps a fixed canvas, large enough for the biggest shape plus its shadow, and only moves when the screen changes. Every size change is a SwiftUI animation inside that canvas, so AppKit frame changes never fight the spring. While collapsed, the panel ignores the mouse; global and local `NSEvent` monitors plus geometry produce pointer events, so clicks on menu bar items beside the notch go through. This approach comes from open-vibe-island.

On screens without a notch, the band is as tall as the menu bar (`frame.maxY − visibleFrame.maxY`) and the camera housing is replaced by a 190 pt floating center.

### Look and motion

The look and motion follow Vibe Island, measured frame by frame from recordings of the app:

- Size: `spring(response: 0.36, dampingFraction: 0.9)` opening and `0.95` closing — about 90% in 0.2 s, settled by 0.35 s, under 1% overshoot.
- Corner radius 10 collapsed, 14 open (`easeOut`, 0.3 s); fixed 6 pt concave shoulders outside the shape.
- Layers fade by opacity only (0.15 s in, 0.1 s out) and are laid out at the shape's current width on every frame, so titles truncate to the moment's width instead of overlapping. No blur or scale.
- The centering frame must sit inside the size animation; otherwise the shape jumps to its final position while its width is still animating.
- The ears ride the shape's edges and fade within ~80 ms when opening.
- Pixel art is drawn on whole pixels: 1 pt cells (2 px on Retina), one path per colour so fractional scales leave no seams.

Only a blocked ram animates. Nothing animates while the notch is collapsed and every agent is idle or done.

## Cross-cutting concerns

### Testing

- **Unit tests** (`swift test`) cover every pure piece: protocol decoding against recorded fixtures, an in-process fake Herdr server for the client and runtime, refresh scheduling with an injected clock, row building, title cleaning, the presentation reducer, geometry and preferences.
- **End-to-end tests** (`Tests/E2E`) start a disposable session named `perch-e2e`, drive agent states with `pane.report_agent` (no real agents needed), and check `perchctl watch` output for latency and lifecycle. They only ever write to their own session and always stop and delete it.
- **Smoke test** (`scripts/smoke.sh`) builds and launches the app against the default session read-only, and checks it stays out of the Dock, matches `herdr agent list`, and quits cleanly.
- **`scripts/perf.sh`** samples CPU in five scenarios. It moves the pointer unless run with `--static`.
- **Test hooks:** with `PERCH_TEST_HOOKS=1`, the app listens for distributed notifications that expand or collapse the notch without pointer events. `PERCH_HERDR_ROOT` points the app at another directory, such as a single demo session. Both are off in normal launches.

### Privacy

The repository is public. Test fixtures, sample data, the settings previews and the README recordings use fictional agents, titles and projects only, never real ones from a developer's machine.

### Performance

Each session costs one subscription connection and a snapshot every 3 s while idle (well under a millisecond). Animations run only while something is visible and moving. The idle target is under 0.5% CPU and 60 MB of memory.

### Settings

Stored in `UserDefaults` under: `compactStyle`, `displayPlacement`, `peekOnFinished`, `cleanTitles`, `followReduceMotion`, `launchAtLogin`. Missing or unknown values fall back to defaults; keys from older versions are ignored. Settings change presentation only; nothing that affects correctness (polling, socket paths) is configurable.

### Licensing

Perch is GPL-3.0. Parts of the Herdr client and terminal activation derive from NotchAgent (Apache-2.0, see `LICENSES/`); the overlay window and pointer handling follow open-vibe-island (GPL-3.0). Derived files say so in a header, and `NOTICE` lists every source, including the agent marks.
