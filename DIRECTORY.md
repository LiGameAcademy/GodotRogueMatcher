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
└─ addons/                 第三方依赖
```

目录归属与运行生命周期是两件事：仍保留现有Autoload名称及兼容桥；RunController现已接管基础规则，Ability完整迁移留M3。glow_effect.gd属于表现辅助，沿用现有实现，不因本次路径整理修改参数。

迁移28个代码/场景文件及关联.gd.uid，UID内容保留。project.godot、场景、preload及data/item中的脚本引用同步更新。无业务继续留在scripts/、scenes/、prefabs/；不留跳转副本。addons及历史docs中的示例不作为当前工程路径。

后续新增代码直接进入功能目录，可复用场景与同名入口脚本并置。不要再创建scripts/global、scripts/resources或scripts/gameplay。
验证：Godot 4.7.2下42项GUT测试、812个断言全部通过；主场景直接启动退出码0。日志为忽略目录.godot/directory-tests.log与directory-main.log。无界面验证采用Dummy文字后端，未替代窗口视觉验收。

M3新增gameplay/skills/（定义、实例、爆炸规则及content资源）、skills/debug/（F6固定盘面）、presentation/explosion_visual/（同名场景与脚本）。普通新局无核心；F6将爆向上移一格触发70分连锁。
