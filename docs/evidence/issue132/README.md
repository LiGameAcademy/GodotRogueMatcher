# #132核查证据 · 2026-10-20

对应[四链路核查报告](../../quality/issue132_baseline.md)。游戏基线为`3f07699`；测试提交`2992ae9`只增加分支策略文档。引擎`4.7.2.stable.official.ed1daf0bf`，GUT9.6.0，CoreSystem提交`4ba6dda22ef8fad2e9864438073306adf0747c17`。没有运行代码修改。

## 实际结果

| 运行 | 结果 | 证据 |
| --- | --- | --- |
| 首次启动 | 退出1：GUT不识别`-gexport_path`，没有执行测试；工具参数错误 | [首次输出](baseline-output.log) |
| 移除无效参数后的完整自有回归 | 76脚本，556测试，555通过、1失败；19871/20287断言通过；GUT计时201.449秒，进程退出1 | [完整原始输出](baseline-output-run2.log)、[逐脚本统计](script-results.json) |
| 技能卡脚本独立复测 | 5测试，4通过、1失败；780/1196断言通过；0.965秒，退出1。仍是`test_all_skill_descriptions_fit_card_and_popup_at_base_viewport`，416项卡片操作提示/稀有度包含关系断言失败 | [独立原始输出](cards-isolated-output.log) |
| 固定种子CLI烟测 | seed132000、随机合法策略、阶段模式、12行动；退出0，落盘后读回精确回放OK；0分/0次奖励选择，`censored/move_limit`，不当作通关或奖励体验证据 | [CLI输出](bot-output.log)、[runs.csv](bot-runs.csv)、[汇总](bot-summary.json)、[原始命令记录](bot-record.jsonl) |

六组必要基线均有当前实际运行覆盖：核心循环27/27、奖励表现4/4、目标交互6/6、场景命令4/4、跳过恢复10/10、阶段场景6/6、继续挑战7/7、Composite8/8、压力补棋10/10；其余脚本结果见逐脚本统计。单项通过不代表对应0.0.3新契约已经实现。

全套和独立卡片测试均失败，尚未定位根因；没有修改断言、排除测试或以历史全绿覆盖本次结果。该失败归后续#129/#133实际卡片修改与#136回归核验，编辑器人工观察仍待执行。

引擎每次启动输出系统根证书读取错误；未将它当作测试断言失败根因。完整测试内的旧prism_tower无效果配置警告、受控文件写失败/采集限额诊断均保留原输出，相关测试通过；未发现额外脚本解析失败。未运行Web、实际编辑器点击或截图工具产出。

## 复现命令

在实际游戏仓库目录运行，使用PowerShell。以下`APPDATA`修改只作用于当前启动命令所在进程环境；不同测试使用不同沙箱目录，避免接触正常玩家数据。

```powershell
$godotExe = 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
$env:APPDATA = Join-Path (Get-Location) '.godot/issue132/sandbox'
New-Item -ItemType Directory -Path $env:APPDATA -Force | Out-Null
& $godotExe --headless --path . --fixed-fps 60 --log-file .godot/issue132/baseline-engine-run2.log -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit *> .godot/issue132/baseline-output-run2.log
```

独立复测将APPDATA改为`.godot/issue132/isolated-sandbox`、日志改为`cards-isolated-engine.log`和`cards-isolated-output.log`，将`-gdir=res://tests -ginclude_subdirs`替换为`-gtest=res://tests/integration/test_skill_cards.gd`，其余参数相同。首次失败命令与完整回归命令相同，但额外带`-gexport_path=res://.godot/issue132/gut-report.json`，日志名为`baseline-engine.log`及`baseline-output.log`；该无效参数不应继续使用。

CLI把APPDATA改为`.godot/issue132/bot-sandbox`后运行：

```powershell
& $godotExe --headless --text-driver Dummy --path . --log-file .godot/issue132/bot-engine.log -s tools/bot_testing/batch_cli.gd -- --count=1 --seed=132000 --moves=12 --strategy=random --output=res://.godot/issue132/bot --record-output=res://.godot/issue132/bot/records --telemetry-output=res://.godot/issue132/bot/telemetry --commit=2992ae92856f71b0f1aa4fd19015952565f12405 *> .godot/issue132/bot-output.log
```

CLI内部`BatchJob`已通过`RuleReplay.replay_file`读回落盘文件，见`tools/bot_testing/batch_job.gd:63`后路径。原始记录另归档为`bot-record.jsonl`，可用同版CLI的`replay <文件路径>`独立核对；重新代玩产生新run身份是预期行为。

## 静态证据与预算

- [兼容消费者搜索](compatibility-consumers.txt)：对`gameplay/ui/services/tools/tests`及`project.godot`搜索旧单例名；不包含第三方addons整库扫描。具体消费者用途由报告逐项解释，命中数量不等于运行消费者数量。
- [信号、await和延迟入口](signals-and-waits.txt)：Board、推进器、Game、GameManager、LevelUpSystem、ItemEffectSystem、UIManager及Popup；另检查场景/资源引用和Autoload，不能以文本未命中直接删接口。
- [19个相关文件物理行数](line-counts.json)：当前全部≤500，未改运行文件。
- [逐脚本统计](script-results.json)从原始完整输出移除ANSI控制码后提取；完整日志保留原样，失败结论以原始结果为准。
- [manifest](manifest.json)记录上述机器产物字节数和SHA256，不包含本说明或manifest自身。此证据目录使用局部`.gitattributes`禁用换行转换，保证原始字节及哈希可跨checkout核对；不改变游戏文件的换行策略。原始日志带ANSI颜色码，查看工具可能隐藏控制字符。

可追溯计时间隔为文档归档提交2026-10-20 12:21:45至证据汇总12:29:04（Asia/Hong_Kong），7分19秒，包含完整GUT201.449秒；提交前的静态阅读未独立计时，不虚构为人工工时或未来修复估算。首轮3人时、必要补证2人时预算未触顶；无因预算缩减必要案例。当前已解释范围内关键写入口，六组基线及失败归属足以划界#133/#134；布局根因和人工视觉留后续，不将其标为已解决。
