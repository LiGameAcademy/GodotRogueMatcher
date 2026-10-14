# O4 技能管线（#64）

规则版本：`run-commands-v24-composite-score-events`（记录与调试见 `../skills/SKILL_RECORDING.md`）。

## 配置 → 提交（取得）

```
SkillDefinition (.tres)
  choice_effect 或 levels[].abilities[].effect  → SkillEffect
       │
       ├─ SkillRules.rejection / level
       ├─ SkillRules.freeze_target  （候选冻结唯一入口）
       └─ SkillRules.apply
              └─ AbilityEffectRunner.preflight / apply_skill_effect
                     └─ ChoiceEffect.build → ChoiceEffectRequest
                            └─ 写入 ExplosionState / DyeState / SpawnState /
                               BoardRules / SkillInstance.commit_next_level
```

## 配置 → 提交（离场）

```
AbilityDefinition (on piece AbilityInstance)
  → AbilityTriggerAdapter.explain / matches
  → AbilityEvents.dispatch / complete  （RuleResult.activations）
  → AbilityResolver 爆炸结算
```

## 阅读顺序（review）

1. `content/*.tres` — 叶子或 Composite 配置  
2. `skill_definition.gd` / `skill_level_definition.gd`  
3. `skill_rules.gd` → `ability_effect_runner.gd`  
4. `choice_effect_request.gd` + 各 `effects/*_effect.gd`  
5. `skill_instance.gd` / `run_state.gd`  
6. `ability_events.gd` → `run_snapshot.gd` / `run_recorder.gd`

片级证据：`SKILL_INSTANCES.md`（#59）、`../skills/ABILITY_EVENTS.md`（#60）、`../skills/EFFECT_COMPOSITE.md`（#61）、`SKILL_MIGRATION.md`（#62）、`../skills/SKILL_RECORDING.md`（#63）。

## #64 清理结论

- 已删除 `SkillDefinition.Action` 与 `_apply_legacy`；无 Action 双写。
- 候选/测试/工具冻结统一 `SkillRules.freeze_target`。
- UI 消耗/补棋剩余读 `SkillDefinition.refill_effect()`（含组合卡叶子）。
- 组合卡 `composite_refill_color` / `composite_clear_dye` 保留在运行目录，权重与文案已收为正式卡。
- 其余 `InstallUpgrade` 等仍可走 `choice_effect` + Runner（非第二套 apply）。

## 本次 debug 的全技能回归

`choice_effect` 是直接叶子配置，`levels[].abilities[].effect` 是分级配置，两者都进入同一个 Runner。前者并非已删除的 Action 旧执行入口；可重复和即时技能无需为了测试强制改成有限等级技能。

取得/升级测试统一使用 `SkillRules.freeze_target`，再经 `SkillRules.apply` 或真实 `ChooseSkillCommand` 提交。叶子单元测试继续直接验证 freeze/build；故意失效和非法参数测试保留手工构造目标。演出测试需要指定落点/颜色时，先冻结合法目标再修改明确的场景参数。

`tests/rules/test_catalog_skill_pipeline.gd` 穷举当前42卡的真实选择命令，检查资格、成功取得、配置不变、重复提交幂等、采集事件合计与账本一致；遍历所有声明的多级升级并检查实例身份和触发计数。完整命令回放由 `test_commands_replay`、`test_expanded_skills` 和阶段/目标奖励回放案例验证，不把手工候选记录称为可从初始局面独立重放。
