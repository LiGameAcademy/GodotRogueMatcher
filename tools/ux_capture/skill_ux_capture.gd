extends Node

## 固定验收盘面，只用于渲染真实场景截图；tools不进入Web发布包。
const MAIN: PackedScene = preload("res://main.tscn")
const OUTPUT: String = "res://production/skill_ux_review"
var game: Node2D
var board: Board
var hud: Hud

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var main: Node2D = MAIN.instantiate() as Node2D
	game = main.get_node("Game") as Node2D
	game.set("persist_preferences", false)
	game.set("record_runs", false)
	game.set("collect_telemetry", false)
	add_child(main)
	board = game.get_node("Board") as Board
	hud = game.get_node("UILayer/HUD") as Hud
	await board.initialized
	for piece: PieceState in board.rules.state.get_snapshot(): board.remove_piece(piece.coordinate)
	var coordinates: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(6, 1), Vector2i(2, 3), Vector2i(3, 3), Vector2i(5, 3), Vector2i(7, 4), Vector2i(1, 5), Vector2i(2, 5), Vector2i(4, 6), Vector2i(6, 6), Vector2i(7, 7), Vector2i(4, 8)]
	var colors: Array[int] = [0, 1, 2, 3, 0, 1, 4, 2, 3, 0, 4, 1, 2, 0]
	for index: int in range(coordinates.size()):
		var piece: PieceState = board.rules.place_piece(coordinates[index], colors[index])
		if index in [0, 4]: board.run.abilities.assign_fuse(piece.piece_id)
	board.run.abilities.add_core(Vector2i(8, 5))
	board.run.state.explosion.reward_level = 1
	board.rebuild_view()
	(hud.get_node("%Title") as Label).text = "固定盘面 · 交互验收"
	GameManager.add_score(500)
	await hud.wait_for_score()
	board.run.state.rewards.consumed_count = 2
	board.run.state.pending_rewards = 1
	board.run.enter_rewards()
	var refill: SkillOffer = _offer([&"refill_less"])
	var applied: SkillApplyResult = SkillRules.apply(board.run, refill.offer_id, &"refill_less")
	if not applied.success:
		push_error(applied.error)
		get_tree().quit(1)
		return
	board.run.state.phase = RunState.Phase.INPUT
	hud.show_run(board.run)
	hud.show_status("临时技能已生效 · 下次补棋2枚 · 剩余3次")
	await _capture("01_active_skill")
	board.run.state.pending_rewards = 1
	board.run.enter_rewards()
	_offer([&"instant_color_clear", &"instant_line_clear", &"score_multiplier"])
	LevelUpSystem.resolve_pending_rewards(board)
	await _frames(5)
	var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	if popup == null:
		push_error("截图验收未取得真实三选一")
		get_tree().quit(1)
		return
	popup._select(0)
	await _capture("02_color_unselected")
	popup.picker.confirm_selection()
	await _capture("03_color_required")
	popup.picker.select_color(0)
	popup.toggle_board_view()
	await _capture("04_board_inspection")
	popup.toggle_board_view()
	await _capture("05_color_selected")
	popup.picker.confirm_selection()
	await board.finish_presentation()
	await _frames(5)
	for batch: int in range(3):
		board.run.state.phase = RunState.Phase.INPUT
		var bot: RuleBot = RuleBot.new(8)
		var moves: Array[MovePieceCommand] = bot.legal_moves(board.run)
		var outcome: CommandResult = board.run.execute_command(moves[0])
		if not outcome.accepted:
			push_error(outcome.reason)
			get_tree().quit(1)
			return
		for step: int in range(6):
			var result: RunStepResult = board.run.advance()
			if result.kind == &"input": break
			if result.kind == &"offer":
				push_error("截图盘面出现额外奖励，停止以免跳过交互")
				get_tree().quit(1)
				return
		board.rebuild_view()
		hud.show_run(board.run)
		hud.show_status("实际补棋已消费 %d 次" % (batch + 1))
		if batch == 0: await _capture("06_skill_remaining_two")
	hud.history_button.set_pressed(true)
	hud.show_status("3次实际补棋已用完 · 技能退出当前列表 · 历史保留")
	await _capture("07_skill_consumed")
	print("UX_CAPTURE_COMPLETE ", ProjectSettings.globalize_path(OUTPUT))
	UIManager.close_popup()
	get_tree().paused = false
	get_tree().quit()

func _offer(ids: Array[StringName]) -> SkillOffer:
	var run: RunController = board.run
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = run.state.rewards.next_offer_id
	run.state.rewards.next_offer_id += 1
	offer.reward_id = run.state.rewards.consumed_count + 1
	for id: StringName in ids:
		for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
			if skill.skill_id != id: continue
			offer.choices.append(skill)
			offer.targets[id] = skill.choice_effect.freeze(SkillRules.effect_context(run.state), run.state.rewards.target_random) if skill.choice_effect != null else SkillTarget.new()
	run.state.rewards.active_offer = offer
	return offer

func _frames(count: int) -> void:
	for index: int in range(count): await get_tree().process_frame

func _capture(name: String) -> void:
	await _frames(6)
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var error: Error = image.save_png(OUTPUT.path_join(name + ".png"))
	if error != OK: push_error("截图保存失败：%s" % error_string(error))
