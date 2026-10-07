# 当前回归 · 2026-10-07

Game Juice M4：17脚本、98项集成测试/1093断言通过（`.godot/score_float_final_tests_output.log`）。`test_score_floats.gd`覆盖倍率主分/额外精确拆分、零收益、提示色/面板隔离、边缘定位与整段运动避让、无离场奖励位置、暂停/低特效/加速/过期、重复事件、取消/重试及可选长尾。原生真实规则样本100+10+10=120，Web F6结算70分正常。

Game Juice M3：集成16脚本、91项测试/1047断言通过（`.godot/juice_m3_final_tests_output.log`）。新增`test_board_juice.gd`覆盖棋子/棋格ShaderMaterial实例与模板隔离、ghost出生透明度、取消路径不改已提交规则、暂停光环及低特效停止脉动。实际Web移动/补棋与F6连锁结算通过，规则完整基线沿用下方M2结果。

Game Juice M2：完整28脚本、229项测试/6170断言通过（.godot/hud_m2_final_tests_output.log）。真实补棋预告使用独立内容随机流与锁定前缀，v5快照/回放包含内容计划；覆盖UI读操作、免补棋、数量/权重变化、核心条件回退、满盘与重试。提示音借用插件池的原process_mode只保存一次，复借/结束/取消均有验证。

Game Juice M1技能卡：最新集成目录15脚本、83项测试/991断言通过（`.godot/skill_cards_release_tests_output.log`），增加32项真实冻结目标布局、卡面样式隔离与暂停时真实正文鼠标点击。以下217项为此前完整规则基线，不把本轮集成子集当成完整回归。

Godot 4.7.2 / Compatibility，GUT 9.6.0。32项运行技能、五档稀有度、核心供给/主动爆破、引信与连锁组合、HUD/精确回放/机器人/采集接通后，完整26个脚本、217项测试、5991断言通过。日志`.godot/skill_depth_verified_output.log`。新增`tests/rules/test_demolition_build.gd`覆盖32项取得、合法前置、稀有度、顺序/去重/终止与状态隔离；主动行动埋点见`test_telemetry.gd`。

