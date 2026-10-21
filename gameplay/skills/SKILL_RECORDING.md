# 当前记录增量 · #135 B/S/T

规则版本 `run-commands-v41-followup-strength`；v39/v40 等旧版明确拒绝精确回放。离场爆破/扫线的 `trigger_strength` 与实际 removed/score 分列。匹配和爆破结果的 `followups` 保存来源 score event 身份、冻结范围/数量/波次上限、实际目标以及 pending/applied/empty/wave_limit/batch_not_selected/interrupted 诊断。

快照的 pending_removals / pending_followups 为脱离票据引用的只读数据。RuleResult 增加 completed_leaves / failed_leaf；保留 skill_outcome / target_changes / activations.interrupted。普通及延迟爆破异常均取消尚未执行的局部队列和染色，重试退役旧 Run。

验证包括真实染色命令的落盘回放、两次安全命令前缀重建、正常/快放低特效；安全前缀由完整命令重算，不支持中途叶子快照直接接管或 #160 任意存档恢复。证据见 docs/evidence/issue135-bst-completion/。下文为历史设计。

# O4 / #63：技能记录、回放与调试

集成分支 `feature/skill-refactor`；本片独立分支 `feat/issue-63-skill-recording`。
规则版本：`run-commands-v21-skill-recording`。旧 v20 及更早命令不跨版本精确回放。

## 本片交付

| 能力 | 位置 |
| --- | --- |
| Piece 能力快照关联 | `RunSnapshot.capture().instances[]` 含 `owner_id` / `skill_instance_id` / `event_type` / `max_triggers` / `consume_on_empty` |
| SkillInstance 调试字段 | `SkillInstance.data()` 含 `pending_event_id`、触发上限与空结果消费政策 |
| 条件解释 | `AbilityTriggerAdapter.explain()`（与 `matches` 同序短路） |
| 触发轨迹 | `AbilityEvents.complete` → `take_traces()` → `RuleResult.activations` |
| 错误可读化 | `RuleReplay.describe_error()` |
| 结果观看验证 | ResultViewer「验证回放」按钮（跑完整 RuleReplay；1×/快放不改变规则结论） |

## activations 字段（每条完成的激活）

`event_id`, `parent_event_id`, `owner_id`, `skill_instance_id`, `ability_id`, `source_ability_id`, `cause`, `generation`, `matched`, `reason`, `conditions[]`, `applied`, `affected_count`, `consumed`, `consume_on_empty`, `trigger_count_after`

用于定位「哪枚棋 / 哪个能力 / 条件为何通过 / 是否消费次数」。

## 验收对照

- 新格式可重算并比全状态：RuleReplay 仍逐条 canonical 比对；activations 进入 RuleResult 一并校验。
- 配置不匹配 / 截断 / 规则错误：机器码保留；`describe_error` 与 ResultViewer 显示中文摘要。
- 普通与加速演出同规则结果：既有 presentation / ResultViewer 速度测试；验证按钮不走演出路径。
- 调试可定位来源技能、条件与消费：activations + snapshot 关联字段。

## 未改

- 不重写 JSONL schema 名（仍 `run-jsonl-v1`）。
- 不把拒绝匹配的 listener 全量写入（避免噪声）；需要时用 `explain` 在调试会话查询。
- 旧 v17–v20 跨版本重算留给历史保留策略，不在本片打开。
