# O4 技能管线（#64）

规则版本：`run-commands-v21-skill-recording`（记录与调试见 `../skills/SKILL_RECORDING.md`）。

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
