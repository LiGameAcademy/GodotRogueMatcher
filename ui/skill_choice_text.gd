class_name SkillChoiceText
extends RefCounted

## 卡面消费已冻结目标，不自行抽取或改变规则。
static func describe(skill: SkillDefinition, target: SkillTarget) -> String:
	return "%s\n%s\n%s\n\n%s\n\n%s" % [SkillRarity.LABELS[skill.rarity], skill.title, level_text(skill, target), preview(skill, target), skill.description]

static func kind(skill: SkillDefinition) -> String:
	if skill.choice_effect is RefillCountEffect: return "限次持续"
	return "局内强化" if skill.is_persistent else "即时工具"

static func level_text(skill: SkillDefinition, target: SkillTarget) -> String:
	if not skill.is_persistent: return "实际补棋时消耗次数" if skill.choice_effect is RefillCountEffect else "即时生效 · 不消耗行动"
	var result: String = "Lv.%d  →  Lv.%d" % [target.level_before, target.level_after]
	if skill.maximum_level > 0 and target.level_after >= skill.maximum_level: result += "  ·  满级"
	return result

static func preview(skill: SkillDefinition, target: SkillTarget) -> String:
	var detail: String = ""
	if skill.choice_effect is InstallUpgradeEffect:
		detail = "局内保留 · 核心离场不卸下" if skill.requires_core else "本局持续生效 · 重试后重置"
	if skill.choice_effect is RefillCountEffect:
		detail = "实际补棋：%d → %d 枚\n剩余批次：%d → %d 次" % [target.value_before, target.value_after, target.remaining_before, target.remaining_after]
	elif skill.choice_effect is ColorWeightEffect:
		detail = "%s权重：%d → %d" % [_color_name(target.color), target.value_before, target.value_after]
	elif skill.choice_effect is ClearMaterialEffect:
		if skill.choice_effect.requires_color_choice():
			return "由你选择要清理的颜色\n可收起面板查看棋盘"
		var group: String = _color_name(target.color) if target.line_axis == -1 else "第%d%s" % [target.line_index + 1, "行" if target.line_axis == 0 else "列"]
		detail = "%s · 直接清理 %d 枚\n引信爆炸可能继续扩大清理范围。" % [group, target.piece_ids.size()]
	return detail

static func emblem(skill: SkillDefinition) -> String:
	if skill.tags.has(&"exp"): return "爆"
	if skill.tags.has(&"generation"): return "生"
	if skill.tags.has(&"utility"): return "清"
	return "连"

static func _color_name(color: int) -> String:
	return PieceTooltip.COLOR_NAMES[color] if color >= 0 and color < PieceTooltip.COLOR_NAMES.size() else "未知颜色"
