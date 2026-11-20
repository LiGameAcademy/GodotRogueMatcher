# 空心环与经典奖励交界验收证据

2026-10-24。基础合并树a19b16e34e66118863892dc7dd3f7952985db6c0（按作者授权顺序合并#175/#176/#177）；受测代码01a982da15568e05518053ac91753de4b32ba142。

Godot4.7.2 / Compatibility，GUT9.6.0，无界面回归固定60FPS，进程级APPDATA/LOCALAPPDATA隔离于.godot/issue118-ring/。

- full-output.log：115脚本、839/839、24843断言、199.419秒、退出0，无新增解析错误或Resource/ObjectDB泄漏；summary.json为实际脚本/测试/断言/耗时/退出码；script-results.json为逐脚本统计。
- import.log为导入检查。target.log/target2.log保留新测试夹具的失败：弹窗offer未安装、重复命令检查跨过后续命令、生产profile探针使用错误。target3.log最终29/29、274断言；这些失败不冒称生产规则RED。
- line-counts.json核对自有GDScript物理行数，每个不超过500。
- 新记录ring-unlock-record.jsonl（19）、order-ring-u.jsonl/order-u-ring.jsonl（各23）、center-playground.jsonl（17）、move-playground.jsonl（20）。保留104分触发的真实额外经典选卡，未抬高阈值或清空奖励；真实UI等待第二个候选组后继续流程。
- replay-*.log为24个独立进程精确回放：五份新记录＋十九份既有T/＋/×/Z/S/U记录。summary中保存来源、SHA256与成功结果，不代表v42兼容。
- human-output.log/human-error.log为实际可见桌面启动快照；human-window.png是稳定引擎截帧，已查看。启动成功、自动测试或截图不代替作者完整体验验收。
- manifest.json包含证据原始字节数和SHA256，README不纳入；文本证据禁用换行转换。

完整回归：

```powershell
& $engine --headless --verbose --path . --fixed-fps 60 -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

专项另加-gselect=ring_。回放逐记录使用新进程、隔离目录：

```powershell
& $engine --headless --text-driver Dummy --path . -s tools/bot_testing/batch_cli.gd -- replay <记录路径>
```

桌面试玩入口tools/ring_template_playground/ring_template_playground.tscn，编辑器打开按F6。选择解锁环→104分→再选择解锁U，完成后观察盘面/恢复；中心同色保留、空盘只补3枚、移动题免补。完整步骤见../../quality/issue118_ring_template.md。

复审APPROVE，无阻断项，重点核对八格、中心排除、唯一方向、U/环材料消耗、104分奖励屏障、重开隔离及旧profile/v43兼容。新PR保留作者review不自动合并。O4当前状态核对也在quality文档，模板属于O2，不自动关闭O4五项KR。
