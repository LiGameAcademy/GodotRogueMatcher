# #18 压力基线与合法技能窗口

本工具复用 RandomLegal/Greedy，不修改压力、目标、技能配置或界面。适用 Godot 4.7.2；规则版本取 JSONL Header，分析版本为 `model-analysis-v2-paired-choice`。工具数据不能验收首玩者理解、退出动机或视觉反馈。

## 正常池基线

从工程目录运行，输出目录每次取新名称。`--count` 是每策略局数；默认两策略，`--strategy=random|greedy` 可单独重跑。经典模式加 `--legacy`。策略 RNG 使用 seed+100000，独立于规则 RNG。

```powershell
$godotExe = 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --headless --path . -s tools/bot_testing/batch_cli.gd -- --count=3 --seed=1000 --moves=80 --output=.godot/bot-smoke --record-output=.godot/bot-smoke/records --telemetry-output=.godot/bot-smoke/telemetry --commit=<代码提交>
```

先每模式、每策略3局，再改成100种子探索。80是本次工程试验的**工具行动上限**，不是死亡规则；默认工具上限仍为300。命令/超时上限取只读 BotConfig，每局独立复制。阶段/q/P/carry 为当前规则观察，不能外推到其他目标表或策略。

每局都从**磁盘**重读并精确重算。机器人没有游戏界面的刷新驱动，所以 BotRunner 在安全点刷新 Recorder/Telemetry 的待写批次。规则异常、回放错误、记录/采集写入错误均返回失败。排除损坏探索批次，不以其已落盘前缀代替完整局。

`pressure_summary.json` 是本切片的压力报告：按模式/规则配置/策略配置/提交分组；阶段分母分成 reached、completed、board_full_unmet、censored。`completion_rate_known` 仅以已达标或满盘的已决样本为分母，截尾单列；达标行动 P50/P90 仅来自达标局。原始 q/P/carry 数组、种子、记录路径、终态指纹保留。技能有候选/选择/安装后行动暴露、可归属计分事件与首条证据；未出现/未选/无计分归属各自可见。能力 attempt 和非计分首次作用仍缺失，不能把0分视为未触发。

`runs.csv`、`turns.csv`、`rewards.csv` 和旧 `summary.json` 保留兼容；旧 summary 按结束状态拆组，不用它计算全批阶段完成率。重检自定义目录：

```powershell
& $godotExe --headless --path . -s tools/bot_testing/batch_cli.gd -- analyze .godot/bot-smoke/runs.csv .godot/bot-rechecked .godot/bot-smoke/records
```

## 成对窗口的确切问题

从真实三选一的安全检查点重放完整前缀，重建棋盘、能力实例、账本、阶段、待领奖、冻结目标/生成令牌及所有规则 RNG。`restore_prefix` 只接受完整 Checkpoint 且无终局；普通 `replay` 仍拒绝缺 Footer 的文件。A/B各自重建，配置资源不被运行时改写，非法/同卡/缺候选对照拒绝。

A取得或升级目标技能，B保持目标原等级、取得同一三选一的另一张合法卡。没有删除发动机，没有留下不合法的后置技能，没有伪造“跳过奖励”。**这估计的是该技能相对于指定替代卡的选择差异，包含机会成本，不是孤立技能的普适卡价。** 对照技能写进输出和 Excel 的分组范围。

两边从相同独立策略种子开始，各自重新决策；不复制未来命令，不窥看规则未来 RNG。`hold-target-v1` 策略在两边后续三选一都不再取得目标技能：若原策略选中目标，选真实候选中第一张非目标卡；无合法替代时截尾。该限制和工具预算写入策略配置指纹，不混普通基线策略。

从**应用卡之前**计分/空间，所以即时作用进入窗口。H=20/50分别计量有效移动+主动爆破，选卡不算行动；截止点必须完成根行动，不能在补棋前截成完整H。自然满盘/末阶段结束保留真实终态和实际行动数；其后无新游戏行动，终态是已知的。超时/命令上限/无合法策略动作是外部截尾，整窗 Δ 为 null，仅另存已观察前缀差。

整窗差只登记一次：`ΔS=(S_A_end-S_start)-(S_B_end-S_start)`；`ΔF=F_A_end-F_B_end`。不再另加即时/间接/延寿收益。每分支独立ID，`parent_run_id` 保留原局簇；H/技能等级/对照卡/协议/配置分别分组。同局多个分叉不算多个独立原局。0、负数、null不同；触发 attempt 缺失仍null。

```powershell
# 从完整正常局记录取首个真实候选，不覆盖原文件。
& $godotExe --headless --path . -s tools/bot_testing/batch_cli.gd -- paired '<完整JSONL路径>' .godot/paired-real --seed=1000 --strategy=greedy
# 固定F6棋盘+诊断目标表，来源明确fixture，不作为正常抽卡可获得率。
& $godotExe --headless --path . -s tools/bot_testing/batch_cli.gd -- paired fixture .godot/paired-fixture --seed=23
```

每个首选候选与下一候选配对，分别跑20/50；输出完整规则 JSONL、`.pair.json`、`telemetry/`。所有分支落盘后再精确回放，只有 treatment 发一条 `paired_window_resolved`，control 不重复登记差值。其他技能/升级可对任意实际 offer Checkpoint 调用 `PairedWindow.compare`；未出现的候选拒绝，不合成池供给。

## Excel 与验收

将 `telemetry/` 输入既有 `tools/telemetry_analysis/model_import.py`。事件Reader校验、源索引、簇数、H和对照技能保留到新增观测页；每个整窗只有一条分数/空间观测。原输入/公式不改，默认不选择自动参考组；样本不足不会覆盖待测参考。完整命令 JSONL 用于回放，不混成 telemetry。

本次运行证据见 [issue18-results.json](evidence/issue18-results.json)。回归覆盖状态/RNG/待领奖/锁定计划隔离、非法前缀与对照、完整落盘回放、重复复现、截尾null、应用前基线、长局批量刷新，以及H/对照卡/原局簇/负收益的统计分组。固定盘面和正常池分叉分别留来源。没有证明技能未触发：attempt 分母尚缺，这是显式缺失，不会被零收益掩盖。

O1后续仍需 #19 离线参考曲线与作者试玩验收；首玩者理解、前三阶段选择作用、失败原因与下一局调整由真人试验收口。#18完成不自动勾完O1全部KR。
