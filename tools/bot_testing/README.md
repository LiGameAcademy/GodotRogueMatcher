# 命令记录、规则回放与机器人测试

适用 Godot 4.7.2。正常游戏默认录制 `user://run_records/<run_id>.jsonl`，每个命令、安全阶段和终局刷新；重试、F6切换和关闭场景会结束旧记录。F6来源为fixture，F7会先关闭正常采样，再进行调试加分。写入失败显示“本局记录不完整”，游戏继续。

从实际 Godot 工程目录运行，替换以下引擎路径为本机控制台可执行文件：

```powershell
$godotExe = 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --headless --text-driver Dummy --path . -s tools/bot_testing/batch_cli.gd -- --count=5 --seed=1000 --output=user://bot_reports/smoke
```

`--count` 为**每策略**局数，范围1～1000；两种策略均运行，`--seed` 为连续局种子起点，策略种子为局种子+100000。默认限制300次有效移动、3000次命令/推进、60秒；`--moves` 覆盖移动上限，其余参数在只读 `bot_config.tres` 配置。每局复制策略配置，游戏随机流不参与策略决策。

每局落盘后重新读回并重算全部规则记录，再输出 `runs.csv`、`turns.csv`、`rewards.csv`、`summary.json`。运行错误或回放失败返回非零退出码；上限是 `censored`，未满盘无合法移动是 `censored/no_legal_move`。`completed/board_full` 只对应真实满盘；异常诊断保留为 `rule_error`。

验证指定日志：

```powershell
& $godotExe --headless --text-driver Dummy --path . -s tools/bot_testing/batch_cli.gd -- replay 'user://run_records/某局ID.jsonl'
```

这会拒绝引擎、规则/内容/候选版本或配置摘要不匹配。回放重算出生、候选、目标、技能应用和计分；记录结果只用于逐项比较。64位种子、RNG state和标识均用十进制字符串，截断文件不补造结束记录。首处差异包含序号、阶段、字段和期望/实际值。

重检已生成批次并重新汇总（通过原runs.csv定位本地JSONL）：

```powershell
& $godotExe --headless --text-driver Dummy --path . -s tools/bot_testing/batch_cli.gd -- analyze 'user://bot_reports/smoke/runs.csv' 'user://bot_reports/smoke_verified'
```

独立的**结果观看**入口：

```powershell
& $godotExe --path . res://tools/bot_testing/result_viewer.tscn -- 'user://run_records/某局ID.jsonl'
```

也可在编辑器运行 `result_viewer.tscn` 后输入JSONL路径。支持下一步、自动播放和1/4/16倍速度，使用现有BoardView演出完成屏障消费出生、移动、消除和爆炸；它不提交游戏命令、不计分、不抽选。只要求支持的记录schema，旧配置可以观看，不能因此宣称当前规则回放成功。首批v1日志无移动路径时按安全点重建盘面；损坏结构明确拒绝。没有增加游戏内撤销或通用表现导演。

真人计时按暂停、技能等待、忙碌、输入区间记录；缓冲等待是附加指标，不能再加到总时长。机器人计算耗时单列。报告分开统计来源、策略版本、策略/游戏配置摘要和结束分类，记录技能出现/选择次数、条件选择率、即时分与净空位。永久技能因果收益、后续H窗口对照、真人15分钟体验仍需后续专项采样，不能用机器人耗时代替。

支持正常技能池与F6专项。旧道具兼容接口或外部直接改棋盘/账本没有命令记录，不属于回放承诺范围；构建信息无法确认时如实记 `unknown`。日志只保存在本地，未上传。

完整自动化测试：

```powershell
& $godotExe --headless --text-driver Dummy --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```
