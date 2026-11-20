# #132 · 0.0.3兼容链路与迁移基线

2026-10-20。父目标#117；本片只核查与留证，不改运行脚本、场景、Resource、插件或规则版本。设计依据为课程工作区`architecture/代码质量指导.md`的QC01～QC06，以及#133/#134已确认契约。本文记录实际消费者，不能将其视为0.0.3规则实现或整版验收。

## 基线与环境

- 开发起点：`develop/0.0.3`，`3f07699a3eb1a7ea29cfb4d85709efcc34eebf63`；与0.0.2发行源`b131358`文件树一致。当前核查分支`feature/132-compatibility-baseline`。
- 测试提交：`2992ae92856f71b0f1aa4fd19015952565f12405`，只增加分支策略与索引，游戏文件仍为上述稳定基线；#162未合并试作不在本次树中。
- 实际执行：Windows，Godot `4.7.2.stable.official.ed1daf0bf`，GUT `9.6.0`；项目声明Compatibility、版本0.0.2；规则标识`run-commands-v34-special-conversion`。
- 测试进程把`APPDATA`定向至`.godot/issue132/*-sandbox`，主基线用`.godot/issue132/sandbox`；不读取或改写作者正常用户配置。未停止已有编辑器进程。
- 子仓库开工时只有已授权的分支策略文档改动。外层16个已修改设计文件、2个未跟踪美术文档继续保留；不纳入游戏提交。
- 行数记录见[证据目录](../evidence/issue132/README.md)：19个相关自有脚本均未超过500物理行；`Board`489行，`Game`414行，核心循环测试447行。#133需按职责迁出，不能继续向Board堆入奖励协调。

## 权威状态与调用链

路径均相对游戏仓库；行号由证据对应提交固定。消费者分类：正式游戏、调试fixture、测试、工具/机器人、兼容保留。静态搜索是线索，下面结论同时依据方法实现、场景连接及实际测试。

### A · 奖励、候选与弹窗

| 入口/位置 | 调用者及条件 | 读写/权威拥有者 | 迁移去向与停止旧写入条件 |
| --- | --- | --- | --- |
| `gameplay/progression/progression_state.gd:11` `check_score`；`gameplay/run/run_controller.gd:197` `check_rewards` | 经典模式匹配、技能提交、advance及GameManager.publish_score；阶段模式不走经典门槛 | 规则：本局progression、pending_rewards；重复检查按门槛推进，非第二份分数 | 保留规则入口；#133不能用UI显示时点重新产生奖励 |
| `run_controller.gd:337` `_settle_stage`及继续挑战命令 | 完整行动收束；继续挑战合法命令 | 规则：StageState凭证/awaiting_reward、本局pending；继续挑战同run | #133保存原continuation，保持阶段与经典奖励安全点区别 |
| `gameplay/progression/skill_offer_generator.gd:63` `generate` | RunController.prepare_offer，机器人与规则测试同入口 | 规则：候选/目标/排列RNG、active_offer、next_offer_id；已有组原样返回 | #86/#161负责临时生成成功后提交、少张/一次重建；#133不从弹窗清offer或解析文案重抽 |
| `gameplay/board/board_run_flow.gd:5` `continue_run` | Board._execute_action及continue_challenge；每步等表现后advance | 表现驱动，offer分支await旧LevelUpSystem；不是独立规则状态机 | #133由Game协调弹窗；Board/推进器传递步骤、已提交结果，不拥有奖励等待 |
| `gameplay/progression/level_up_system.gd:117` `resolve_pending_rewards` | 正式BoardRunFlow；F7；截图工具；多项集成测试 | 混合：全局is_resolving、演出/UI await、offer准备、全局暂停、满盘通知 | #133移出正式弹窗等待和奖励写入；调用者全部接新入口后停止该路径，不能只改方法名字 |
| 同文件`:151` `_apply_selected_skill`及`:148`选色转发 | Popup信号，绑定board/旧run/popup；旧回调测试直接调用 | 创建命令；reward_id却在回调时读当前consumed+1；中文错误匹配后直接清active_offer再生成 | #133绑定原run/reward/offer/弹窗代次；成功命令才消费。#86/#161提供规则重建结果，UI不决定重建 |
| 同文件`:9–29`代理setter、`:36`reset、`:188`generate_options | Autoload初始化，Board.retry/F6；旧循环/进度测试；ItemRegistry和旧候选去重测试 | setter直接写当前GameManager.run；旧item_pools及全局随机仅旧查询 | #133移除正式写入消费者；旧池测试改局部fixture/明确退役后再清。不能因不是正式候选就宣称无消费者 |
| `ui/ui_manager.gd:21/55` open/close；`ui/popup_skill_choice.gd:66/126/191` | 单例打开选卡与终局弹窗；Game附加设置、技能池、卡片飞入信号 | 表现：popup指针、临时选择、_submitted、暂停。close调用accept_selection，closed唤醒旧等待；关闭本身不执行SkillRules | #133分开成功、查看、关闭、销毁；Game持有显示与输入上下文，关闭不耗奖励，仍能回到选卡 |
| `gameplay/progression/skill_rules.gd:104` `apply`；`run_controller.gd:213`命令入口 | 真人选卡、BotRunner、RuleReplay及规则测试 | 本局校验run/action/command/reward/offer；成功才写取得历史、pending--、consumed++、清offer；重复命令返回缓存 | 保留单一消费入口；#133更换协调器不能绕过命令、重试身份或重复消费保护 |

