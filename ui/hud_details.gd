class_name HudDetails
extends RefCounted

## 只列当前有效构筑，不混入棋盘统计或调试变量。
static func active_skills(state: RunState) -> Array[SkillDefinition]:
	var result: Array[SkillDefinition] = []
	for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
		if state.rewards.acquired.get(skill.skill_id, 0) == 0: continue
		if skill.is_persistent or remaining_refills(skill, state) > 0: result.append(skill)
	return result

static func remaining_refills(skill: SkillDefinition, state: RunState) -> int:
	if not skill.choice_effect is RefillCountEffect: return 0
	return state.spawning.refill_batches[(skill.choice_effect as RefillCountEffect).delta]

## 纯文本摘要供离线查看和验证；HUD使用独立横卡。
static func skills(state: RunState) -> String:
	var lines: PackedStringArray = []
	for skill: SkillDefinition in active_skills(state):
		var header: String = TranslationServer.translate(skill.title)
		if skill.is_persistent: header += " · Lv.%d" % SkillRules.level(state, skill)
		else: header += " · " + TranslationServer.translate("剩余 %d 次实际补棋") % remaining_refills(skill, state)
		lines.append(header + "\n" + SkillChoiceText.summary(skill))
	return "\n\n".join(lines) if not lines.is_empty() else TranslationServer.translate("尚未获得持续技能")

static func tools(state: RunState) -> String:
	var lines: PackedStringArray = []
	for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
		if not skill.choice_effect is RefillCountEffect: continue
		var effect: RefillCountEffect = skill.choice_effect as RefillCountEffect
		var remaining: int = state.spawning.refill_batches[effect.delta]
		if remaining > 0: lines.append(TranslationServer.translate("%s：剩余 %d 次补棋") % [TranslationServer.translate(skill.title), remaining])
	return "\n".join(lines) if not lines.is_empty() else TranslationServer.translate("暂无生效的临时技能")

static func history(state: RunState) -> String:
	var lines: PackedStringArray = []
	for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
		if skill.is_persistent: continue
		var count: int = state.rewards.acquired.get(skill.skill_id, 0)
		if count > 0: lines.append(TranslationServer.translate("%s · %s %d 次") % [TranslationServer.translate(skill.title), TranslationServer.translate("取得") if skill.choice_effect is RefillCountEffect else TranslationServer.translate("已使用"), count])
	return "\n".join(lines) if not lines.is_empty() else TranslationServer.translate("尚无使用记录")

static func score_details(entries: Array[ScoreEntry], show_formula: bool = false) -> String:
	if entries.is_empty(): return TranslationServer.translate("尚未得分\n\n五枚同色连线即可消除。")
	var action: int = entries.back().root_action_id
	var lines: PackedStringArray = []
	var total: int = 0
	for entry: ScoreEntry in entries:
		if entry.root_action_id != action or entry.reason == &"dye": continue
		if entries.back().reason == &"goal_score_bonus" and entry.event_id != entries.back().event_id: continue
		total += entry.final_score
		var reason: String = TranslationServer.translate("爆炸") if entry.reason == &"explosion" else (TranslationServer.translate("连携回响") if entry.reason == &"chain_reward" else (TranslationServer.translate("印记收获") if entry.reason == &"marked_reward" else TranslationServer.translate("消除")))
		if entry.reason == &"goal_score_bonus": reason = TranslationServer.translate("过关嘉奖")
		if show_formula:
			lines.append(TranslationServer.translate("%s：%d × %.2f + %d = %d") % [reason, entry.base_score, entry.multiplier, entry.extra_score, entry.final_score])
		else:
			lines.append(TranslationServer.translate("%s +%d") % [reason, entry.final_score])
	var heading: String = "目标完成奖励 +%d\n\n%s" if entries.back().reason == &"goal_score_bonus" else "最近得分行动 +%d\n\n%s"
	return TranslationServer.translate(heading) % [total, "\n".join(lines)]

static func summary(state: RunState) -> String:
	var totals: Dictionary[int, int] = {}
	var best: int = 0
	for entry: ScoreEntry in state.ledger.get_entries():
		if entry.reason == &"goal_score_bonus": continue
		totals[entry.root_action_id] = totals.get(entry.root_action_id, 0) + entry.final_score
		best = maxi(best, totals[entry.root_action_id])
	return StageText.end_summary(state) + TranslationServer.translate("有效行动 %d 次 · 技能选择 %d 次\n最高单次行动得分 %d") % [state.valid_moves + state.activations, state.rewards.consumed_count, best]

static func score_details_rich(entries: Array[ScoreEntry]) -> String:
	var lines: PackedStringArray = score_details(entries).split("\n")
	for index: int in range(lines.size()):
		var line: String = lines[index]
		if index == 0 and not entries.is_empty():
			lines[index] = "[font_size=20][color=#f3d28b]%s[/color][/font_size]" % line
		elif line.begins_with(TranslationServer.translate("爆炸")):
			lines[index] = "[color=#ffc08a]%s[/color]" % line
		elif line.begins_with(TranslationServer.translate("连携回响")):
			lines[index] = "[color=#c9a4f4]%s[/color]" % line
	return "\n".join(lines)
