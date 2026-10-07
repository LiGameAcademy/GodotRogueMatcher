extends Node

## 固定验收盘面；只走真实技能与棋盘入口，不进入发布包或采集样本。
const MAIN: PackedScene = preload("res://main.tscn")
var output_directory: String = "res://production/demolition_review"
var board: Board
var hud: Hud

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			var directory: String = argument.trim_prefix("--capture-dir=")
			if directory.is_valid_filename(): output_directory = "res://production/" + directory
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_directory))
	var main: Node2D = MAIN.instantiate() as Node2D
	var game: Node2D = main.get_node("Game") as Node2D
	game.set("persist_preferences", false)
	game.set("record_runs", false)
	game.set("collect_telemetry", false)
	add_child(main)
	board = game.get_node("Board") as Board
	hud = game.get_node("UILayer/HUD") as Hud
	await board.initialized
	for piece: PieceState in board.rules.state.get_snapshot(): board.remove_piece(piece.coordinate)
	for x: int in range(2, 7):
		for y: int in range(2, 7):
			if Vector2i(x, y) != Vector2i(4, 4): board.rules.place_piece(Vector2i(x, y), posmod(x + y * 2, 5))
	GameManager.add_score(500)
	await hud.wait_for_score()
	board.run.state.rewards.consumed_count = 5
	for id: StringName in [&"core_drop", &"core_manual_detonation", &"core_fuse_payload", &"blast_reward", &"blast_radius", &"marked_reward", &"chain_reward"]:
		board.run.state.pending_rewards = 1
		board.run.enter_rewards()
		var offer: SkillOffer = _offer([id])
		if id == &"core_drop": offer.targets[id].coordinate = Vector2i(4, 4)
		var result: SkillApplyResult = SkillRules.apply(board.run, offer.offer_id, id)
		if not result.success:
			push_error(result.error)
			get_tree().quit(1)
			return
	board.run.state.phase = RunState.Phase.INPUT
	board.rebuild_view()
	hud.show_run(board.run)
	(hud.get_node("%Title") as Label).text = "爆破构筑 · 32技能验收"
	board.run.state.pending_rewards = 1
	board.run.enter_rewards()
	_offer([&"blast_chain_bonus", &"blast_chain_radius", &"blast_aftershock"])
	LevelUpSystem.resolve_pending_rewards(board)
	await _frames(8)
	var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	if popup == null:
		push_error("未取得真实技能面板")
		get_tree().quit(1)
		return
	await _capture("01_rarity_choices")
	popup._select(2)
	await board.finish_presentation()
	await _frames(8)
	board.run.state.phase = RunState.Phase.INPUT
	board.can_selected = true
	board.selected_piece = board.view.get_piece(board.rules.state.get_piece_id(Vector2i(4, 4)))
	hud.show_run(board.run)
	hud.show_status("主动爆破已安装 · 双击核心消耗一次行动并正常补棋")
	await _capture("02_build_ready")
	board._on_piece_activated(Vector2i(4, 4))
	await _frames(4)
	await _capture("03_detonation")
	for frame: int in range(600):
		if board.can_selected: break
		await get_tree().process_frame
	if not board.can_selected or not board.run.state.rule_error.is_empty():
		push_error("主动爆破未完成回合：" + board.run.state.rule_error)
		get_tree().quit(1)
		return
	hud.show_run(board.run)
	hud.show_status("连锁与余震已结算 · 正常补棋完成 · 已安装强化保留")
	await _capture("04_settled")
	print("DEMOLITION_CAPTURE_COMPLETE ", ProjectSettings.globalize_path(output_directory))
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
			var target: SkillTarget = skill.choice_effect.freeze(SkillRules.effect_context(run.state), run.state.rewards.target_random) if skill.choice_effect != null else SkillTarget.new()
			target.level_before = SkillRules.level(run.state, skill)
			target.level_after = target.level_before + 1
			offer.targets[id] = target
	run.state.rewards.active_offer = offer
	return offer

func _frames(count: int) -> void:
	for frame: int in range(count): await get_tree().process_frame

func _capture(name: String) -> void:
	await _frames(20)
	await RenderingServer.frame_post_draw
	var screenshot: Image = get_viewport().get_texture().get_image()
	var error: Error = screenshot.save_png(output_directory.path_join(name + ".png"))
	if error != OK: push_error(error_string(error))
