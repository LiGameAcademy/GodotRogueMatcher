# O4 技能管线（#64）

规则版本：`run-commands-v41-followup-strength`（记录与调试见 `../skills/SKILL_RECORDING.md`）。旧版本记录明确拒绝跨版本回放。

## 离场后代强度（#135第二片）

爆破/扫线在离场触发时捕获独占RemovalStrength，执行时查询当前目标及标记；后叶升级不追溯旧事件，新后代独立采样。余震在实际创建时采样。记录区分冻结强度、命中和得分，pending_removals只是只读投影，不是恢复。匹配染色资格、目标数量、波次上限及匹配附引信范围/数量同样在触发时捕获，执行只读取存活目标；运行版本v41，详见docs/quality/issue135_trigger_strength.md。

## Composite接入首片（#135）

叶内染色/出生引起的匹配即时提交账本和移除，后代等待最外层Composite结束；内层返回不flush。待执行匹配及附引信位置均归本局Resolver，异常清理不返还已提交收益，也不把原奖励变成可免费重试。

转化叶默认固定来源；只有配置 `reselect_after_previous=true` 的组合后叶才重新选取剩余普通棋。正式Catalog资源仍使用默认值。

固定目标显式FIXED并沿用冻结身份；动态叶显式DYNAMIC，freeze_offer只保存延迟契约，到达后才freeze一次。比例清理、疏整、行清理、附引信和染色共用该路径。既有独立单卡资源保持FIXED；正式清色后染的染色叶为DYNAMIC。Composite整树刷新方法已删除，数值叶仅刷新数值；预检不抽样，已知无效在首叶前拒绝。

固定合法失效由具体叶过滤/重校验并记录partial/empty；坏参数不转成成功。结果区分rejected/applied/error，异常取消后代记录interrupted。B/T补齐根全空门禁、嵌套完成/失败路径、专门原子成本及旧Run退役；异形与任意存档服务不在此片收口。触发强度由#168接管，详见docs/quality/issue135_composite_boundaries.md。

## 奖励等待与场景协调（#133）

`RunController.prepare_offer/advance/execute_command`拥有奖励等待、冻结候选和继续位置；`RewardOfferRules`负责失效判定。部分失效保留原组并标记不可用，全组失效每次奖励最多成功重建一次，保留reward身份并记录替代offer。候选生成在临时随机流完成冻结，成功后才提交正式三流及offer身份；合法一张、两张仍是完整组，零张进入ERROR。

`BoardRunFlow`通过Board的`reward_requested`向上通知Game；Game持有`GameRewardFlow`等待必要表现、打开快照弹窗并绑定原run/reward/offer/界面代次。普通关闭保留规则等待，HUD“继续选卡”恢复原组。只有成功选择才播放结果并请求Board继续；旧回调不能获取当前奖励身份再提交。Game退出和重试取消界面等待并释放本协调器取得的暂停。

`PopupSkillChoice`仅展示隔离的目标快照及临时选择；不扣奖励、不重抽、不控制全局暂停。LevelUpSystem正式写入口及弹窗循环已在#133退出；#134进一步移除旧道具注册/抽取，仅保留进度只读兼容查询。旧道具配置通过局部ItemRegistry对象构造，效果显式接收局部本局或账本，不订阅正式对局。本片未实现#160磁盘存档恢复或#161六随机流生命周期。

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