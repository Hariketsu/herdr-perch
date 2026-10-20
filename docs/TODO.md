# TODO

v1 之后的候选功能（2026-10-20 确认排期待定）。都只读 Herdr 状态，不注入 hooks。

- [ ] **智能抑制**：用户正看着该 pane 时（`AgentInfo.focused` 为 true 且前台是终端），新 Blocked 不自动展开、不 pop。
- [ ] **跟进提醒**：Blocked 持续超过阈值（例如 1 / 2 / 5 分钟，可设置）仍未处理时，再提醒一次（pop 或自动展开）。用 `AgentRow.since` 计算。
- [ ] **空闲清理**：长时间 Idle 的 Agent 在列表中折叠或隐藏（阈值可设置），只影响视图层过滤。
