# #119 单形状试玩包验证证据

2026-10-24。基础#183提交acad1edbdcde118f9aa0c30f28374ee80ecb0e09，受测代码50f9f77653e8f3ee953c312e6feefe4457715bf7。Godot4.7.2 / GUT9.6.0；无界面固定60FPS，进程用户目录隔离于.godot/issue119-screening/。

- full-output.log：完整123脚本、905/905、26830断言、261.544秒、退出0；summary.json汇总、script-results.json逐脚本统计。最终无SCRIPT ERROR/Parse Error/Failed/Resource或ObjectDB泄漏。
- import.log/import2.log解析与UID导入。target.log规则6项470断言；target2.log规则+界面14项972断言；target3.log增加六个15行动机器人窗15项1176断言；target4.log修复记录退出边界最终17项1195断言。各阶段通过，不冒称RED。
- <key>-direct/wrong/overlap/outside.jsonl共24题；free-<key>.jsonl共6个15行动机器人窗，全部0分，不能代表真人体验或正式遭遇率。
- ui-t-overlap/ui-action-limit/ui-time-busy/ui-time-paused四份记录及同名-screening.json侧记，验证真实UI封存；侧记中的人工字段null，非真人结果。
- replay-*.log为71个独立进程精确回放（34新＋37旧v43），summary保存来源与SHA256及退出结果；不声明v42兼容。
- line-counts.json为自有GDScript行数，全部≤500；human-output.log/human-error.log为实际窗口启动快照，human-window.png为已查看的稳定截帧，不代替真人验收。
- manifest.json为原始字节数/SHA256，README不纳入；文本证据禁用换行转换。

完整回归：

```powershell
& $engine --headless --verbose --path . --fixed-fps 60 -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

专项另加-gselect=screening_。单记录独立回放：

```powershell
& $engine --headless --text-driver Dummy --path . -s tools/bot_testing/batch_cli.gd -- replay <记录路径>
```

[试玩包](../../playtesting/issue119_single_shape_kit.md)含主持步骤与答案；[质量结论](../../quality/issue119_screening_kit.md)说明修复、证据限制与未观察。代码与文档最终APPROVE；PR保留作者review不自动合并，O4冻结。
