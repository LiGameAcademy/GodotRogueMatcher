# 当前工程目录 · 2026-10-05

按功能组织代码和场景，同一功能的规则、配置类型与表现放在所属模块；不再使用scripts/作为第二套分类入口。

```text
res://
├─ main.gd / main.tscn      应用启动
├─ gameplay/
│  ├─ game.gd / game.tscn   单局组装
│  ├─ board/               状态、规则、匹配、生成、协调与BoardView
│  │  ├─ cell/             Cell场景及同名脚本
│  │  └─ piece/            ChessPiece场景及同名脚本
│  ├─ run/                 RunController/RunState、结果数据、GameManager兼容桥
│  ├─ scoring/             ScoreLedger、ScoreEntry
│  ├─ items/               道具类型、索引、放置、效果、conditions/、effects/
│  ├─ progression/         升级与候选流程
│  └─ presentation/        现有辉光辅助
├─ ui/                     HUD、弹窗、UIManager
├─ data/item/              现有道具.tres配置，保留单一来源
├─ assets/                 共享素材
├─ localization/           翻译
├─ tests/                  规则与场景集成验证
├─ tools/bot_testing/      策略配置、批次/分析CLI、独立结果观看器
├─ tools/telemetry_analysis/ 分析事件校验、去重、CSV与分布报告
├─ services/telemetry/     独立本地采集、规则事实投影与界面观察
└─ addons/                 第三方依赖
```

目录归属与运行生命周期是两件事：仍保留现有Autoload名称及兼容桥；RunController现已接管基础规则，Ability完整迁移留M3。glow_effect.gd属于表现辅助，沿用现有实现，不因本次路径整理修改参数。

迁移28个代码/场景文件及关联.gd.uid，UID内容保留。project.godot、场景、preload及data/item中的脚本引用同步更新。无业务继续留在scripts/、scenes/、prefabs/；不留跳转副本。addons及历史docs中的示例不作为当前工程路径。

后续新增代码直接进入功能目录，可复用场景与同名入口脚本并置。不要再创建scripts/global、scripts/resources或scripts/gameplay。
验证：Godot 4.7.2下42项GUT测试、812个断言全部通过；主场景直接启动退出码0。日志为忽略目录.godot/directory-tests.log与directory-main.log。无界面验证采用Dummy文字后端，未替代窗口视觉验收。

M3新增gameplay/skills/（定义、实例、爆炸规则及content资源）、skills/debug/（F6固定盘面）、presentation/explosion_visual/（同名场景与脚本）。普通新局无核心；F6将爆向上移一格触发70分连锁。

M4：gameplay/progression/拥有首片技能定义、content配置、候选及目标、奖励状态与应用规则；ui/popup_skill_choice同名场景/脚本显示正常技能三选一。F7打开下一门槛奖励，F6仍为爆炸盘面。82项测试、1101断言通过；完整存档与播放导演留后续阶段。

试玩反馈调整：progression/progression_config.gd及content/progression_config.tres管理累计目标；content/instant_thin.tres接入一次性疏整。Board只协调一条待执行输入，不改变BoardState的权威占格。当前配置与模型差异见../GDC/32-试玩反馈与节奏输入调整.md。

GDC33：run/commands/定义移动与技能选择意图；run/recording/规范化快照并写本地JSONL；run/replay/重算共享规则并定位首处差异。progression/progression_state.gd拥有本局累计门槛，LevelUpSystem仅转发及协调界面。tools/bot_testing/只在显式运行时测试或观看，不自动代玩发行游戏，详见工具README。
