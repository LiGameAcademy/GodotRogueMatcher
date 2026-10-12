class_name SkillChoiceText
extends RefCounted
const TAG_LABELS: Dictionary[StringName, String] = {&"exp": "爆破", &"dye": "染色", &"generation": "生成", &"match": "连珠", &"mult": "倍率", &"space": "空间", &"goal": "目标", &"extra": "额外分"}
const CONSUME_HINT: String = "每次实际补棋扣1次，次数用完后失效；免补棋不扣次数。"

## 卡面消费已冻结目标，不自行抽取或改变规则。
static func summary(skill: SkillDefinition) -> String:
	return TranslationServer.translate(skill.description if skill.short_description.is_empty() else skill.short_description)

static func summary_rich(skill: SkillDefinition) -> String:
	var text: String = summary(skill)
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
	var effect: SkillEffect = skill.acquisition_effect(target.level_before)
	if effect is InstallGoalBonusEffect:
		return TranslationServer.translate("每次达标：+%d分") % target.value_after
	if effect is PercentClearEffect:
		return TranslationServer.translate("本次清理：%d枚普通棋") % target.piece_ids.size()
	if effect is UnlockCoreSupplyEffect:
		return TranslationServer.translate("立即投放：%s") % _color_name(target.color)
	if effect is CompositeEffect:
		var composite_target: CompositeSkillTarget = target as CompositeSkillTarget
		if composite_target == null or composite_target.leaf_targets.is_empty():
			return TranslationServer.translate("有序组合效果")
		var lines: PackedStringArray = []
		var composite: CompositeEffect = effect as CompositeEffect
		for index: int in range(mini(composite.children.size(), composite_target.leaf_targets.size())):
			var leaf: SkillEffect = composite.children[index]
			var leaf_target: SkillTarget = composite_target.leaf_targets[index]
			if leaf is RefillCountEffect:
				lines.append(TranslationServer.translate("补棋：%d → %d") % [leaf_target.value_before, leaf_target.value_after])
			elif leaf is ColorWeightEffect:
				lines.append(TranslationServer.translate("%s权重：%d → %d") % [_color_name(leaf_target.color), leaf_target.value_before, leaf_target.value_after])
			elif leaf is ClearMaterialEffect:
				lines.append(TranslationServer.translate("自选颜色清理") if (leaf as ClearMaterialEffect).requires_color_choice() else TranslationServer.translate("清理%d枚") % leaf_target.piece_ids.size())
			elif leaf is DyeMaterialEffect:
				lines.append(TranslationServer.translate("染色预览：%s · %d枚") % [_color_name(leaf_target.color), leaf_target.piece_ids.size()])
		return " → ".join(lines) if not lines.is_empty() else TranslationServer.translate("有序组合效果")
	if effect is RefillCountEffect:
		return TranslationServer.translate("本次补棋：%d → %d 枚 · 余%d次") % [target.value_before, target.value_after, target.remaining_after]
	if effect is ClearMaterialEffect:
		if (effect as ClearMaterialEffect).requires_color_choice(): return TranslationServer.translate("自选颜色 · 保留特殊棋")
		var group: String = _color_name(target.color) if target.line_axis == -1 else TranslationServer.translate("第%d%s") % [target.line_index + 1, TranslationServer.translate("行") if target.line_axis == 0 else TranslationServer.translate("列")]
		return TranslationServer.translate("%s · 清理%d枚普通棋") % [group, target.piece_ids.size()]
	if effect is ColorWeightEffect:
		return TranslationServer.translate("%s权重：%d → %d") % [_color_name(target.color), target.value_before, target.value_after]
	if effect is DyeMaterialEffect:
		return TranslationServer.translate("%s · 同时染色 %d 枚") % [_color_name(target.color), target.piece_ids.size()]
	return ""

static func level_text(skill: SkillDefinition, target: SkillTarget) -> String:
	if not skill.is_persistent: return ""
	var result: String = "Lv.%d  →  Lv.%d" % [target.level_before, target.level_after]
	if skill.maximum_level > 0 and target.level_after >= skill.maximum_level: result += TranslationServer.translate("  ·  满级")
	return result

static func _color_name(color: int) -> String:
	return TranslationServer.translate(PieceTooltip.COLOR_NAMES[color]) if color >= 0 and color < PieceTooltip.COLOR_NAMES.size() else TranslationServer.translate("未知颜色")
