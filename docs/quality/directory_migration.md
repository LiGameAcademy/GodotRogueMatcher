# 目录迁移记录

现行路径以仓库根目录[DIRECTORY.md](../../DIRECTORY.md)为准。下文只保留各阶段落到目录时的记录，不作为新代码入口。

## 功能目录归位 · 2026-10-09

当时仍保留现有Autoload名称及兼容桥；RunController已接管基础规则，Ability完整迁移留M3。glow_effect.gd属于表现辅助，沿用现有实现，不因本次路径整理修改参数。

迁移28个代码/场景文件及关联.gd.uid，UID内容保留。project.godot、场景、preload及data/item中的脚本引用同步更新。无业务继续留在scripts/、scenes/、prefabs/；不留跳转副本。

验证：Godot 4.7.2下42项GUT测试、812个断言全部通过；主场景直接启动退出码0。日志为忽略目录.godot/directory-tests.log与directory-main.log。无界面验证采用Dummy文字后端，未替代窗口视觉验收。

## M3

新增gameplay/skills/（定义、实例、爆炸规则及content资源）、skills/debug/（F6固定盘面）、presentation/explosion_visual/（同名场景与脚本）。普通新局无核心；F6将爆向上移一格触发70分连锁。

## M4

gameplay/progression/拥有首片技能定义、content配置、候选及目标、奖励状态与应用规则；ui/popup_skill_choice同名场景/脚本显示正常技能三选一。F7打开下一门槛奖励，F6仍为爆炸盘面。82项测试、1101断言通过；完整存档与播放导演留后续阶段。

## 试玩反馈

progression/progression_config.gd及content/progression_config.tres管理累计目标；content/instant_thin.tres接入一次性疏整。Board只协调一条待执行输入，不改变BoardState的权威占格。当时的配置与模型差异见[32 试玩反馈与节奏输入调整](../../../GDC/历史归档/设计快照_2026-10-08/32-试玩反馈与节奏输入调整.md)。

## GDC33

run/commands/定义移动与技能选择意图；run/recording/规范化快照并写本地JSONL；run/replay/重算共享规则并定位首处差异。progression/progression_state.gd拥有本局累计门槛，LevelUpSystem仅转发及协调界面。tools/bot_testing/只在显式运行时测试或观看，不自动代玩发行游戏，详见工具README。

## M5-A

presentation/presentation_director同名场景/脚本管理本局播放队列；playback_plan_builder复制结果，presentation_step承载步骤，presentation_config管理1×/2×与出生时长。导演和BoardView由Board共同协调；正常局及旧补棋显示入口统一。F8切换速度，完整政策和存档仍待后续。

## 0.0.2 O1

`run/modes/`维护经典无尽/阶段挑战的只读定义；`progression/stages/`维护阶段表、每局状态和结算快照。正常局默认挑战，菜单切换创建新RunController；规则推进仍只有一个入口。`ui/stage_text.gd`格式化阶段/终局文本，HUD与菜单只消费规则状态。`batch_cli.gd`在Autoload就绪后加载`batch_job.gd`，规则/回放异常返回失败状态；`--legacy`选择经典对照。
