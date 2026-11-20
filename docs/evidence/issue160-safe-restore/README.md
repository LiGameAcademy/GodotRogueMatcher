# #160 安全点载荷与独立恢复候选证据

基线8e4ebe5；独立clone，不共享worktree登记。源码身份见source-sha256.json，代码后续不变时文档/证据追加不重写受测身份。

交付日志只去除终端颜色转义及行尾空白；测试、诊断和失败内容保留，原始日志仍在本地`.godot/`。

- combination.log：5脚本60/60、1754断言、10.88s、退出0；新增19、Store20、命令/回放12、六流7、异形回放2。无SCRIPT ERROR、Parse Error或退出资源保留提示；根证书及既有故意日志写失败诊断原样保留。
- first-float-rejection.log：首次14/15，保存冻结候选时temporary_verify_failed，旧档未假成功。float-package-fixed.log为完整精度字符串封装修复后的15/15、180断言、退出0。
- insufficient-score-fixture.log：新增探针使用55分爆破盘，未达到真实100分发奖门槛；不是续局成功证据。随后改用已有mixed_nested真实可达冻结点，没有改生产门槛。
- stale-action-fixture.log：有限次数夹具初始化已有行动，探针旧expected_action_id被正式拒绝；按当前行动构造命令后最终组合通过。
- cold-import.log：冷缓存字体及根证书诊断保留，导入退出0；不以该日志宣称Web或运行验收。
- review.md：独立预审、修正及最终增量审阅结论；非GitHub批准或CI。

执行使用Godot4.7.2 ed1daf0bf/GUT9.6，独立APPDATA为本副本`.godot/restore-sandbox`，没有作者真实档案。命令：

```powershell
$env:APPDATA = Join-Path (Get-Location) '.godot/restore-sandbox'
& 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --fixed-fps 60 --log-file .godot/restore-combination.log -s addons/gut/gut_cmdln.gd -gtest=res://tests/rules/test_run_checkpoint_codec.gd,res://tests/rules/test_checkpoint_store.gd,res://tests/rules/test_commands_replay.gd,res://tests/rules/test_run_random_streams.gd,res://tests/rules/test_shape_unlock_replay.gd -gexit
```

只完成无UI的独立规则候选保存/恢复。当前没有玩家继续入口、Board/Game接管、采集resume/session、正常退出协调、真实跨进程重启/强杀或Web。完整前缀/4096条/15MiB内部载荷及实际包大小、2秒事后耗时限制见质量说明。#160保持OPEN，不将组合回归当完整SV01～SV10。
