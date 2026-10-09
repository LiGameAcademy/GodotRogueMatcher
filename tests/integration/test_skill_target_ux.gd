extends GutTest

const MAIN: PackedScene = preload("res://main.tscn")
var main: Node2D
var board: Board
var popup: PopupSkillChoice

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	UIManager.close_popup()
	main = MAIN.instantiate() as Node2D
	main.get_node("Game").set("persist_preferences", false)
	main.get_node("Game").set("record_runs", false)
	main.get_node("Game").set("collect_telemetry", false)
	add_child_autofree(main)
	board = main.get_node("Game/Board") as Board
	await board.initialized
	LevelUpSystem.reset_system()
	for piece: PieceState in board.rules.state.get_snapshot(): board.remove_piece(piece.coordinate)
	var red: PieceState = board.rules.place_piece(Vector2i(2, 2), 0)
	board.run.abilities.assign_fuse(red.piece_id)
	board.rules.place_piece(Vector2i(3, 2), 1)
	board.rules.place_piece(Vector2i(8, 8), 2)
	board.rebuild_view()
	var run: RunController = board.run
	run.state.rewards.consumed_count = 2
	run.state.pending_rewards = 1
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = 11
	offer.reward_id = 3
	for id: StringName in [&"instant_color_clear", &"score_multiplier", &"refill_less"]:
		for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
			if skill.skill_id != id: continue
			offer.choices.append(skill)
			offer.targets[id] = skill.choice_effect.freeze(SkillRules.effect_context(run.state), run.state.rewards.target_random) if skill.choice_effect != null else SkillTarget.new()
	run.state.rewards.active_offer = offer
	LevelUpSystem.resolve_pending_rewards(board)
	await wait_process_frames(4)
	popup = UIManager.current_popup as PopupSkillChoice
	assert_not_null(popup)

func after_each() -> void:
	UIManager.close_popup()
	get_tree().paused = false
	await wait_process_frames(3)

func test_color_has_no_default_invalid_confirm_only_highlights_without_consumption() -> void:
	var before: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	var card: SkillCard = popup.options.get_child(0) as SkillCard
	assert_eq(card.effect_label.mouse_filter, Control.MOUSE_FILTER_PASS, "术语提示接收悬停，点击继续向整卡传递")
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = card.effect_label.global_position + Vector2(8.0, 8.0)
	get_viewport().push_input(motion, true)
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = motion.position
	press.pressed = true
	get_viewport().push_input(press, true)
	var release: InputEventMouseButton = press.duplicate() as InputEventMouseButton
	release.pressed = false
	get_viewport().push_input(release, true)
	assert_true(popup.picker.visible)
	assert_eq(popup.picker.selected_color, -1)
	assert_string_contains((popup.picker.colors.get_child(0) as Button).text, "其中引信 1 枚")
	assert_true((popup.picker.colors.get_child(3) as Button).disabled)
	popup.picker.confirm_selection()
	assert_string_contains(popup.picker.hint.text, "请先选择颜色")
	assert_eq(popup.picker.frame.get_theme_stylebox("panel"), popup.picker.error_frame)
	assert_eq(popup.picker.selected_color, -1)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), before)
	assert_true(get_tree().paused)

func test_fold_view_pause_and_return_preserve_target_and_lock_board_without_reroll() -> void:
	popup._select(0)
	popup.picker.select_color(0)
	var before: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	popup.toggle_board_view()
	assert_true(popup.viewing_board)
	assert_false(popup.center.visible)
	assert_true(popup.return_bar.visible)
	assert_true(get_tree().paused)
	board._on_coordinate_pressed(Vector2i(2, 2))
	board._on_coordinate_pressed(Vector2i(2, 3))
	assert_false(await board.open_skill_demo())
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), before)
	assert_true(board.view.get_piece(board.rules.state.get_piece_id(Vector2i(2, 2))).tooltip_region.can_process())
	main.get_node("Game").call("_toggle_pause")
	assert_true(popup.selection_paused)
	assert_true(popup.pause_panel.visible)
	main.get_node("Game").call("_toggle_pause")
	assert_true(popup.viewing_board)
	popup.toggle_board_view()
	assert_eq(popup.picker.selected_color, 0)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), before)
	popup.return_to_choices()
	assert_true(popup.options.visible)
	assert_eq(board.run.state.rewards.active_offer.offer_id, 11)
	popup._select(0)
	assert_eq(popup.picker.selected_color, -1)

