# TODO

v1 之后的候选功能（2026-10-20 确认排期待定）。都只读 Herdr 状态，不注入 hooks。

- [ ] **智能抑制**：用户正看着该 pane 时（`AgentInfo.focused` 为 true 且前台是终端），新 Blocked 不自动展开、不 pop。
- [ ] **跟进提醒**：Blocked 持续超过阈值（例如 1 / 2 / 5 分钟，可设置）仍未处理时，再提醒一次（pop 或自动展开）。用 `AgentRow.since` 计算。
- [ ] **空闲清理**：长时间 Idle 的 Agent 在列表中折叠或隐藏（阈值可设置），只影响视图层过滤。

## 开源发布（2026-10-23）

- [ ] **README 素材**：录演示 GIF（收起 → 悬停展开 → Agent 变 Blocked 自动弹出 → 点一行跳回 Herdr pane），截图（收起三种样式、分组列表、完成反馈、设置页）。用虚构 Agent 和标题的演示 Session 录，不暴露真实项目名；替换 README 里的两处 TODO 占位。
- [ ] **中文 README**：`README.zh-CN.md`，英文版定稿后再写。
- [x] **转公开并发布**（2026-10-23）：仓库 `Hariketsu/herdr-perch` 已公开，`v0.1.0` 以 DMG 发布（未公证、仅 Apple 芯片；README 写了首次打开的放行方法）。
- [ ] **公证与更多分发渠道**：需要 Apple 开发者账号；之后可考虑 Homebrew cask。
- [ ] **macOS 26 图标**：`Resources/AppIcon.icon` 已就绪但未打包（见 `scripts/make-icon.py` 开头注释），升级到 macOS 26 或发布前再决定。
