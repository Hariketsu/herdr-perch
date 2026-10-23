<p align="center">
  <img src="docs/assets/icon-256.png" width="128" height="128" alt="Herdr Perch icon">
</p>

<h1 align="center">Herdr Perch</h1>

<p align="center">
  Your <a href="https://github.com/herdrdev/herdr">Herdr</a> agents, perched in the MacBook notch.
</p>

<p align="center">
  English · <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <a href="https://github.com/Hariketsu/herdr-perch/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/Hariketsu/herdr-perch/ci.yml?branch=main&style=flat-square&label=CI" alt="CI"></a>
  <a href="https://github.com/Hariketsu/herdr-perch/releases/latest"><img src="https://img.shields.io/github/v/release/Hariketsu/herdr-perch?style=flat-square&color=555" alt="Latest release"></a>
  <a href="https://github.com/Hariketsu/herdr-perch/releases"><img src="https://img.shields.io/github/downloads/Hariketsu/herdr-perch/total?style=flat-square&color=555" alt="Downloads"></a>
  <br>
  <img src="https://img.shields.io/badge/macOS-14%2B-555?style=flat-square&logo=apple&logoColor=white" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6-555?style=flat-square&logo=swift&logoColor=white" alt="Swift 6">
  <a href="https://github.com/herdrdev/herdr"><img src="https://img.shields.io/badge/Herdr-0.9.5%2B-555?style=flat-square" alt="Herdr 0.9.5+"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Hariketsu/herdr-perch?style=flat-square&color=555" alt="License"></a>
</p>

<p align="center">
  <img src="docs/assets/overview.gif" width="660" alt="An agent gets blocked and peeks out of the notch; hovering opens the full list, one agent in each state">
</p>

## What it does

- **Every agent at a glance.** A pixel ram in the notch takes the colour of your most urgent agent; hover to see them all, grouped into *Needs you*, *Done*, *Working* and a folded *Idle*.
- **Speaks up when it matters.** When an agent asks for approval or input, finishes, or Herdr goes away, the notch peeks out with just that card; hover to see everything. Peeks for finished agents can be turned off in Settings.
- **One click back.** Click a row to focus that agent's pane in Herdr and bring your terminal to the front.
- **Zero setup.** Perch finds every local Herdr session by itself and follows them as they start, stop and reconnect.
- **Stays out of the way.** No Dock icon, no extra processes; it idles at well under 1% CPU.

<p align="center">
  <img src="docs/assets/peek.gif" width="520" alt="Peek: a finished and a blocked agent stack up as cards, then leave once handled">
</p>

## Requirements

- macOS 14 Sonoma or later on Apple silicon. Built for MacBooks with a notch; on other displays Perch draws a notch-shaped panel at the top of the screen.
- [Herdr](https://github.com/herdrdev/herdr) 0.9.5 or later, running locally.

## Install

Download `Herdr-Perch-<version>.dmg` from the [latest release](https://github.com/Hariketsu/herdr-perch/releases/latest), open it and drag **Herdr Perch** into **Applications**.

The app is not notarized yet, so macOS blocks it the first time you open it. To allow it, open **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to the message about Herdr Perch. You only need to do this once.

## How it works

Perch is a read-only companion. It connects directly to each Herdr server's Unix socket, subscribes to agent status events, and shows exactly what `herdr agent list` reports — it never guesses a state Herdr did not report. It does not install hooks into your agents, change Herdr's configuration, or start any processes. The only thing it ever asks Herdr to do is focus a pane, and only when you click a row.

Agent titles from tools such as oh-my-pi carry prompt characters and Nerd Font icons (`π > 󰈙 …`); Perch strips them for display. You can turn this off in Settings.

Clicking a row brings your terminal forward if it is Ghostty, Terminal, iTerm2, kitty, WezTerm, Alacritty or Warp.

## Settings

Open Settings from the gear in the expanded notch, or from the ram in the menu bar.

| Setting | Options |
|---|---|
| Notch style | Clean (count) · Dots (one per agent) · Counts (per state) |
| Rows | Grouped · Detailed · Compact |
| Peek when an agent finishes | On · Off |
| Display | Built-in Notch Display · Main Display |
| Clean agent titles | On · Off |
| Follow system "Reduce motion" | Off · On |
| Launch at login | Off · On |

## Build from source

Requires Xcode 16 or later (Swift 6).

```sh
git clone https://github.com/Hariketsu/herdr-perch.git
cd herdr-perch
scripts/bundle.sh          # builds dist/Herdr Perch.app
open "dist/Herdr Perch.app"
scripts/make-dmg.sh        # optional: dist/Herdr-Perch-<version>.dmg
```

Tests:

```sh
swift test                                                   # unit tests
uv run --project Tests/E2E pytest Tests/E2E -p no:cacheprovider   # end-to-end, against a throwaway Herdr session
```

`perchctl dump | watch` prints the state Perch derives from Herdr, which is handy for debugging. Design notes (in Chinese) live in [`docs/spec`](docs/spec).

## Acknowledgments

- [Herdr](https://github.com/herdrdev/herdr), for an API that makes companions like this possible.
- [Vibe Island](https://vibeisland.app) and [open-vibe-island](https://github.com/Octane0411/open-vibe-island) : the reference for the notch's look and motion; the overlay window and pointer handling are derived from open-vibe-island (GPL-3.0).
- [NotchAgent](https://github.com/ykushch/notchagent) : parts of the Herdr client and terminal activation are derived from it.
- [Lobe Icons](https://github.com/lobehub/lobe-icons) and [oh-my-pi](https://github.com/can1357/oh-my-pi) : the agent marks (MIT).

## License

[GPL-3.0](LICENSE). Herdr Perch is an independent project and is not affiliated with or endorsed by Herdr. Agent marks are trademarks of their respective owners and are used only to identify agents.
