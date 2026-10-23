# TODO

v1 之后的候选功能（2026-10-20 确认排期待定）。都只读 Herdr 状态，不注入 hooks。

- [ ] **智能抑制**：用户正看着该 pane 时（`AgentInfo.focused` 为 true 且前台是终端），新 Blocked 不弹出 Peek。
- [ ] **跟进提醒**：Blocked 持续超过阈值（例如 1 / 2 / 5 分钟，可设置）仍未处理时，再弹一次 Peek，卡片注明已等待多久（原型见 `designs/perch-peek/` 的"跟进提醒"场景）。用 `AgentRow.since` 计算。
- [ ] **空闲清理**：长时间 Idle 的 Agent 在列表中折叠或隐藏（阈值可设置），只影响视图层过滤。

## 提醒与呈现（2026-10-23）

- [x] **Peek 速览**：Blocked、完成与连接问题只弹出相关卡片，悬停长成完整列表；Peek 是唯一的提醒方式（architecture.md §6.3）。
- [ ] **设置页布局优化**：About 以 README 为基础重做，其余页面一并梳理。

## 开源发布（2026-10-23）

- [x] **README 素材**（2026-10-23）：`overview.gif`（卡住弹出 Peek → 悬停展开，四种状态各一个）与 `peek.gif`（卡片叠加、处理后消失），用 `scripts/demo.py` 以虚构 Agent 的演示 Session 录制。截图不再单独做。
- [x] **中文 README**（2026-10-23）：`README.zh-CN.md`，两版顶部互相链接；英文版改动时同步更新。
- [x] **转公开并发布**（2026-10-23）：仓库 `Hariketsu/herdr-perch` 已公开，`v0.1.0` 以 DMG 发布（未公证、仅 Apple 芯片；README 写了首次打开的放行方法）。
- [ ] **发布 v0.2.0**：Peek 与无刘海屏高度修复目前只在 main 上。
- [ ] **公证与更多分发渠道**：需要 Apple 开发者账号；之后可考虑 Homebrew cask。
- [ ] **macOS 26 图标**：`Resources/AppIcon.icon` 已就绪但未打包（见 `scripts/make-icon.py` 开头注释），升级到 macOS 26 或发布前再决定。
