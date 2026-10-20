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