```powershell
& 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --fixed-fps 60 --log-file .godot/tests.log -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

以下保留各轮历史范围，不覆盖当前运行状态。完整发布/真人理解与平衡仍待验收。

# 核心玩法循环修复 · 2026-10-04

本次为旧 Demo 修复基线，先于 M1 棋盘数据化开发。引擎为 Godot 4.7.2 stable，项目使用 GDScript / Forward Plus，入口仍为 main.tscn。

## 根因与修复

- 棋子占格被标为 AStarGrid2D 障碍，旧查询直接从障碍起点寻路。4.7.2 实测返回空路径。查询期间仅放行起点并恢复障碍，目标障碍、同格、越界仍拒绝；矩形网格统一 x=cols、y=rows。
- 移动期间锁定输入，初始化完成才开放输入；无路径不推进回合。移动完成后取消选择再消除，避免取消选择动画打断消除。
- 生成从真实空位集合采样，每枚出生立即查线，继续完成三次生成；无空位或第三次收束后满盘才失败。移除78枚提前结束与“剩三格就停止生成”。
- 棋子演出不自行释放占格对象，由消除/物品移除入口清理引用并释放；重试清理道具注册、节点、路径障碍、分数、回合和升级状态。
- 跨门槛奖励排队，移动/回合结束/生成后的安全点逐次显示；生成失败不补救命选择。奖励填满棋盘时立即结算，停止后续奖励并禁止进入下一回合；每次三张不同内容ID，点击选择只应用一次；反馈使用独立Tween。
- main.tscn删除重复UIManager实例，保留原Autoload；Game协调结算弹窗的重试信号并向下调用Board。UIManager可在暂停时处理弹窗。

## 规则边界

本次恢复旧 Demo 循环，保留旧基础分函数、道具倍率及“本回合正分免补棋，空盘仍补棋”的原型规则。没有实现GDC的新计分账本、统一Ability、独立随机流、Tag候选或阶段目标；不能将本次结果标为M1～M4验收通过。

## 自动化验证

复用仓库GUT 9.6.0。测试文件为tests/test_core_loop.gd，14项测试、224个断言全部通过，退出码0：

- 障碍起点可移动，查询后恢复；同格拒绝。
- 点击处理入口完成移动，只推进一个回合并补三枚；堵路不改分数/占格/回合。
- 五连50分、四连不消、斜向五连、交叉线去重；消除后引用有效。
- 全清后补棋；最后空位生成、出生五连先消除再检查满盘。
- 满盘结算、失败不发待发奖励、结算按钮发起重试及状态隔离。
- 不同候选ID、跨两个门槛顺序弹窗、双击只应用一次、道具占格计数。

从工程目录运行：

```powershell
& 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe' --headless --path . --log-file .godot/core-loop-tests.log -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_core_loop.gd -gexit
```

路径按本机安装调整。运行日志保存在忽略的.godot目录。沙箱出现系统根证书读取提示；未出现脚本解析、失效引用或Tween运行错误。旧道具若没有effect_config但在MatchSystem/SpawnManager里实现，会保留已有警告。

本次通过主场景实例化及点击处理入口的自动化验证，尚未人工点击实际窗口、检查视觉效果或导出构建。后续M0仍需完成规则版本、迁移清单及实际窗口验收。

## Git范围

仅提交本次修复、测试及记录；工作区已有框架子模块迁移、旧docs删除和其他个人配置不纳入本次提交。外层教程更新对应说明并记录游戏子模块提交。

## M1 · 2026-10-04
最新36项测试、783个断言全部通过。使用相同GUT命令，将-gtest参数替换为-gdir=res://tests -ginclude_subdirs，日志使用.godot/m1-tests.log。PathfindingManager已退役，当前由BoardRules直接读取BoardState计算路径。窗口试玩与导出待验证。详见外层GDC/acceptance/m1-棋盘规则验收.md。


## 2026-10-05 · M2第一批实现

已接入ScoreLedger及N(N+5)基础分，额外得分不免普通生成；42项测试、812个断言通过。完整回合控制器仍待迁移，M2尚未全部验收。详见GDC/acceptance/m2-计分与生成条件验收.md。

目录迁移后测试入口不变，运行脚本改在gameplay/与ui/；详见[当前目录](../DIRECTORY.md)。


## 2026-10-05 · M2回合规则接入

RunController/RunState已接入，本局持有棋盘、账本、阶段、回合、待发奖励与补棋随机流。移动消除和基础计分先提交再播放；54项测试、904个断言通过，主场景启动通过。旧Ability仍在兼容边界，完整随机重放尚未实现。见GDC/acceptance/m2-回合规则迁移验收.md；历史阶段说明以本节更新为准。


## 2026-10-05 · M3爆炸基础实现

核心/引信离场爆炸、按代及来源ID排序、重叠去重、B=0的爆炸E计分已接入。68项测试、1013个断言通过；F6可加载T02移动盘面。旧三选一暂未替换，完整组合与播放导演未实现。详细见GDC/acceptance/m3-爆炸基础验收.md。
## M4首片技能奖励

test_skill_rewards.gd验证首片合法过滤、权重算例、冻结目标、独立随机流、去重应用及10000种子初局检查。test_core_loop.gd覆盖正常技能弹窗、连续奖励、F7、失效候选刷新和重试取消旧回调。最终82项测试、1101断言通过，日志.godot/m4-verified-tests.log；主场景启动日志.godot/m4-main.log。

2026-10-05试玩反馈：97项测试、1387断言通过，日志.godot/feedback-verified-tests.log。新增输入缓冲、奖励前清理、目标重验、疏整和累计门槛检查；连续奖励旧用例改为260分以跨新100/250门槛。主场景启动退出码0，日志.godot/feedback-main.log。此处为无界面集成验证，实际节奏和视觉手感仍待真人试玩。

## GDC33命令记录回放与机器人


新增test_commands_replay.gd覆盖请求幂等/拒绝、检查点、64位精度、篡改/截断/版本/真实结束分类、写入失败、策略不污染活随机、爆炸轨迹和固定种子复跑。test_command_scene.gd验证真人快慢演出与无UI命令一致、跨门槛后重试/F6保留旧日志。test_result_viewer.gd验证快慢结果观看、不重复计分、旧配置可看而重算拒绝，以及损坏记录明确失败。

完整回归114项、1941断言通过（.godot/c33-reviewed.log）；最终新增损坏观看日志用例包含在观看专项3项23断言中（.godot/viewer-validated.log），完整回归与专项均没有脚本错误或孤立节点。首批两策略各100局、保留种子各3局均落盘读回回放一致。使用方式见[机器人工具说明](../tools/bot_testing/README.md)，采样与限制见外层GDC/acceptance/c33-命令记录回放验收.md。

## GDC35本地采集 · 2026-10-06最终验收

test_telemetry.gd验证采集不污染规则、曝光与选择去重、计时及输入、链式回合、文件错误与精度、插件JSON独立使用、实验分组和同局前缀合并；test_telemetry_scene.gd覆盖实际展示与重试。最终完整回归130项测试、2063断言通过，日志.godot/d35-verified-tests.log。使用说明见[本地采集](../services/telemetry/README.md)与[分析工具](../tools/telemetry_analysis/README.md)。

## M5-A最小表现导演

test_presentation_director.gd验证队列身份、空队列、重复完成、取消、暂停、结果复制、并行动画屏障和F8快慢规则/采集一致。测试核心奖励与F7改为等待实际导演完成，避免用固定帧数猜测新出生动画已结束。F8切换1×/2×，使用说明见[表现模块](../gameplay/presentation/README.md)，细节见外层GDC/acceptance/m5a-最小表现导演验收.md。
最终完整回归138项测试、2103断言通过，日志.godot/m5a-delivery-tests.log。
