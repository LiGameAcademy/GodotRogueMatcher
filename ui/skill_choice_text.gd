class_name SkillChoiceText
extends RefCounted
const TAG_LABELS: Dictionary[StringName, String] = {&"exp": "爆破", &"dye": "染色", &"generation": "生成", &"match": "连珠", &"mult": "倍率", &"space": "空间", &"goal": "目标", &"extra": "额外分"}
const CONSUME_HINT: String = "每次实际补棋扣1次，次数用完后失效；免补棋不扣次数。"

## 卡面消费已冻结目标，不自行抽取或改变规则。
static func summary(skill: SkillDefinition, level: int = -1, remaining: int = -1, owned: bool = false) -> String:
	return SkillRuleDescription.describe(skill, level, remaining, owned).text

static func summary_rich(skill: SkillDefinition, level: int = -1, remaining: int = -1, owned: bool = false) -> String:
	var text: String = summary(skill, level, remaining, owned)
	if skill.refill_effect() != null:
		text = text.replace(TranslationServer.translate("消耗（正文）"), '[hint="%s"][b]%s[/b][/hint]' % [TranslationServer.translate(CONSUME_HINT), TranslationServer.translate("消耗（正文）")])
	return text

static func tags(skill: SkillDefinition) -> String:
	var labels: PackedStringArray = []
	for tag: StringName in skill.tags:
		if TAG_LABELS.has(tag): labels.append(TranslationServer.translate(TAG_LABELS[tag]))
	if not skill.is_persistent and skill.refill_effect() == null: labels.append(TranslationServer.translate("即时"))
	return " · ".join(labels)

## 卡面只显示此次选择的具体变化，不重复展示共同生命周期。
static func compact_preview(skill: SkillDefinition, target: SkillTarget) -> String:
	if target.deferred: return TranslationServer.translate("目标在执行时选择")
	var effect: SkillEffect = skill.acquisition_effect(target.level_before)
	if effect is DemolitionStatEffect and (effect as DemolitionStatEffect).stat == DemolitionStatEffect.Stat.MULTIPLIER:
		return SkillRuleDescription.preview("rules.multiplier_preview", {"before": String.num(target.value_before * SkillRuleDescription.EXPLOSION.multiplier_per_level, 3), "after": String.num(target.value_after * SkillRuleDescription.EXPLOSION.multiplier_per_level, 3)}).text
	if effect is TransformMaterialEffect:
		var content: StringName = (effect as TransformMaterialEffect).content_id
		var name_text: String = "爆破手" if content == &"special_demolition" else ("横扫手" if content == LineClearState.CONTENT_ROW else "列扫手")
		return TranslationServer.translate("本次转化：%d枚 → %s") % [target.piece_ids.size(), TranslationServer.translate(name_text)]
	if effect is InstallGoalBonusEffect:
		return TranslationServer.translate("每次达标：+%d分") % target.value_after
	if effect is PercentClearEffect:
		return TranslationServer.translate("本次清理：%d枚普通棋") % target.piece_ids.size()
	if effect is InstallLineUpgradeEffect and (effect as InstallLineUpgradeEffect).upgrade == &"line_clear_score":
		return TranslationServer.translate("每枚额外得分：+%d → +%d") % [LineClearRules.score_per_target(target.value_before), LineClearRules.score_per_target(target.value_after)]
	if effect is InstallLineUpgradeEffect and (effect as InstallLineUpgradeEffect).required_axis >= 0:
		var axis: int = (effect as InstallLineUpgradeEffect).required_axis
		var format: String = TranslationServer.translate("扫线范围：%d → %d 行") if axis == LineClearState.AXIS_ROW else TranslationServer.translate("扫线范围：%d → %d 列")
		return format % [LineClearRules.line_count(target.value_before), LineClearRules.line_count(target.value_after)]
	if effect is UnlockCoreSupplyEffect:
		return TranslationServer.translate("立即投放：%s") % _color_name(target.color)
	if effect is CompositeEffect:
		return _composite_preview(effect as CompositeEffect, target as CompositeSkillTarget)
	if effect is RefillCountEffect:
		return _refill_preview(target)
	if effect is ClearMaterialEffect:
		if (effect as ClearMaterialEffect).requires_color_choice(): return TranslationServer.translate("自选颜色 · 保留特殊棋")
		var group: String = _color_name(target.color) if target.line_axis == -1 else TranslationServer.translate("第%d%s") % [target.line_index + 1, TranslationServer.translate("行") if target.line_axis == 0 else TranslationServer.translate("列")]
		return TranslationServer.translate("%s · 清理%d枚普通棋") % [group, target.piece_ids.size()]
	if effect is ColorWeightEffect:
		return TranslationServer.translate("%s权重：%d → %d") % [_color_name(target.color), target.value_before, target.value_after]
	if effect is DyeMaterialEffect:
		return TranslationServer.translate("%s · 同时染色 %d 枚") % [_color_name(target.color), target.piece_ids.size()]
	return ""