func test_color_confirm_applies_once_and_proceeds_through_real_reward_coordinator() -> void:
	popup._select(0)
	popup.picker.select_color(0)
	popup.picker.confirm_selection()
	assert_eq(board.run.state.rewards.consumed_count, 3)
	assert_eq(board.run.state.pending_rewards, 0)
	assert_eq(board.run.state.rules.state.get_piece_count(), 1)
	assert_false(get_tree().paused)
	assert_true(await board.finish_presentation())
	assert_eq(board.view._pieces.size(), 1)
	assert_eq(board.run.state.rewards.acquired[&"instant_color_clear"], 1)

func test_hud_temporary_skill_disappears_when_consumed_history_can_be_expanded() -> void:
	UIManager.close_popup()
	await wait_process_frames(2)
	var run: RunController = board.run
	run.state.rewards.acquired[&"refill_less"] = 1
	run.state.spawning.extend_refill(-1, 3)
	var hud: Hud = main.get_node("Game/UILayer/HUD") as Hud
	hud.show_run(run)
	assert_string_contains(HudDetails.skills(run.state), "剩余 3 次实际补棋")
	assert_false(hud.history_label.visible)
	run.state.spawning.consume_refill_count(RunController.SPAWN_CONFIG)
	hud.show_run(run)
	assert_string_contains(HudDetails.skills(run.state), "剩余 2 次实际补棋")
	for count: int in range(2): run.state.spawning.consume_refill_count(RunController.SPAWN_CONFIG)
	hud.show_run(run)
	assert_false(HudDetails.skills(run.state).contains("留白一手"))
	assert_false(hud.tools_label.text.contains("留白一手"))
	hud.history_button.set_pressed(true)
	assert_true(hud.history_label.visible)
	assert_string_contains(hud.history_label.text, "留白一手 · 取得 1 次")

func test_non_color_budget_refusal_keeps_offer_random_and_reward() -> void:
	var run: RunController = board.run
	for x: int in range(4): board.rules.place_piece(Vector2i(x, 0), run.abilities.config.core_color)
	var offer: SkillOffer = run.state.rewards.active_offer
	var core: SkillDefinition = preload("res://gameplay/progression/content/core_drop.tres")
	offer.choices[0] = core
	var target: SkillTarget = SkillTarget.new()
	target.coordinate = Vector2i(4, 0)
	offer.targets[core.skill_id] = target
	popup.show_offer(offer)
	var original_config: ExplosionConfig = run.abilities.config
	run.abilities.config = original_config.duplicate() as ExplosionConfig
	run.abilities.config.event_budget = 1
	var random_before: int = run.state.rewards.candidate_random.state
	var action_before: int = run.state.action_id
	popup._select(0)
	assert_same(run.state.rewards.active_offer, offer)
	assert_eq(run.state.rewards.candidate_random.state, random_before)
	assert_eq(run.state.pending_rewards, 1)
	assert_eq(run.state.action_id, action_before)
	assert_eq(board.rules.state.get_piece_id(target.coordinate), 0)
	assert_string_contains(popup.message.text, "预算")
	run.abilities.config = original_config

func test_paused_card_body_mouse_click_opens_picker_once_without_reroll() -> void:
	var card: SkillCard = popup.options.get_child(0) as SkillCard
	var click_count: Array[int] = [0]
	card.pressed.connect(func() -> void: click_count[0] += 1)
	var before: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	var position: Vector2 = card.effect_label.get_global_rect().get_center()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	get_viewport().push_input(motion, true)
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await wait_process_frames(2)
	assert_eq(click_count[0], 1)
	assert_true(popup.picker.visible)
	assert_eq(popup.picker.selected_color, -1)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), before)
	assert_true(get_tree().paused)
