class_name ScoreTooltip
extends RefCounted

## 汇总账本各笔最终分；升级后的倍率不会追溯改写历史。
static func describe(state: RunState) -> String:
	var lines: PackedStringArray = [TranslationServer.translate("整局总分 %d · 过关不扣分") % state.ledger.total]
	lines.append(TranslationServer.translate("每笔得分 = floor(B × G + E)\n五连基础 B = N × (N + 5)，N 为消除数量（至少5枚）。\nG 为该笔倍率，E 为额外得分；独立技能奖励的 B 为0。"))
	var action_score: int = 0
	var choice_score: int = 0
	var other_score: int = 0
	for entry: ScoreEntry in state.ledger.get_entries():
		if entry.root_action_id > 0: action_score += entry.final_score
		elif entry.root_action_id < 0: choice_score += entry.final_score
		else: other_score += entry.final_score
	lines.append(TranslationServer.translate("实际构成：行动 %d + 选卡 %d + 其他 %d = %d") % [action_score, choice_score, other_score, state.ledger.total])
	lines.append(TranslationServer.translate("总分是各笔最终得分之和，采用得分当时的倍率。"))
	if not state.ledger.get_entries().is_empty(): lines.append("\n" + HudDetails.score_details(state.ledger.get_entries()))
	return "\n\n".join(lines)
