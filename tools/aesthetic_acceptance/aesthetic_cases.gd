class_name AestheticCases
extends RefCounted

## 展示夹具只布置初态；行动、选卡、匹配和计分使用正式入口。
const KEYS: Array[String] = ["match", "blast_row", "row_blast", "shape", "cards"]
const CARDS: Array[SkillDefinition] = [
	preload("res://gameplay/progression/content/core_supply_up.tres"),
	preload("res://gameplay/progression/content/refill_less.tres"),
	preload("res://gameplay/progression/content/composite_clear_dye.tres")]

## 三句仅用于 #128 样片评审；复制定义，不改正式池共享Resource。
static func card_samples() -> Array[SkillDefinition]:
	var texts: Array[String] = ["好搭档，总会再碰面。", "留点空位，下一手更从容。", "先收拾，再换个心情。"]
	var samples: Array[SkillDefinition] = []
	for index: int in range(CARDS.size()):
		var sample: SkillDefinition = CARDS[index].duplicate() as SkillDefinition
		sample.flavor_text = texts[index]
		samples.append(sample)
	return samples

static func create(key: String) -> RunController:
	var samples: Array[SkillDefinition] = card_samples()
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 128)
	if key == "shape":
		run = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 128, null, RunController.PROTOTYPE_PROFILE)
		run.initialize("fixture_shape_unlock")
		offer(run, [ShapeUnlockDemo.l()])
		return run
	if key in ["match", "blast_row"]:
		for x: int in range(1, 5): run.state.rules.place_piece(Vector2i(x, 4), 1)
		if key == "match": run.state.rules.place_piece(Vector2i(5, 5), 1)
		else:
			run.abilities.add_core(Vector2i(5, 5), 1)
			run.abilities.add_line_piece(LineClearState.AXIS_ROW, Vector2i(6, 4), 2)
			run.state.rules.place_piece(Vector2i(8, 4), 3)
			run.abilities.upgrade_reward()
	elif key == "row_blast":
		run.state.line_clear.row_unlocked = true
		run.abilities.add_line_piece(LineClearState.AXIS_ROW, Vector2i(1, 4), 0)
		run.abilities.add_core(Vector2i(5, 4), 1)
		run.state.rules.place_piece(Vector2i(5, 3), 3)
		run.state.rules.place_piece(Vector2i(6, 3), 4)
		run.abilities.upgrade_reward()
		install(run, load("res://gameplay/progression/content/line_manual_clear.tres") as SkillDefinition)
	elif key == "cards":
		run.abilities.add_core(Vector2i(6, 6), 2)
		run.state.explosion.core_pool_unlocked = true
		run.state.rewards.consumed_count = 3
		for y: int in range(7):
			for x: int in range(9):
				if run.state.rules.state.get_piece_id(Vector2i(x, y)) == 0:
					run.state.rules.place_piece(Vector2i(x, y), (x + y * 2) % 5)
		install(run, samples[0])
	# 不清空后触发无关的空盘恢复，保留一枚不参与当前匹配的真实棋子。
	if run.state.rules.state.get_piece_id(Vector2i(8, 8)) == 0:
		run.state.rules.place_piece(Vector2i(8, 8), 4)
	run.start_turn()
	if key == "cards": offer(run, samples)
	return run

static func offer(run: RunController, skills: Array[SkillDefinition]) -> SkillOffer:
	run.state.pending_rewards = 1
	run.enter_rewards()
	var result: SkillOffer = SkillOffer.new()
	result.offer_id = run.state.rewards.next_offer_id
	run.state.rewards.next_offer_id += 1
	result.reward_id = run.state.rewards.consumed_count + 1
	for skill: SkillDefinition in skills:
		result.choices.append(skill)
		result.targets[skill.skill_id] = SkillRules.freeze_target(run.state, skill)
	run.state.rewards.active_offer = result
	return result

static func install(run: RunController, skill: SkillDefinition) -> void:
	var frozen: SkillOffer = offer(run, [skill])
	var result: SkillApplyResult = SkillRules.apply(run, frozen.offer_id, skill.skill_id)
	if not result.success: run.report_error(result.error)
