# O4 / #59：技能定义与运行实例首片

集成分支 `feature/skill-refactor`；本片独立分支 `feat/issue-59-skill-instances`。
仅迁移两张现有卡，保留40项运行目录和当前数值，不扩染色或增加玩法。

| 内容 | 原执行与等级 | 本片执行与等级 |
| --- | --- | --- |
| 爆壳手登场 | CORE_DROP分支、取得计数 | 等级1的取得能力 → UnlockCoreSupplyEffect请求；SkillInstance等级1 |
| 爆壳补给 | choice_effect → InstallUpgradeEffect、爆破升级表等级 | 两级能力配置 → 原InstallUpgradeEffect请求；SkillInstance等级1/2 |

## 配置、状态与提交

- SkillDefinition及SkillLevelDefinition只保存配置；每级列出AbilityDefinition。
- 本片每级支持一个取得/升级能力。level 1使用skill_acquired，level 2使用skill_upgraded；同能力ID保留运行实例。
- RunState.skill_instances拥有持久技能实例，instance_id采用首次成功选择的奖励序号，等级只由成功提交推进。
- AbilityInstance保持按实例独占的trigger_count；升级替换定义引用，沿用同ID能力对象及已用次数，不重建归零。
- RewardState.acquired仍记录历史取得次数，迁移卡的等级及构筑显示不再由该历史决定。
- 核心供给解锁与生成修正仍由ExplosionState拥有，生成规则读取；不是另一个可写技能等级。补给修正与实例等级不符时拒绝升级。
- 先校验配置、资格、冻结目标、颜色与连携预算，再落子/安装修正。失败不修改实例、不消费奖励，也不重抽已展示计划。
- 核心离场只销毁该棋子的离场能力，持久SkillInstance及供给修正继续保留。重试清空本局实例。

取得能力仍经已有ChoiceEffect生成请求、SkillRules提交。AbilityDefinition.effect的Resource加载边界显式检查类型；离场只接受ExplodeEffect，取得等级只接受ChoiceEffect。不存在任意Resource的隐式执行。
已删除CORE_DROP的旧资格/目标生成/应用分支，空等级配置不能退回无效果取得。
其余38项尚未迁移，沿用各自原路径；同一已迁移卡没有旧新双执行。

## 记录与兼容

规则版本为run-commands-v17-skill-instances。配置哈希递归记录等级/能力/效果参数；快照包含安装顺序、真实等级、能力ID、时机与消费次数。
旧v16及更早命令不跨版本重算，历史telemetry/结果不删除。本片实际使用合法命令取得核心、将补给升到2级并精确回放完整状态；测试用20个小目标只为覆盖升级，不进入游戏八阶段配置。
UI继续读SkillRules.level；核心预告颜色、生成流及锁定补棋前缀不变。没有导出Web。

## 验证与作者验收

Godot 4.7.2，13个相关脚本107测试/3311断言通过，日志 `.godot/issue59-regression-final.log`。
覆盖A/B共享定义与独立状态、升级对象/计数保留、无效取得/升级不消费、离场后持久状态、重试、非法配置、修正不一致、预告/卡片/技能池、阶段/成对工具及实际命令回放。自有相关代码最长321行。
没有做整库全回归或正式数值分析；编辑器真人体验待作者review。

作者可在当前开发分支试玩：取得爆壳手登场，确认首枚颜色与预告一致；取得爆壳补给并重复升级，横卡及技能池显示Lv.1→Lv.2/满级；消除核心后供给和升级继续保留。

#59已获作者review并合并PR #66。本页保留该首片的验证证据。
#60已接入局内离场事件/条件、应用后消费及重试隔离，当前记录版本为v18；细节见../skills/ABILITY_EVENTS.md。
后续按#61有序Composite统一请求、#62其余技能与生命周期、#63记录调试工具、#64旧路径清理逐片推进。
