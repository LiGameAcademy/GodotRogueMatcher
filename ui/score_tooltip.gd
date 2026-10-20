class_name ScoreTooltip
extends RefCounted

## 汇总账本各笔最终分；升级后的倍率不会追溯改写历史。
static func describe(state: RunState) -> String:
	var lines: PackedStringArray = [TranslationServer.translate("整局总分 %d · 过关不扣分") % state.ledger.total]
	lines.append(TranslationServer.translate("每笔得分 = 基础分 × 分数倍率 + 额外得分（向下取整）\n总分为每笔得分的累加。\n五连基础分 = 消除数量 ×（消除数量 + 5）。"))
	var config: ExplosionConfig = AbilityResolver.DEFAULT_CONFIG
	lines.append(TranslationServer.translate("当前五连：分数倍率 %.2f · 额外得分 %d\n独立技能奖励只计额外得分。") % [1.0 + state.explosion.multiplier_level * config.multiplier_per_level, state.explosion.match_extra_level * config.bonus_per_match])
	var action_score: int = 0
	var choice_score: int = 0
	var other_score: int = 0
	for entry: ScoreEntry in state.ledger.get_entries():
		if entry.root_action_id > 0: action_score += entry.final_score
		elif entry.root_action_id < 0: choice_score += entry.final_score
		else: other_score += entry.final_score
	lines.append(TranslationServer.translate("实际构成：行动 %d + 选卡 %d + 其他 %d = %d") % [action_score, choice_score, other_score, state.ledger.total])
	lines.append(TranslationServer.translate("总分是各笔最终得分之和，采用得分当时的倍率。"))
	if not state.ledger.get_entries().is_empty(): lines.append("\n" + HudDetails.score_details(state.ledger.get_entries(), true))
	return "\n\n".join(lines)
