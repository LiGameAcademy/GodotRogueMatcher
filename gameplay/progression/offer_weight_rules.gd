class_name OfferWeightRules
extends RefCounted

## Explains one candidate from one frozen build projection without consuming randoms.
static func evaluate(skill: SkillDefinition, snapshot: SkillBuildSnapshot, choice_index: int, reason: String, config: OfferConfig) -> Dictionary:
	var traits: SkillOfferTraits = skill.offer_traits
	var related: bool = snapshot.related(traits)
	var gaps: Array[StringName] = snapshot.gap_routes(traits)
	var fills_gap: bool = reason.is_empty() and not gaps.is_empty()
	var before_clamp: float = 1.0 + config.related_gain * int(related) + config.gap_gain * int(fills_gap)
	var factor: float = clampf(before_clamp, config.factor_min, config.factor_max)
	var base: float = config.base_weight(skill.rarity, choice_index)
	var eligible: bool = reason.is_empty()
	return {"H": int(eligible), "rejection": reason, "B": base, "Q": traits.exception_multiplier,
		"related": int(related), "fills_gap": int(fills_gap), "gap_routes": gaps,
		"s": 0.0, "V": 1.0, "factor_before_clamp": before_clamp, "factor_after_clamp": factor,
		"weight_before_clamp": int(eligible) * base * traits.exception_multiplier * before_clamp,
		"W": int(eligible) * base * traits.exception_multiplier * factor,
		"mechanisms": traits.mechanisms.duplicate(), "affinity": traits.affinity.duplicate(),
		"supplies": traits.supplies.duplicate(), "payoffs": traits.payoffs.duplicate(),
		"needs": traits.needs.duplicate(), "roles": traits.roles.duplicate(), "lifetime": traits.lifetime,
		"once_per_run": traits.once_per_run, "upgradeable": traits.upgradeable, "repeatable": traits.repeatable}
