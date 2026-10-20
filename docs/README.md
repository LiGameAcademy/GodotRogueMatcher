# Development notes

Skill Lines is a five-in-a-row roguelite preview. Start with the [English README](../README.md), [中文说明](../README.zh_CN.md), and [directory guide](../DIRECTORY.md).

- [Core rules and UI regression tests](../tests/)
- [Web export tool](../tools/export_web.ps1)
- [Core System documentation](../addons/godot_core_system/docs/)
- [Localization configuration](../localization/game.csv)
- [Git分支与发行策略](branch_strategy.md)：里程碑开发分支、feature/fix、发行候选、修复回流与清理。
- [0.0.3兼容链路与迁移基线（#132）](quality/issue132_baseline.md)：四链路消费者、状态所有权、运行证据及#133/#134边界。
- [0.0.2 O3整体验收、最终组合画面与待补证据](o3_acceptance.md)
- [GameTheme与构筑卡视觉](game_themes.md)、[流动背景](background_flow.md)、[棋盘信号试验](board_signal.md)
- [比例清理试调与600分试玩观察](percent_clear.md)
- [爆破手预告颜色修复](core_preview_color_fix.md)
- [过关嘉奖与目标奖励采集](goal_score_bonus.md)
- [Preview artwork and real gameplay screenshots](preview/)

The former Matrix Link design index referred to files absent from this repository and has been retired. Current behavior is defined by the shipped gameplay resources and tests; planned missions and mobile support are not preview features.

- [0.0.2 Web发布候选验收](release_0_0_2.md)：构建身份、浏览器实测与剩余发布验收。
