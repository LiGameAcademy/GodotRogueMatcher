# #87 首批最小复现与后续边界

2026-10-29；交接基线`9589563051f845e2c710f9522f4deed76307a265`。本批不重跑450局，不将旧450局/约524MB分析故障写成已修复。小批只检验工具链，不是随机校准或构筑实验。

## 当前已实际执行

| 输入/版本 | 操作 | 本轮事实 |
| --- | --- | --- |
| 旧集成基线 | random，seed777000，1局，3行动上限；落盘后回放 | censored，回放OK，REPORT后实际退出0；未复现历史退出故障 |
| 同一旧基线采集 | analysis_cli读取该局telemetry | 1局、30事件、0错误，实际退出0 |
| 本批六流工作树 | random，seed777000～777002，3局，20行动上限 | 三局均18行动真实满盘、0分、0次选卡，三份落盘回放OK，实际退出0；不能据此推断候选机会或技能强度 |
| 本批采集 | analysis_cli读取三份telemetry | 3局、558事件、0错误，实际退出0 |
| 同一新日志复制两份 | analysis_cli读取同目录两个相同内容文件 | 只统计1局、186事件；不翻倍，实际退出0 |
| 一份有效新日志＋一份坏JSONL | analysis_cli | 有效局保留，坏文件列invalid_telemetry_json诊断，实际退出1，未伪装完整成功 |

旧基线第一次启动发现`SkillMarkResult`缓存未刷新等解析错误，虽有REPORT也**不计通过**；刷新Godot类缓存后另以clean日志与退出码留证。运行日志中的系统证书读取错误属于本地环境诊断，未隐藏。两者均没有证据可解释历史450局故障。

## 可重跑命令

从实际游戏/worktree目录执行，`$godotExe`指本机Godot4.7.2控制台程序。每次使用新的输出目录，避免混入其它批次；需要隔离APPDATA的测试环境单独设置，不改作者的正常存档。

```powershell
& $godotExe --headless --text-driver Dummy --log-file .godot/probe-engine.log --path . -s tools/bot_testing/batch_cli.gd -- --count=3 --seed=777000 --moves=20 --strategy=random --output=.godot/probe/report --telemetry-output=.godot/probe/telemetry --record-output=.godot/probe/records --commit=<实际提交>
& $godotExe --headless --text-driver Dummy --log-file .godot/analysis-engine.log --path . -s tools/telemetry_analysis/analysis_cli.gd -- .godot/probe/telemetry .godot/probe/analysis
```

必须同时记录完整命令、游戏提交/规则/配置/策略、PID、开始/结束时刻、退出码、stdout/stderr、输入文件数量/字节数和报告摘要。出现REPORT后仍存活时先保留进程/CPU/内存快照，不把输出字符串当成功；只停止本批明确记录PID，不能结束作者编辑器或其它目标进程。

## 大批分析的真实缺口与下一最小定位

静态检查发现`TelemetryReport`会保留全部事件、每个event_id对应的完整JSON文本，写CSV时再构造七表行。这说明总输入量增长时内存没有当前硬上限，但**不是已复现的524MB故障根因**。本批未改写分析器，也未宣称流式/有界大批分析完成。

下批先定位原450份输入和原命令/版本/REPORT后进程证据，先记录文件清单、字节数与SHA256，不用新采样替代旧故障。保留旧规则版本做分析，不尝试由新六流执行器精确重算旧日志。

1. 从原输入选择1份、重复同份及1～3份受控组合，分别记录耗时/峰值内存/退出；损坏行、冲突ID、缺终局保留诊断。
2. 若最小批可用，再在既定预算内增加**读取的文件数**定位资源增长；不重玩450局。超过测量预算停止并记截尾，不能无界等待。
3. 依据实测选择逐文件/有界分块或流式聚合；同一run/event/reward/父局身份贯穿去重，完整前缀可补齐、冲突隔离，版本/配置/策略严格分组。不能简单拼接summary或把不同组均值合并。
4. 先用小批与重复输入核对runs.csv/成功选择/机会，坏输入明确非零；再对旧450份完成完整有界汇总。未取得这些证据前，#87大批出口仍未完成。

候选H/B/Q/related/fills_gap/s/V、限幅W与逐槽分母接#85/#86；新字段不能由旧算法日志伪造。恢复父局/分支去重依#160，本批未实现。没有候选机会保持null，不能因本轮随机机器人0次选卡填成“技能无收益”。

## 兼容测试的调整

新协议必须拒绝旧日志精确重算。原`docs/evidence/issue119-screening/`与`tests/fixtures/issue128_legacy_v43.jsonl`保持原字节；旧v43记录另验只读观看/拒绝重算。报告/sidecar/去重/CLI回归改由`tests/support/screening_current_records.gd`通过当前正式命令在测试隔离目录生成全新记录，Header显式synthetic、真人观察仍null，不把测试当实际UI用户或正式筛选。

自然固定样本的结果也不移植：当前六个free合成窗口可能有自然匹配，按本次Footer和实体增减核对；仍单独覆盖“有完整机会且得分0是有效观察”，不强迫新协议重现历史全零分布。