正式链：`Board执行命令 → BoardRunFlow.advance → LevelUpSystem等待 → UIManager/Popup → ChooseSkillCommand → SkillRules → 已提交结果表现 → 原继续位置`。

Game当前只在`gameplay/game.gd:286`为弹窗连接settings/pool/card_acquired及主题，不拥有奖励流程；新协调职责应在场景侧按真实需要拆分，不预建通用UI框架。

### B · 计分、进度与终局

| 入口/位置 | 实际消费者 | 状态分类与当前事实 | 保留/退出条件 |
| --- | --- | --- | --- |
| `gameplay/scoring/score_ledger.gd:16` `commit` | AbilityResolver匹配/爆破/扫线、DyeRules、DemolitionRules、GoalCompletionRules、GameManager.add_score | 规则唯一总账；事件ID及独立ScoreEntry副本；表现不重复commit | 保留；#133/#134回归盘面、账本、奖励与因果，不能以静态计数替代验证 |
| `gameplay/run/game_manager.gd:41/48` add_score/publish_score | F7、UX截图、旧EffectAddScore、测试；正式Board.finish_presentation发布已提交分数 | add_score提交`legacy_extra`；publish广播总分并检查经典奖励。score/turn/is_game_over读取本局，并非第二份权威 | 分开规则写与通知；调试/工具转显式fixture后才收口兼容加分。保留HUD通知可按证据决定 |
| 同文件`:31/52/63/69` reset/finish/start/end | Board新局/重试、BoardRunFlow、旧SpawnManager、LevelUpSystem；测试主动调用start/end | reset可替换run或重置计数；finish含通知闩锁及规则finish；start/end调用规则并广播，旧道具订阅广播 | #134正式推进维持RunController.advance，停止旧订阅副作用后可保留通知；不得直接删除所有Autoload |
| 同文件`:17` piece_count；`gameplay/board/board.gd:486`更新 | Board/旧SpawnManager写入，Game连接piece_count_changed到HUD | 表现缓存，真实占格/寻路/满盘使用BoardState；未发现该缓存反向驱动规则 | 可保留显示桥；以实际读写追踪为依据，不把缓存判成重复权威 |
| `gameplay/scoring/legacy_score_modifiers.gd:5`；`run_controller.gd:142`space_compressor分支 | AbilityResolver.calculate调用；旧content_id fixture及旧道具生成兼容 | 规则读取BoardState里的旧ID，并非ItemEffectSystem节点列表；正常新技能CATALOG未创建这六种旧道具 | #134/#135逐消费者决定保留/退役，不借清UI注册顺带删除所有内容兼容；space_compressor随机归#161消费者核查，不激活旧内容 |
| `gameplay/progression/stages/stage_state.gd:60` settle；`gameplay/game.gd:158`终局UI | RunController唯一完整行动入口；GameManager.game_overed到Game | 规则先检查满盘再判达标；Game等待已提交演出再开结果弹窗；继续挑战走同run命令 | 保留；#133不得因奖励得分连过阶段、提前结算或丢继续挑战奖励 |

