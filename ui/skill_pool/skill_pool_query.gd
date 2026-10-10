class_name SkillPoolQuery
extends RefCounted

enum Order { DEFAULT, RARITY, LEVEL, NAME }

## 即时技能没有持久等级，取得历史不作为等级。
static func level(run: RunController, skill: SkillDefinition) -> int:
	return SkillRules.level(run.state, skill) if skill.is_persistent else 0

static func select(run: RunController, tag: StringName = &"", rarity: int = -1, current_level: int = -1, order: Order = Order.DEFAULT) -> Array[SkillDefinition]:
	var result: Array[SkillDefinition] = []
	for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
		if not tag.is_empty() and not skill.tags.has(tag): continue
		if rarity >= 0 and skill.rarity != rarity: continue
		if current_level >= 0 and level(run, skill) != current_level: continue
		result.append(skill)
	result.sort_custom(func(a: SkillDefinition, b: SkillDefinition) -> bool:
		if order in [Order.DEFAULT, Order.RARITY] and a.rarity != b.rarity: return a.rarity > b.rarity
		if order in [Order.DEFAULT, Order.LEVEL] and level(run, a) != level(run, b): return level(run, a) > level(run, b)
		var a_name: String = TranslationServer.translate(a.title)
		var b_name: String = TranslationServer.translate(b.title)
		if a_name != b_name: return a_name.naturalnocasecmp_to(b_name) < 0
		return String(a.skill_id) < String(b.skill_id))
	return result
