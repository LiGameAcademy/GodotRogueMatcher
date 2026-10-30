class_name SkillRuleDescription
extends RefCounted
## Read-only supported-family projection. Diagnostics identify manual migration fallbacks.

const IDS: Array[StringName] = [&"score_multiplier", &"line_row_span", &"refill_less", &"goal_score_bonus", &"composite_refill_color", &"composite_clear_dye", &"refill_more", &"color_weight_up", &"color_weight_down", &"line_column_span", &"instant_color_clear", &"instant_color_dye", &"match_extra", &"blast_extra", &"blast_reward", &"line_clear_score"]
const EXPLOSION: ExplosionConfig = preload("res://gameplay/skills/content/explosion_config.tres")
const TRANSLATIONS: Dictionary[String, Translation] = {
	"en": preload("res://localization/skill_rules.en_US.translation"),
	"zh": preload("res://localization/skill_rules.zh_CN.translation")}

## level is the displayed owned/proposed level, not an acquisition-array index.
## A negative level denotes the catalog's configuration-only context.
static func describe(skill: SkillDefinition, level: int = -1, remaining: int = -1, owned: bool = false) -> Dictionary[String, String]:
	if skill == null: return _failure(null, "definition missing")
	if not IDS.has(skill.skill_id): return _failure(skill, "outside supported description slice")
	var error: String = skill.validation_error()
	if not error.is_empty(): return _failure(skill, error)
	if level == 0 or level < -1 or remaining < -1: return _failure(skill, "invalid display context")
	var shown_level: int = maxi(1, level)
	if skill.maximum_level > 0 and shown_level > skill.maximum_level:
		return _failure(skill, "display level exceeds maximum")
	var effect: SkillEffect = skill.acquisition_effect(shown_level - 1)
	if effect == null: return _failure(skill, "acquisition effect missing")
	var result: Dictionary[String, String] = _effect(effect, shown_level, remaining, owned, [])
	if not result.error.is_empty(): return _failure(skill, result.error)
	return result

static func _effect(effect: SkillEffect, level: int, remaining: int, owned: bool, ancestors: Array[SkillEffect]) -> Dictionary[String, String]:
	if effect == null: return {"text": "", "error": "effect missing"}
	if ancestors.has(effect) or ancestors.size() >= SkillEffect.MAX_EFFECT_DEPTH:
		return {"text": "", "error": "composite cycle/depth"}
	if effect is CompositeEffect:
		var composite: CompositeEffect = effect as CompositeEffect
		var validation: String = composite.validation_error()
		if not validation.is_empty(): return {"text": "", "error": validation}
		var next: Array[SkillEffect] = ancestors.duplicate()
		next.append(effect)
		var lines: PackedStringArray = []
		for index: int in range(composite.children.size()):
			var child: Dictionary[String, String] = _effect(composite.children[index], level, remaining, owned, next)
			if not child.error.is_empty(): return {"text": "", "error": "child[%d]: %s" % [index, child.error]}
			var step: Dictionary[String, String] = _format("rules.step", {"index": index + 1, "rule": child.text})
			if not step.error.is_empty(): return step
			lines.append(step.text)
		if composite.children.size() == 2 and composite.children[0] is RefillCountEffect and composite.children[1] is ColorWeightEffect:
			var refill: RefillCountEffect = composite.children[0] as RefillCountEffect
			var weight: ColorWeightEffect = composite.children[1] as ColorWeightEffect
			var values: Dictionary = {"delta": "%+d" % refill.delta, "weight": "%+d" % weight.delta}
			values["remaining" if owned else "batches"] = remaining if owned else refill.batches
			return _format("rules.mixed_owned" if owned else "rules.mixed", values)
		if composite.children.size() == 2 and composite.children[0] is ClearMaterialEffect and composite.children[1] is DyeMaterialEffect:
			var dye: DyeMaterialEffect = composite.children[1] as DyeMaterialEffect
			if ancestors.is_empty() and dye.dynamic_targets() and dye.allow_empty_targets and composite.fixed_target_policy == CompositeEffect.FixedTargetPolicy.REJECT:
				return _format("rules.clear_dye", {"count": DyeRules.CONFIG.instant_targets})
		if composite.fixed_target_policy == CompositeEffect.FixedTargetPolicy.SKIP_INVALID:
			var policy: Dictionary[String, String] = _format("rules.fixed_skip")
			if not policy.error.is_empty(): return policy
			lines.append(policy.text)
		# Only the outermost composition owns the descendant barrier.
		if ancestors.is_empty() and _has_material_effect(composite):
			var barrier: Dictionary[String, String] = _format("rules.barrier")
			if not barrier.error.is_empty(): return barrier
			lines.append(barrier.text)
		return {"text": "\n".join(lines), "error": ""}
	if effect is DemolitionStatEffect:
		var stat: DemolitionStatEffect.Stat = (effect as DemolitionStatEffect).stat
		if stat == DemolitionStatEffect.Stat.MULTIPLIER:
			return _format("rules.multiplier_owned" if owned else "rules.multiplier", {"delta": String.num(EXPLOSION.multiplier_per_level * (level if owned else 1), 3)})
		var key: String = ""
		var delta: int = 0
		match stat:
			DemolitionStatEffect.Stat.MATCH_EXTRA:
				key = "rules.match_extra"
				delta = EXPLOSION.bonus_per_match
			DemolitionStatEffect.Stat.BLAST_EXTRA:
				key = "rules.blast_extra"
				delta = EXPLOSION.bonus_per_blast
			DemolitionStatEffect.Stat.REWARD:
				key = "rules.blast_reward"
				delta = EXPLOSION.reward_per_target
			_:
				return {"text": "", "error": "unsupported demolition stat"}
		return _format(key, {"total": delta * level, "delta": delta})
	if effect is InstallLineUpgradeEffect:
		var line: InstallLineUpgradeEffect = effect as InstallLineUpgradeEffect
		if line.upgrade == &"line_clear_score" and line.required_axis == -1:
			return _format("rules.line_clear_score", {"total": LineClearRules.score_per_target(level), "delta": LineClearRules.score_per_target(1)})
		if line.required_axis not in [LineClearState.AXIS_ROW, LineClearState.AXIS_COLUMN] or line.upgrade != LineClearRules.upgrade_for_axis(line.required_axis):
			return {"text": "", "error": "unsupported line upgrade"}
		return _format("rules.row_span" if line.required_axis == LineClearState.AXIS_ROW else "rules.column_span", {"count": LineClearRules.line_count(level)})
	if effect is RefillCountEffect:
		var refill: RefillCountEffect = effect as RefillCountEffect
		if refill.delta not in [-1, 1] or refill.batches <= 0:
			return {"text": "", "error": "invalid refill parameters"}
		if owned:
			if remaining < 0: return {"text": "", "error": "owned refill remaining missing"}
			return _format("rules.refill_owned", {"delta": "%+d" % refill.delta, "remaining": remaining})
		return _format("rules.refill", {"delta": "%+d" % refill.delta, "batches": refill.batches})
	if effect is ColorWeightEffect:
		var weight: ColorWeightEffect = effect as ColorWeightEffect
		if weight.delta == 0: return {"text": "", "error": "zero weight delta"}
		if weight.dynamic_targets(): return {"text": "", "error": "unsupported dynamic weight"}
		return _format("rules.color_weight" if ancestors.is_empty() else "rules.weight", {"delta": "%+d" % weight.delta})
	if effect is InstallGoalBonusEffect:
		var goal: InstallGoalBonusEffect = effect as InstallGoalBonusEffect
		if goal.bonus_score <= 0: return {"text": "", "error": "invalid goal bonus"}
		return _format("rules.goal_owned" if owned else "rules.goal", {"score": goal.bonus_score})
	if effect is ClearMaterialEffect:
		var clear: ClearMaterialEffect = effect as ClearMaterialEffect
		if clear.selector != ClearMaterialEffect.Selector.COLOR or clear.score_cleared:
			return {"text": "", "error": "unsupported clear selector/scoring"}
		return _format("rules.clear")
	if effect is DyeMaterialEffect:
		var dye: DyeMaterialEffect = effect as DyeMaterialEffect
		if DyeRules.CONFIG.instant_targets <= 0: return {"text": "", "error": "invalid dye target count"}
		if ancestors.is_empty() and not dye.dynamic_targets() and not dye.allow_empty_targets:
			return _format("rules.dye_fixed_root", {"count": DyeRules.CONFIG.instant_targets})
		var dye_text: Dictionary[String, String] = _format("rules.dye_dynamic" if dye.dynamic_targets() else "rules.dye_fixed", {"count": DyeRules.CONFIG.instant_targets})
		if not dye_text.error.is_empty(): return dye_text
		var empty: Dictionary[String, String] = _format("rules.empty_skip" if dye.allow_empty_targets else "rules.empty_reject")
		if not empty.error.is_empty(): return empty
		return {"text": dye_text.text + " " + empty.text, "error": ""}
	return {"text": "", "error": "unsupported effect: " + str(effect.get_script().resource_path)}