### C · 补棋、行动与输入恢复

| 入口/位置 | 实际消费者 | 权威状态/副作用 | 迁移出口 |
| --- | --- | --- | --- |
| `run_controller.gd:294` advance；`:90/95`预告/行动冻结；`:123`spawn_one | 正式BoardRunFlow、机器人、回放与规则测试 | 本局continuation/action_refill_count、SpawnState令牌/有限修正/RNG、BoardRules占格；出生逐枚查线，整批规则计算后表现 | 保留唯一正式推进；#133记录原继续位置；#134不复制旧SpawnManager另造循环 |
| `gameplay/run/spawn_state.gd:17/48/74` ensure/consume/modifier | RunController正式规则；HUD/池界面只preview副本；测试直接构造 | 内容随机独立，计划尾部复用；有限次数仅实际补棋扣减 | 保留数量、免补/全清、出生后继续和显示一致业务断言 |
| `gameplay/board/spawn_manager.gd:18` spawn_random_pieces | `tests/test_core_loop.gd`三处；`tests/integration/test_explosion_loop.gd`一处；正式BoardRunFlow未调用此循环 | 独立扣修正并逐枚spawn/present，调用全局终局；与正式advance重复，且不是同一阶段冻结路径 | #134先把4处测试调用迁到正式advance/本局计划，保留原测试意图，再关闭该写入口；必要常量/只读用途另核对 |
| `gameplay/board/board.gd:376/476`执行/延迟缓冲；`:254`finish_presentation | 鼠标移动/主动技能、延迟缓冲、导演完成 | 表现can_selected/_generation/_turn_in_progress/缓冲；命令先提交，再播放；call_deferred带generation与实体，过期拒绝 | #133保持重试/取消后旧回调不得恢复新局输入；不能把动画耗时变成规则判断 |
| `gameplay/presentation`导演/BoardView；Game.skip | 正常/快速/低特效/略过/恢复集成测试 | 消费结果，重建显示需同步旧道具节点映射；不是第二份BoardState | #134替换映射测试，保留恢复后显示/规则一致及A/B隔离验证 |

### D · 旧道具、fixture与工具

| 入口/位置 | 消费者与触发 | 已核对副作用 | 迁移/保留条件 |
| --- | --- | --- | --- |
| `project.godot:22–30` Autoload；`gameplay/items/item_registry.gd:7/11` | 正式启动自动注册6项；Board.retry/F6清列表/reset/再次注册 | 旧池资源创建与写入；注册不等于进入正式SkillOfferGenerator.CATALOG | #134正式开局/重试/F6退出旧注册；测试所需配置转局部fixture，再决定删除Autoload |
| `gameplay/items/item_effect_system.gd:24`订阅 | 自动连接GameManager.turn_started/ended和MatchSystem.match_made；Board._on_match_visualized广播已播放匹配 | 全局placed_items + group查Board；ON_PLACE/TURN/MATCH可执行加分/改色/移除。当前正常池不出旧道具，但订阅与正式信号链仍在 | #134必须停止正式订阅副作用；仅清空列表不算退出；不以“当前没旧物品”证明无路径 |
| `gameplay/items/item_placer.gd:33/55/99` | 旧道具放置/移除接口；核心循环测试显式调用 | 全局randi选空位，Board.place/remove写权威占格并同步视图，注册ON_PLACE | 先将测试迁局部配置/显式上下文，再关闭正式放置写入口；不得静默空实现 |
| `gameplay/board/board.gd:186/225/246/250` | 移除、重建显示、离场、匹配表现；核心循环及skip恢复测试验证映射 | 同步/清除ItemEffectSystem节点列表、发旧匹配信号；可能由表现触发旧规则效果 | #134迁出旧道具后关闭同步/旧触发，替换结构断言为显示、占格、收益只提交一次 |
| `gameplay/items/effects/effect_add_score.gd:17`；dye/destroy的apply | 旧配置、ItemEffectSystem；核心循环测试直接构造旧效果 | 通过GameManager/Board写分数、颜色与占格；旧染色使用全局随机；不是正式AbilityEffectRunner | 业务验证保留，但测试改局部上下文；#134不把items目录机械重写成Effect |
| `gameplay/board/match_system.gd:5/8/15` | Game/Board读取MIN_MATCH_COUNT，测试查询/旧消除包装，ItemEffectSystem订阅match_made | 常量、规则查询与委托；信号本身不计分，但旧订阅可能写规则 | 可保留常量/必要通知；旧自动触发退出与接口删除分别判断 |
| `gameplay/board/board.gd:119/153`；`gameplay/game.gd:122` | F6/F10/F11与F7，debug开关；旧循环/回放/采集测试 | fixture建新run，终结旧记录；F7经典模式debug加分排除自然样本 | #133替换奖励协调调用，#134移除旧注册；保持fixture来源、旧记录及重试隔离 |
| `tools/ux_capture/{skill_ux_capture,demolition_capture}.gd` | 截图场景显式加分、调用LevelUpSystem.resolve_pending_rewards | 仅工具，但依赖将迁出的接口；其余capture通过GameManager.reset_game绑定fixture | #133迁工具调用再停旧入口；本片只静态核查，未把截图生产当运行验收 |
| `tools/bot_testing/bot_runner.gd:9`；RuleReplay；RunSnapshot | CLI、机器人测试、记录观看和重算工具 | 机器人直接advance/execute_command，不开UI；策略随机独立。Snapshot五流/冻结计划是记录投影，不能完整恢复独立对象 | #133保持同规则命令，无UI；#160/#161补安全恢复/六流/兼容清单；禁止以回放成功代替存档已完成 |

