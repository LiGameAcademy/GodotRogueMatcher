extends GutTest

const MAIN: PackedScene = preload("res://main.tscn")
const POPUP: PackedScene = preload("res://ui/popup_skill_choice.tscn")
var main: Node2D
var board: Board

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	UIManager.close_popup()
	main = MAIN.instantiate() as Node2D
	main.get_node("Game").set("persist_preferences", false)
	(main.get_node("Game/Board") as Board).game_mode = GameModes.CLASSIC
	add_child_autofree(main)
	board = main.get_node("Game/Board") as Board
	await board.initialized
	for piece: PieceState in board.rules.state.get_snapshot(): board.remove_piece(piece.coordinate)

func after_each() -> void:
	get_tree().paused = false
	UIManager.close_popup()
	await wait_process_frames(2)

func test_popup_shows_frozen_colors_counts_and_hud_shows_actual_generation_state() -> void:
	var run: RunController = board.run
	run.state.rules.place_piece(Vector2i(2, 3), 0)
	var offer: SkillOffer = SkillOffer.new()
	for id: StringName in [&"refill_less", &"color_weight_up", &"instant_line_clear"]:
		for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
			if skill.skill_id != id: continue
			offer.choices.append(skill)
			offer.targets[id] = skill.choice_effect.freeze(SkillRules.effect_context(run.state), run.state.rewards.target_random)
	var popup: PopupSkillChoice = POPUP.instantiate() as PopupSkillChoice
	add_child_autofree(popup)
	var random_before: int = run.state.rewards.target_random.state
	popup.show_offer(offer)
	var texts: Array[String] = []
	for card: SkillCard in popup.options.get_children(): texts.append(card.preview_label.text)
	assert_string_contains(texts[0], "3 → 2 枚")
	assert_string_contains(texts[1], "4 → 6")
	assert_string_contains(texts[2], "直接清理 1 枚")
	popup.show_offer(offer)
	assert_eq(run.state.rewards.target_random.state, random_before)
	run.state.spawning.extend_refill(-1, 3)
	run.state.spawning.color_weights[0] = 6
	assert_string_contains(HudDetails.skills(run.state), "下次普通补棋 2 枚")
	assert_string_contains(HudDetails.skills(run.state), "红色 6／22（27.3%）")

func test_clear_then_blast_presentation_aligns_rule_and_view_at_two_speeds() -> void:
	for fast: bool in [false, true]:
		for piece: PieceState in board.rules.state.get_snapshot(): board.remove_piece(piece.coordinate)
		var run: RunController = board.run
		run.state.rewards.consumed_count = 2
		run.state.pending_rewards = 1
		run.enter_rewards()
		var fuse: PieceState = run.state.rules.place_piece(Vector2i(2, 2), 0)
		run.abilities.assign_fuse(fuse.piece_id)
		run.state.rules.place_piece(Vector2i(3, 2), 1)
		run.state.rules.place_piece(Vector2i(8, 8), 2)
		board.rebuild_view()
		var skill: SkillDefinition = preload("res://gameplay/progression/content/instant_color_clear.tres")
		var offer: SkillOffer = SkillOffer.new()
		offer.offer_id = 9
		offer.reward_id = 3
		offer.choices = [skill]
		var target: SkillTarget = SkillTarget.new()
		target = skill.choice_effect.freeze(SkillRules.effect_context(run.state), run.state.rewards.target_random)
		offer.targets[skill.skill_id] = target
		offer.targets[skill.skill_id] = target
		run.state.rewards.active_offer = offer
		var result: SkillApplyResult = SkillRules.apply(run, offer.offer_id, skill.skill_id, 0)
		assert_true(result.success)
		board.set_playback_fast(fast)
		board.present_skill_result(result)
		assert_true(await board.finish_presentation())
		assert_eq(run.state.rules.state.get_piece_count(), 1)
		assert_eq(board.view._pieces.size(), 1)
		assert_eq(board.director.error, "")
		assert_not_null(board.get_cell(Vector2i(8, 8)).piece)

func test_skill_clear_chain_finishes_and_score_arrives_before_next_reward_popup() -> void:
	var run: RunController = board.run
	GameManager.add_score(500)
	run.state.rewards.consumed_count = 2
	run.state.pending_rewards = 1
	var fuse: PieceState = run.state.rules.place_piece(Vector2i(2, 2), 0)
	run.abilities.assign_fuse(fuse.piece_id)
	run.state.rules.place_piece(Vector2i(3, 2), 1)
	run.state.explosion.reward_level = 100
	board.rebuild_view()
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = 9
	offer.reward_id = 3
	for id: StringName in [&"instant_color_clear", &"score_multiplier", &"match_extra"]:
		for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
			if skill.skill_id == id:
				offer.choices.append(skill)
				offer.targets[id] = SkillTarget.new()
	var target: SkillTarget = offer.targets[&"instant_color_clear"]
	offer.targets[&"instant_color_clear"] = offer.choices[0].choice_effect.freeze(SkillRules.effect_context(run.state), run.state.rewards.target_random)
	run.state.rewards.active_offer = offer
	LevelUpSystem.resolve_pending_rewards(board)
	await board.finish_presentation()
	await wait_process_frames(3)
	var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	assert_not_null(popup)
	popup._select(0)
	popup.picker.select_color(0)
	popup.picker.confirm_selection()
	assert_eq(GameManager.score, 1000)
	assert_true(board.view.is_presenting())
	assert_false(get_tree().paused)
	await wait_process_frames(3)
	assert_false(is_instance_valid(UIManager.current_popup) and UIManager.current_popup.visible)
	await board.finish_presentation()
	await wait_process_frames(3)
	var next: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	assert_not_null(next)
	assert_eq(next.offer.reward_id, 4)
	assert_eq((main.get_node("Game/UILayer/HUD") as Hud).displayed_score, 1000)
	assert_false(board.view.is_presenting())
