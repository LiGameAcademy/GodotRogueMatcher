# O4 / #62：现有技能迁移对照

集成分支 `feature/skill-refactor`；本片独立分支 `feat/issue-62-skill-migration`。
规则版本：`run-commands-v20-skill-migration`。旧 v19 及更早命令不跨版本重算。

## 本片目标

- 目录内每张运行技能都有 Effect 配置入口（`choice_effect` 或 `levels[].abilities[].effect`）。
- 删除 `SkillRules._apply_legacy` 与按 `SkillDefinition.Action` 的取得/应用分支。
- 保留已确认数值与生命周期；升级/重复取得/次数耗尽/唯一棋与预告边界由既有案例 + 本片 Action 回归覆盖。

## Action 分支 → Effect（本片关闭）

| skill_id | 原 Action | 现 Effect | 等级/生命周期 |
| --- | --- | --- | --- |
| assign_fuse | ASSIGN_FUSE | `AssignFuseEffect` → `ASSIGN_FUSE` | 即时；`choice_effect` |
| instant_thin | THIN | `ThinMaterialEffect` → `THIN`（直接 `remove_piece`，不得分） | 即时；`choice_effect` |
| blast_radius | BLAST_RADIUS | `DemolitionStatEffect(RADIUS)` | 1 级 `levels` / SkillInstance |
| blast_reward | BLAST_REWARD | `DemolitionStatEffect(REWARD)` | 3 级 `levels` / SkillInstance |
| blast_extra | BLAST_EXTRA | `DemolitionStatEffect(BLAST_EXTRA)` | 3 级 `levels` / SkillInstance |
| score_multiplier | SCORE_MULTIPLIER | `DemolitionStatEffect(MULTIPLIER)` | 可重复；`choice_effect`（max=0） |
| match_extra | MATCH_EXTRA | `DemolitionStatEffect(MATCH_EXTRA)` | 可重复；`choice_effect`（max=0） |

`SkillDefinition.Action` 已在 #64 删除；运行时仅经 Effect / Runner。

## 已走 Effect 路径（先前片或本片对照）

| 类别 | 代表 skill_id | 配置入口 | 说明 |
| --- | --- | --- | --- |
| 核心首迁 | core_drop, core_supply_up | `levels` | #59 SkillInstance |
| 组合试玩 | composite_refill_color, composite_clear_dye | `levels` + `CompositeEffect` | #61 |
| 爆破升级表 | fuse_capacity, core_radius, … | `InstallUpgradeEffect`（`choice_effect`） | 经 Runner；修正仍在 ExplosionState.upgrades |
| 染色升级 | dye_target_up, dye_chain_depth, … | `InstallDyeUpgradeEffect` | Runner → DyeState.upgrades |
| 目标奖励 | goal_score_bonus | `InstallGoalBonusEffect` | Runner → goal_bonus_score |
| 生成修正 | refill_*, color_weight_* | `RefillCountEffect` / `ColorWeightEffect` | 即时或可重复；批次/权重在 SpawnState |
| 即时清/染/引 | instant_color_*, instant_fuse_ignite, instant_percent_clear | Clear/Dye/Ignite/Percent | 即时 `choice_effect` |

完整目录仍由 `SkillOfferGenerator.CATALOG` 持有；每张卡 `acquisition_effect(0) != null`（见 `test_skill_action_migration.gd`）。

## 重复状态入口

- 取得应用只经 `AbilityEffectRunner`；已删除 `_apply_legacy`。
- 候选冻结只经 Effect.`freeze`；不再按 Action 手写 piece_ids。
- Offer 工具位/兜底/亲和力改读 Effect 类型辅助方法，不再读 Action。

## 验收案例入口

- `tests/rules/test_skill_action_migration.gd`：引信赋能、疏整、半径满级同步、倍率重复、目录全有 Effect。
- `tests/rules/test_demolition_build.gd`：整目录取得冒烟。
- `tests/rules/test_ability_composite_effects.gd` / `test_skill_instances.gd`：组合与实例回归。

## 未强制 levels 化（#64 仍成立）

仍用 `choice_effect` 的持久 `InstallUpgrade` / 染色升级 / 目标奖励：已在 Runner 路径上，数值与满级仍由 `maximum_level` + 状态表拥有。不另开 apply 双入口。管线总览见 `SKILL_PIPELINE.md`。
