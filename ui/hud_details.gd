class_name HudDetails
extends RefCounted

## 将只读规则状态格式化成原型说明，不重新计算收益。
static func skills(state: RunState) -> String:
	var persistent: PackedStringArray = []
	var temporary: PackedStringArray = []
	for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
		var acquired: int = state.rewards.acquired.get(skill.skill_id, 0)
		if acquired == 0: continue
		if skill.is_persistent:
			var progress: String = "Lv.%d" % SkillRules.level(state, skill)
			persistent.append("%s · %s · %s\n%s" % [TranslationServer.translate(SkillRarity.LABELS[skill.rarity]), TranslationServer.translate(skill.title), progress, TranslationServer.translate(skill.description)])
		elif skill.choice_effect is RefillCountEffect:
			var effect: RefillCountEffect = skill.choice_effect as RefillCountEffect
			var remaining: int = state.spawning.refill_batches[effect.delta]
			if remaining > 0: temporary.append(TranslationServer.translate("%s · 补棋%+d\n剩余 %d 次实际补棋") % [TranslationServer.translate(skill.title), effect.delta, remaining])
	var cores: int = 0
	var fuses: int = 0
	for piece: PieceState in state.rules.state.get_snapshot():
		if piece.content_id == &"special_demolition": cores += 1
		elif state.explosion.instances.has(piece.piece_id): fuses += 1
	var text: String = TranslationServer.translate("爆壳手在场 %d · 引信 %d\n\n") % [cores, fuses]
	if state.explosion.core_pool_unlocked:
		text += TranslationServer.translate("核心补给已解锁 · 场上唯一\n核心类型权重 %d／普通 %d\n") % [DemolitionRules.CONFIG.core_type_weight + state.explosion.level(&"core_supply_up"), DemolitionRules.CONFIG.ordinary_type_weight]
		if cores == 0: text += TranslationServer.translate("已安装核心强化对下一枚生效\n")
		text += "\n"
	var config: ExplosionConfig = AbilityResolver.DEFAULT_CONFIG
	text += TranslationServer.translate("五连 G = %.2f · E = %d\n爆炸每目标奖励 %d\n\n") % [1.0 + state.explosion.multiplier_level * config.multiplier_per_level, state.explosion.match_extra_level * config.bonus_per_match, state.explosion.reward_level * config.reward_per_target]
	text += TranslationServer.translate("下次普通补棋 %d 枚（基础 %d）\n\n") % [state.next_refill_count(), state.base_refill_count()]
	if state.spawning.color_weights != RunController.SPAWN_CONFIG.color_weights:
		var total_weight: int = 0
		for weight: int in state.spawning.color_weights: total_weight += weight
		var chances: PackedStringArray = []
		for color: int in range(state.spawning.color_weights.size()):
			chances.append("%s %d／%d（%.1f%%）" % [TranslationServer.translate(PieceTooltip.COLOR_NAMES[color]), state.spawning.color_weights[color], total_weight, 100.0 * state.spawning.color_weights[color] / total_weight])
		text += TranslationServer.translate("普通生成权重\n") + "\n".join(chances) + "\n\n"
	text += "\n\n".join(persistent) if not persistent.is_empty() else TranslationServer.translate("尚未获得持续技能")
	if not temporary.is_empty(): text += TranslationServer.translate("\n\n有效临时技能\n") + "\n\n".join(temporary)
	return text

static func tools(state: RunState) -> String:
	var lines: PackedStringArray = []
	for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
		if not skill.choice_effect is RefillCountEffect: continue
		var effect: RefillCountEffect = skill.choice_effect as RefillCountEffect
		var remaining: int = state.spawning.refill_batches[effect.delta]
		if remaining > 0: lines.append(TranslationServer.translate("%s：剩余 %d 次补棋") % [TranslationServer.translate(skill.title), remaining])
	return "\n".join(lines) if not lines.is_empty() else TranslationServer.translate("暂无生效的临时技能")

## 保留纯文本接口供记录/测试复用，富文本仅用于HUD。
static func skills_rich(state: RunState) -> String:
	var lines: PackedStringArray = skills(state).split("\n")
	for index: int in range(lines.size()):
		var line: String = lines[index]
		for rarity: int in range(SkillRarity.LABELS.size()):
			if line.begins_with(TranslationServer.translate(SkillRarity.LABELS[rarity])):
				lines[index] = "[font_size=16][color=#%s]%s[/color][/font_size]" % [SkillRarity.COLORS[rarity].to_html(false), line]
				break
		if line.begins_with(TranslationServer.translate("爆壳手在场")) or line.begins_with(TranslationServer.translate("五连 G")) or line.begins_with(TranslationServer.translate("下次普通补棋")):
			lines[index] = "[color=#8fe3da]%s[/color]" % line
	return "\n".join(lines)

static func history(state: RunState) -> String:
	var lines: PackedStringArray = []
	for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
		if skill.is_persistent: continue
		var count: int = state.rewards.acquired.get(skill.skill_id, 0)
		if count > 0: lines.append(TranslationServer.translate("%s · %s %d 次") % [TranslationServer.translate(skill.title), TranslationServer.translate("取得") if skill.choice_effect is RefillCountEffect else TranslationServer.translate("已使用"), count])
	return "\n".join(lines) if not lines.is_empty() else TranslationServer.translate("尚无使用记录")

static func score_details(entries: Array[ScoreEntry]) -> String:
	if entries.is_empty(): return TranslationServer.translate("尚未得分\n\n五枚同色连线即可消除。")
	var action: int = entries.back().root_action_id
	var lines: PackedStringArray = []
	var total: int = 0
	for entry: ScoreEntry in entries:
		if entry.root_action_id != action or entry.reason == &"dye": continue
		total += entry.final_score
		var reason: String = TranslationServer.translate("爆炸") if entry.reason == &"explosion" else (TranslationServer.translate("连携回响") if entry.reason == &"chain_reward" else (TranslationServer.translate("印记收获") if entry.reason == &"marked_reward" else TranslationServer.translate("消除")))
		lines.append("%s：%d × %.2f + %d = %d" % [reason, entry.base_score, entry.multiplier, entry.extra_score, entry.final_score])
	return TranslationServer.translate("最近得分行动 +%d\nB × G + E\n\n%s") % [total, "\n".join(lines)]

static func summary(state: RunState) -> String:
	var totals: Dictionary[int, int] = {}
	var best: int = 0
	for entry: ScoreEntry in state.ledger.get_entries():
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