## 运行证据与必要六组

完整结果、命令、日志哈希见[证据说明](../evidence/issue132/README.md)。本次76脚本556测试：555通过、1失败，19871/20287断言通过；失败为技能卡布局，独立复测一致。固定种子CLI烟测退出0，落盘读回回放OK；六组覆盖如下，不以历史0.0.2报告数字代替本次结果。

| 组 | 固定输入/现有测试 | 必须保留的观察与目标差异 |
| --- | --- | --- |
| Q1 开局/移动/匹配/补棋 | `test_core_loop`合法点击和堵路；`test_board_rules`固定四连/五连/交叉；`test_pressure_loop`冻结数量/全清/出生后剩余批次 | 非法输入不动盘面/RNG/行动；直线匹配按当前规则；保留实际次数及预告尾部 |
| Q2 奖励/取消/连续选择 | `test_reward_presentation`；`test_skill_target_ux`冻结offer=11/reward=3；`test_core_loop`260分跨两个经典门槛/重复确认 | 候选展示不重抽，取消不取得，一次成功耗一次；旧“单个失效即刷新”测试是待改目标差异，不能作为新规则验收 |
| Q3 爆破/扫线/组合 | `test_explosion_rules`、line系列、`test_ability_composite_effects`清色→染色顺序/固定失效 | 当前CLEAR可暂存后代、DYE仍完整resolve；当前通过不代表B/S/T新契约已满足 |
| Q4 重试与旧回调 | `test_core_loop.test_old_skill_callback_after_retry_cannot_modify_new_run`；`test_skip_recovery`旧step/代次；`test_command_scene`重试记录 | 旧run回调无效，旧播放完成不放开新局；#133还需补同局旧offer/弹窗代次及销毁清理 |
| Q5 阶段/满盘/继续 | `test_stage_challenge`、`test_stage_scene`、`test_continue_challenge` | 满盘优先，完整行动判关，继续保留棋盘/构筑且奖励一次；不冒充六流或安全续局验证 |
| Q6 fixture/旧兼容/机器人 | 核心循环F7/F6及旧道具重建、SpawnManager测试；`test_commands_replay`；CLI seed=132000/12行动 | fixture不混自然样本；CLI截尾与真实终局分开，命令及读回回放共同验证；旧结构断言需有替代业务覆盖 |

## 当前行为与已确认目标差异

