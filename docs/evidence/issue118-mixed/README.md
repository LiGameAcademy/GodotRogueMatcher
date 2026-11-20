# 跨模板混合验收证据

2026-10-24。基线#182：4feb0d065a2a20eaabbb93598c0d4283f2464f4a；受测代码d14aed3dc8f551d9d8d20a8e0a876fd6282a202d。Godot4.7.2 / GUT9.6.0，完整无界面回归固定60FPS；进程级用户目录隔离于.godot/issue118-mixed/。

- full-output.log：完整121脚本、888/888、25635断言、256.373秒、退出0；summary.json实际汇总、script-results.json逐脚本统计。最终无SCRIPT ERROR/Parse Error/Failed/Resource或ObjectDB泄漏。
- import.log/import2.log最终引用/UID检查。target.log首轮固定题与测试探针失败（意外交叉X、快照字段、安全前缀阶段），target2.log初版17/17、471断言，target3.log控件同步17/17、487断言，target4.log最终18/18、498断言。
- 八份新记录为lt/plus-x/independent/nested及各baseline。lt84、plus-x126、independent50、nested176，基线依次0/0/0/50；126/176保留真实经典额外奖励。
- replay-*.log为37个独立进程结果，8新＋29旧v43。summary保存原记录来源/SHA256/实测结果/退出码。仅当前规则，不声明v42兼容。
- line-counts.json为376个自有GDScript行数，最大474，均不超过500。
- human-output.log/human-error.log为可见桌面启动快照；human-window.png为已查看的稳定引擎截帧，不等于真人体验通过。
- manifest.json为原始字节数/SHA256；README不纳入；文本证据禁用换行转换。

完整回归：

```powershell
& $engine --headless --verbose --path . --fixed-fps 60 -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

专项另加-gselect=mixed_template。逐记录独立回放：

```powershell
& $engine --headless --text-driver Dummy --path . -s tools/bot_testing/batch_cli.gd -- replay <记录路径>
```

[质量结论](../../quality/issue118_mixed_acceptance.md)和[试玩准备包](../../playtesting/issue119_screening_preparation.md)说明责任/范围/未观察项。复审问题已修复并复验，最终APPROVE；PR留作者review，不自动合并，O4冻结。
