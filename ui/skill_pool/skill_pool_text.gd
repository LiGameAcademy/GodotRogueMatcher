class_name SkillPoolText
extends RefCounted

## 只读运行目录；不生成候选，不冻结目标，不读取抽取权重。
static func details(run: RunController, skill: SkillDefinition) -> String:
	var view: Dictionary[String, String] = rule_view(run, skill)
	var lines: PackedStringArray = [view.text, view.context]
	var requirements: PackedStringArray = []
	if skill.offer_traits != null:
		for need: StringName in skill.offer_traits.needs:
			requirements.append(_capability_text(need))
	if not skill.prerequisite.is_empty():
		for entry: SkillDefinition in SkillOfferGenerator.CATALOG:
			if entry.skill_id == skill.prerequisite:
				requirements.append(TranslationServer.translate(entry.title))
	if skill.minimum_reward > 1:
		requirements.append(TranslationServer.translate("第%d次选择起") % skill.minimum_reward)
	lines.append(TranslationServer.translate("前置：%s") % (" · ".join(requirements) if not requirements.is_empty() else TranslationServer.translate("无")))
	var maximum: int = skill.maximum_level
	var effect: SkillEffect = skill.acquisition_effect(SkillRules.level(run.state, skill))
	if effect is DemolitionStatEffect:
		match (effect as DemolitionStatEffect).stat:
			DemolitionStatEffect.Stat.RADIUS: maximum = run.abilities.config.maximum_radius_level
			DemolitionStatEffect.Stat.REWARD: maximum = run.abilities.config.reward_maximum_level
	if skill.is_persistent:
		lines.append(TranslationServer.translate("等级 %d / %s") % [SkillRules.level(run.state, skill), str(maximum) if maximum > 0 else TranslationServer.translate("可重复升级")])
	var reason: String = SkillRules.rejection(run.state, skill, run.abilities.config)
	if reason.begins_with("missing_required_capability:"):
		reason = TranslationServer.translate("缺少前置升级") + " · " + _capability_text(StringName(reason.trim_prefix("missing_required_capability:")))
	elif reason == "already_acquired_once_per_run":
		reason = TranslationServer.translate("取得") + " 1 / 1 · " + TranslationServer.translate("当前不可选")
	# 配置诊断不向玩家暴露抽取权重。
	if reason == "技能权重必须为正数": reason = "当前不可选"
	lines.append(TranslationServer.translate("当前资格：%s") % (TranslationServer.translate("满足条件") if reason.is_empty() else TranslationServer.translate(reason)))
	return "\n".join(lines)

## Browsing is never an offer: show owned state, or a definition without sampled targets.
static func rule_view(run: RunController, skill: SkillDefinition) -> Dictionary[String, String]:
	var level: int = SkillRules.level(run.state, skill)
	var refill: RefillCountEffect = skill.refill_effect(maxi(0, level - 1))
	var remaining: int = run.state.spawning.refill_batches.get(refill.delta, 0) if refill != null else 0
	if skill.is_persistent and level > 0:
		return {"text": SkillChoiceText.summary(skill, level, remaining, true), "context": SkillRuleDescription.preview("rules.context_owned", {"level": level}).text}
	if not skill.is_persistent and level > 0 and refill != null and remaining > 0:
		return {"text": SkillChoiceText.summary(skill, maxi(1, level), remaining, true), "context": SkillRuleDescription.preview("rules.context_active").text}
	return {"text": SkillChoiceText.summary(skill), "context": SkillRuleDescription.preview("rules.context_definition").text}

static func _capability_text(need: StringName) -> String:
	match need:
		&"core_supply": return TranslationServer.translate("需先获得爆壳手登场")
		&"fuse_unlocked": return TranslationServer.translate("需先解锁引信路线")
		&"live_fuse": return TranslationServer.translate("棋盘上需要引信")
		&"row_supply": return TranslationServer.translate("行清除手登场")
		&"column_supply": return TranslationServer.translate("列清除手登场")
		&"line_supply": return TranslationServer.translate("行清除手登场") + " / " + TranslationServer.translate("列清除手登场")
		&"dye_engine": return TranslationServer.translate("染色接续")
	return String(need)
