# #119 汇总与人工筛选整理工具证据

2026-10-24。基线#184：984f4b078ecf8aaeff86d4a5901ff0717dc0cf6f；受测代码a8dd7e2386337c4cdfc49afb2c21d97eede14aa8。Godot4.7.2、GUT9.6.0，完整无界面回归固定60FPS，进程用户目录隔离于.godot/issue119-report/。

- full-output.log：完整126脚本、930/930、27145断言、344.208秒、退出0；summary.json实测汇总，script-results.json逐脚本统计。最终无SCRIPT ERROR/Parse Error/Failed/Resource或ObjectDB泄漏。
- import.log/import2.log为导入及UID检查。target.log 34/34、1438；target2.log 35/35、1450；target3.log 39/39、1489；target4.log强化门禁后的旧重复测试期望不符（40/41、1501/1502）；target5.log最终42/42、1510。修复详见质量结论。
- final-demo.log实际34条记录汇总退出0；sample-report/三个输出文件，所有人工字段/结论均空。
- blank.log全null标注模板往返退出0，blank-roundtrip-report.json与样例报告逐字段相同。
- negative.log合成无证据retain输入退出2，negative-report.json只有invalid_decision诊断，人工结果及结论仍空；不是作者实际决定。
- 原始34条记录仍在依赖#184的issue119-screening证据目录，summary保存其路径/原始SHA256与摘要SHA256，本片不改原记录。
- line-counts.json核对390个自有GDScript，最大478，全部≤500。
- manifest.json含证据原始字节数/SHA256，根README不纳入；文本证据关闭换行转换。

完整回归：

```powershell
& $engine --headless --verbose --path . --fixed-fps 60 -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

相关回归另加-gselect=screening_。实际样例：

```powershell
& $engine --headless --path . -s tools/screening_analysis/report_cli.gd -- docs/evidence/issue119-screening <新的输出目录>
```

[质量结论](../../quality/issue119_screening_report.md)与[工具说明](../../../tools/screening_analysis/README.md)记录范围、修复和人工空值契约。没有新的真人观察，不认证作者身份、不改变游戏开关或GitHub状态。复审APPROVE，PR保留作者review，O4冻结。
