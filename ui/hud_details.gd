class_name HudDetails
extends RefCounted

## 将只读规则状态格式化成原型说明，不重新计算收益。
static func skills(state: RunState) -> String:
	var persistent: PackedStringArray = []
	var instant: PackedStringArray = []
	for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
		var acquired: int = state.rewards.acquired.get(skill.skill_id, 0)
		if acquired == 0: continue
		if skill.is_persistent:
			persistent.append("%s · Lv.%d\n%s" % [skill.title, SkillRules.level(state, skill), skill.description])
		else:
			instant.append("%s ×%d（已使用）" % [skill.title, acquired])
	var cores: int = 0
	var fuses: int = 0
	for piece: PieceState in state.rules.state.get_snapshot():
		if piece.content_id == &"special_demolition": cores += 1
		elif state.explosion.instances.has(piece.piece_id): fuses += 1
	var text: String = "爆壳手在场 %d · 引信 %d\n\n" % [cores, fuses]
	var config: ExplosionConfig = AbilityResolver.DEFAULT_CONFIG
	text += "五连 G = %.2f · E = %d\n爆炸每目标奖励 %d\n\n" % [1.0 + state.explosion.multiplier_level * config.multiplier_per_level, state.explosion.match_extra_level * config.bonus_per_match, state.explosion.reward_level * config.reward_per_target]
	text += "\n\n".join(persistent) if not persistent.is_empty() else "尚未获得持续技能"
	if not instant.is_empty(): text += "\n\n即时技能记录\n" + "\n".join(instant)
	return text

static func tools(state: RunState) -> String:
	var lines: PackedStringArray = []
	for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
		if skill.is_persistent: continue
		var count: int = state.rewards.acquired.get(skill.skill_id, 0)
		if count > 0: lines.append("%s：已使用 %d 次" % [skill.title, count])
	return "\n".join(lines) if not lines.is_empty() else "尚未使用即时技能"

static func score_details(entries: Array[ScoreEntry]) -> String:
	if entries.is_empty(): return "尚未得分\n\n五枚同色连线即可消除。"
	var action: int = entries.back().root_action_id
	var lines: PackedStringArray = []
	var total: int = 0
	for entry: ScoreEntry in entries:
		if entry.root_action_id != action: continue
		total += entry.final_score
		var reason: String = "爆炸" if entry.reason == &"explosion" else "消除"
		lines.append("%s：%d × %.2f + %d = %d" % [reason, entry.base_score, entry.multiplier, entry.extra_score, entry.final_score])
	return "最近得分行动 +%d\nB × G + E\n\n%s" % [total, "\n".join(lines)]

static func summary(state: RunState) -> String:
	var totals: Dictionary[int, int] = {}
	var best: int = 0
	for entry: ScoreEntry in state.ledger.get_entries():
		totals[entry.root_action_id] = totals.get(entry.root_action_id, 0) + entry.final_score
		best = maxi(best, totals[entry.root_action_id])
	return "有效移动 %d 次 · 技能选择 %d 次\n最高单次行动得分 %d" % [state.valid_moves, state.rewards.consumed_count, best]