static func _has_material_effect(effect: SkillEffect) -> bool:
	if effect is ClearMaterialEffect or effect is DyeMaterialEffect: return true
	if effect is CompositeEffect:
		for child: SkillEffect in (effect as CompositeEffect).children:
			if _has_material_effect(child): return true
	return false

static func _format(key: String, values: Dictionary = {}) -> Dictionary[String, String]:
	var language: String = TranslationServer.get_locale().get_slice("_", 0)
	var translation: Translation = TRANSLATIONS.get(language)
	var error: String = _translation_error(translation, key)
	if not error.is_empty(): return {"text": "", "error": language + ": " + error}
	var template: String = TranslationServer.translate(key)
	if template == key: return {"text": "", "error": "translation missing: " + key}
	for name: Variant in values:
		if not template.contains("{" + str(name) + "}"):
			return {"text": "", "error": "translation parameter missing: " + key + "/" + str(name)}
	var text: String = template.format(values)
	if text.contains("{") or text.contains("}"): return {"text": "", "error": "unresolved translation parameter: " + key}
	return {"text": text, "error": ""}

## Preview/remaining labels share the same locale and parameter validation.
static func preview(key: String, values: Dictionary = {}) -> Dictionary[String, String]:
	var result: Dictionary[String, String] = _format(key, values)
	if not result.error.is_empty():
		result.text = "[Manual preview]" if TranslationServer.get_locale().begins_with("en") else "[人工预览]"
	return result

## Validate the requested language before TranslationServer can hide a missing entry.
static func _translation_error(translation: Translation, key: String) -> String:
	if translation == null or translation.get_message(key).is_empty():
		return "translation missing: " + key
	return ""

static func _failure(skill: SkillDefinition, reason: String) -> Dictionary[String, String]:
	var manual: String = "[Manual rule]" if TranslationServer.get_locale().begins_with("en") else "[人工规则]"
	var previous: String = "" if skill == null else TranslationServer.translate(skill.description if skill.short_description.is_empty() else skill.short_description)
	var identity: String = "null" if skill == null else "%s (%s)" % [skill.skill_id, skill.resource_path]
	return {"text": manual + " " + previous, "error": identity + ": " + reason}
