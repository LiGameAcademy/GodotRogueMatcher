extends RefCounted

class FixedDye extends DyeMaterialEffect:
	var ids: Array[int] = []
	var selected: int = 0
	func _init() -> void:
		target_policy = TargetPolicy.FIXED
	func freeze(_context: ChoiceEffectContext, _random: RandomNumberGenerator) -> SkillTarget:
		var target: SkillTarget = SkillTarget.new()
		target.piece_ids = ids.duplicate()
		target.color = selected
		return target

class FailAfterMatch extends ChoiceEffect:
	func rejection(_context: ChoiceEffectContext) -> String:
		return ""
	func build(context: ChoiceEffectContext, _target: SkillTarget) -> ChoiceEffectRequest:
		var request: ChoiceEffectRequest = ChoiceEffectRequest.new()
		if context.material.size() < 3: request.error = "injected_after_match"
		return request

static func run() -> RunController:
	var result: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 135)
	populate(result)
	return result

static func populate(result: RunController) -> void:
	result.abilities.config = result.abilities.config.duplicate() as ExplosionConfig
	result.abilities.config.reward_per_target = 0
	result.abilities.config.bonus_per_blast = 0
	for x: int in range(1, 5): result.state.rules.place_piece(Vector2i(x, 2), 0)
	result.abilities.assign_fuse(result.state.rules.state.get_piece_at(Vector2i(3, 2)).piece_id)
	result.state.rules.place_piece(Vector2i(5, 2), 1)
	result.state.rules.place_piece(Vector2i(3, 3), 2)
	result.state.rules.place_piece(Vector2i(8, 8), 2)
	result.state.pending_rewards = 1
	result.enter_rewards()

static func first(run_state: RunController) -> FixedDye:
	var dye: FixedDye = FixedDye.new()
	dye.ids = [run_state.state.rules.state.get_piece_at(Vector2i(5, 2)).piece_id]
	return dye

static func skill(effect: SkillEffect) -> SkillDefinition:
	var ability: AbilityDefinition = AbilityDefinition.new()
	ability.ability_id = &"bst_contract_acquire"
	ability.event_type = &"skill_acquired"
	ability.effect = effect
	var level: SkillLevelDefinition = SkillLevelDefinition.new()
	level.level = 1
	level.abilities = [ability]
	var definition: SkillDefinition = SkillDefinition.new()
	definition.skill_id = &"bst_contract_fixture"
	definition.maximum_level = 1
	definition.levels = [level]
	return definition

static func offer(controller: RunController, effect: SkillEffect) -> SkillOffer:
	var generator: SkillOfferGenerator = SkillOfferGenerator.new()
	generator.set_catalog([skill(effect)])
	return generator.generate(controller)

static func apply(controller: RunController, current: SkillOffer, color: int = -1) -> SkillApplyResult:
	return SkillRules.apply(controller, current.offer_id, current.choices[0].skill_id, color)