| 当前基线事实 | 已确认目标 / 负责issue | 本片处理 |
| --- | --- | --- |
| 候选强制3张，fallback/槽位分池；生成过程直接推进正式流 | 统一合法池、合法1/2张完整组；三流与身份成功提交 / #85/#86/#161 | 记录差异，#133不可照搬旧刷新策略 |
| 回调按中文目标失效错误清offer、可再次生成；无每reward修复已用字段 | 部分失效不补，全组真实合法失效最多一次成功系统重建 / #86/#133/#161 | 本局负责重建，弹窗只读结果；旧测试预期需随对应实现更新 |
| 后叶和嵌套refresh共用候选target_random；爆破/扫线出队读当前等级 | 动态叶到达时选一次、外层后代屏障、触发时冻结强度 / #118/#120/#135/#161 | #133前不迁Resolver；其后作为独立片验证B/S/T/RC，不承诺普通组合回滚 |
| 五流与XOR派生，新局Board使用全局randi | 非负63位主种子、SHA256命名六流、版本兼容和失败保旧档 / #161/#160 | 本片不合入#162、不升级规则、不改随机序列 |
| Snapshot/回放已有字段，但无完整独立恢复与自动槽接管 | 输入/冻结选卡安全档、单槽备份、失效优先、临时验证后接管 / #160 | 存档行为未实现，不能造迁移前恢复成绩 |

## 后续切片与停手出口

1. **#133奖励归位**：先让本局返回带原身份及继续义务的奖励状态/命令结果；Game协调显示与输入，BoardRunFlow不再等待全局LevelUpSystem。迁真人、F7、截图、机器人与测试消费者；关闭不消费、旧回调、连续奖励、异常清理为必要门禁。O1重建契约与随机提交可独立分片，但不能在切换时留下UI决定重抽的正式写入口。
2. **#134旧写入口退出**：基于#133，先迁4处旧补棋测试、旧道具局部fixture和重建映射测试；退出Board初始化/重试/F6注册、旧回合/匹配自动订阅；验证正式规则只推进一次后再删接口/注册。MatchSystem常量、GameManager必要通知和仍有消费者配置可解释地保留。
3. **Resolver及新功能**：#133完成前不改旧内容分支；之后按#118/#135处理B/S/T/固定动态目标，不把本核查变成整库重构。#136对真实最终合并树回归。

#132的出口是迁移边界和必要基线可追溯，不是所有现存缺陷修完。未覆盖项必须说明影响与归属；影响规则迁移的关键缺证仍阻塞相应片，独立项不被无关问题锁住。

| QC | 本片结论 |
| --- | --- |
| QC01 / QC02 | 四链路的正式、调试、测试及工具消费者已分类；规则/表现/只读边界和仍在订阅的旧副作用已解释。未宣称全仓库无未知消费者 |
| QC03 | 六组必要基线均有本次运行覆盖；完整自有回归555/556，独立确认卡片布局失败。记录可作为迁移对照，不能声称全绿 |
| QC04 | 保留行为和O1/O2/随机/存档目标差异分开列明；没有修改规则或为通过改断言 |
| QC05 | #133先迁奖励/弹窗及其工具消费者；#134再迁4处旧补棋测试和旧道具映射后关闭副作用；Resolver前置保留 |
| QC06 | 计时区间、预算与未覆盖归属见证据说明；布局复核不阻塞纯规则/协调职责迁移，但相关UI验收与最终回归仍有未解决项 |

结论：本片迁移准备证据已具备，待作者review；#132暂保留open，PR使用Refs，不因文档或测试子集宣称O5完成。

## 未覆盖、失败与责任

- 技能卡布局断言在本次headless全套及单脚本均失败：保留失败，不把它归为偶发或仅环境问题。当前根因未定；#129/#133触及卡片显示时需在编辑器复核并保留当前基线，#136最终回归必须处理。它不阻止只迁移规则/协调职责，但阻止宣称UI回归全绿。
- 实际编辑器点击、截图工具产出、真人理解/视觉、Web导出未执行；由后续相关切片和作者试玩留证，不代替O4。当前headless集成会实例化真实main/Game/Board/Popup场景，仍不等同人工视觉验收。
- 新随机协议、异形解锁/恢复、完整存档与备份失效未实现，不列作当前基线通过；由#161/#118/#160分别实施验证。
- 未重跑第三方插件整库测试；仅运行本项目自有测试覆盖到的配置、音效、条件适配和采集路径。无故障证据不扩展插件重构。
- 本次没有删除未合并分支、修改Project排期或关闭实施issue。核查耗时与QC结论随运行结果登记，不能用预算耗尽代替完成。
