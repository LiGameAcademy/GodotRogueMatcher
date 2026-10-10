class_name SkillPoolText
extends RefCounted

## 只读运行目录；不生成候选，不冻结目标，不读取抽取权重。
static func details(run: RunController, skill: SkillDefinition) -> String:
	var lines: PackedStringArray = [SkillChoiceText.summary(skill)]
	var requirements: PackedStringArray = []
	if skill.requires_core: requirements.append(TranslationServer.translate("需先获得爆壳手登场"))
	if skill.requires_fuse_unlock: requirements.append(TranslationServer.translate("需先解锁引信路线"))
	if skill.requires_fuse: requirements.append(TranslationServer.translate("棋盘上需要引信"))
	if not skill.prerequisite.is_empty():
		for entry: SkillDefinition in SkillOfferGenerator.CATALOG:
			if entry.skill_id == skill.prerequisite:
				requirements.append(TranslationServer.translate(entry.title))
	if skill.minimum_reward > 1:
		requirements.append(TranslationServer.translate("第%d次选择起") % skill.minimum_reward)
		if skill.rescue_offer and run.state.stage.enabled(): requirements.append(TranslationServer.translate("拥挤时可提前出现"))
	lines.append(TranslationServer.translate("前置：%s") % (" · ".join(requirements) if not requirements.is_empty() else TranslationServer.translate("无")))
	var maximum: int = skill.maximum_level
	if skill.choice_effect == null:
		if skill.action == SkillDefinition.Action.BLAST_RADIUS: maximum = run.abilities.config.maximum_radius_level
		elif skill.action == SkillDefinition.Action.BLAST_REWARD: maximum = run.abilities.config.reward_maximum_level
	if skill.is_persistent:
		lines.append(TranslationServer.translate("等级 %d / %s") % [SkillRules.level(run.state, skill), str(maximum) if maximum > 0 else TranslationServer.translate("可重复升级")])
	var reason: String = SkillRules.rejection(run.state, skill, run.abilities.config)
	# 配置诊断不向玩家暴露抽取权重。
	if reason == "技能权重必须为正数": reason = "当前不可选"
	lines.append(TranslationServer.translate("当前资格：%s") % (TranslationServer.translate("满足条件") if reason.is_empty() else TranslationServer.translate(reason)))
	return "\n".join(lines)
