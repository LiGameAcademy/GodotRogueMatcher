# 当前工程目录

按功能组织代码和场景，同一功能的规则、配置类型与表现放在所属模块；不再使用scripts/作为第二套分类入口。

```text
res://
├─ main.gd / main.tscn      应用启动
├─ gameplay/
│  ├─ game.gd / game.tscn   单局组装
│  ├─ board/               状态、规则、匹配、生成、协调与BoardView
│  │  ├─ cell/             Cell场景及同名脚本
│  │  └─ piece/            ChessPiece场景及同名脚本
│  ├─ run/                 RunController/RunState、modes只读模式、补棋、记录与回放
│  ├─ scoring/             ScoreLedger、ScoreEntry
│  ├─ items/               道具类型、索引、放置、效果、conditions/、effects/
│  ├─ progression/         经典门槛、stages挑战配置/状态/结果、候选与38项技能Resource
│  ├─ skills/              Ability触发适配、爆炸/引信/根行动组合与只读配置
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

目录归属与运行生命周期是两件事：仍保留现有Autoload名称及兼容桥。glow_effect.gd属于表现辅助，沿用现有实现，不因路径整理修改参数。

迁移28个代码/场景文件及关联.gd.uid，UID内容保留。project.godot、场景、preload及data/item中的脚本引用同步更新。无业务继续留在scripts/、scenes/、prefabs/；不留跳转副本。addons及历史docs中的示例不作为当前工程路径。

后续新增代码直接进入功能目录，可复用场景与同名入口脚本并置。不要再创建scripts/global、scripts/resources或scripts/gameplay。

各阶段如何落到这些目录，见[目录迁移记录](docs/quality/directory_migration.md)。