static func _refill_preview(target: SkillTarget) -> String:
	return SkillRuleDescription.preview("rules.refill_preview", {"before": target.value_before, "after": target.value_after, "remaining_before": target.remaining_before, "remaining_after": target.remaining_after}).text

static func level_text(skill: SkillDefinition, target: SkillTarget) -> String:
	if not skill.is_persistent: return ""
	var result: String = "Lv.%d  →  Lv.%d" % [target.level_before, target.level_after]
	if skill.maximum_level > 0 and target.level_after >= skill.maximum_level: result += TranslationServer.translate("  ·  满级")
	return result

static func _color_name(color: int) -> String:
	return TranslationServer.translate(PieceTooltip.COLOR_NAMES[color]) if color >= 0 and color < PieceTooltip.COLOR_NAMES.size() else TranslationServer.translate("未知颜色")

static func _composite_preview(effect: CompositeEffect, target: CompositeSkillTarget) -> String:
	if not effect.validation_error().is_empty(): return TranslationServer.translate("有序组合效果")
	var composite_target: CompositeSkillTarget = target
	if composite_target == null or composite_target.leaf_targets.is_empty():
		return TranslationServer.translate("有序组合效果")
	if effect.children.size() == 2 and composite_target.leaf_targets.size() == 2 and effect.children[0] is ClearMaterialEffect and effect.children[1] is DyeMaterialEffect and composite_target.leaf_targets[1].deferred:
		return SkillRuleDescription.preview("rules.dynamic_preview").text
	if effect.children.size() == 2 and composite_target.leaf_targets.size() == 2 and effect.children[0] is RefillCountEffect and effect.children[1] is ColorWeightEffect:
		var refill: SkillTarget = composite_target.leaf_targets[0]
		var weight: SkillTarget = composite_target.leaf_targets[1]
		return SkillRuleDescription.preview("rules.mixed_preview", {"before": refill.value_before, "after": refill.value_after, "remaining_before": refill.remaining_before, "remaining_after": refill.remaining_after, "color": _color_name(weight.color), "weight_before": weight.value_before, "weight_after": weight.value_after}).text
	var lines: PackedStringArray = []
	var composite: CompositeEffect = effect
	for index: int in range(mini(composite.children.size(), composite_target.leaf_targets.size())):
		var leaf: SkillEffect = composite.children[index]
		var leaf_target: SkillTarget = composite_target.leaf_targets[index]
		if leaf_target.deferred:
			lines.append(SkillRuleDescription.preview("rules.dynamic_preview").text)
		elif leaf is CompositeEffect:
			lines.append(_composite_preview(leaf as CompositeEffect, leaf_target as CompositeSkillTarget))
		elif leaf is RefillCountEffect:
			lines.append(_refill_preview(leaf_target))
		elif leaf is ColorWeightEffect:
			lines.append(TranslationServer.translate("%s权重：%d → %d") % [_color_name(leaf_target.color), leaf_target.value_before, leaf_target.value_after])
		elif leaf is ClearMaterialEffect:
			lines.append(TranslationServer.translate("自选颜色清理") if (leaf as ClearMaterialEffect).requires_color_choice() else TranslationServer.translate("清理%d枚") % leaf_target.piece_ids.size())
		elif leaf is DyeMaterialEffect:
			lines.append(TranslationServer.translate("染色预览：%s · %d枚") % [_color_name(leaf_target.color), leaf_target.piece_ids.size()])
	return " → ".join(lines) if not lines.is_empty() else TranslationServer.translate("有序组合效果")
