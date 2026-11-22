extends GutTest

const MAIN: PackedScene = preload("res://main.tscn")
const VIEWER: PackedScene = preload("res://tools/bot_testing/result_viewer.tscn")
var board: Board

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	UIManager.close_popup()
	var main: Node = MAIN.instantiate()
	main.get_node("Game").set("persist_preferences", false)
	add_child_autofree(main)
	board = main.get_node("Game/Board") as Board
	await board.initialized
	(main.get_node("Game/GameFeedback") as GameFeedback).set_volume(0.0)

func after_each() -> void:
	get_tree().paused = false
	UIManager.close_popup()
	await wait_process_frames(2)

func test_f12_offer_confirms_and_transforms_same_nodes_with_exact_file_replay() -> void:
	var game: Node = board.get_parent()
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_F12
	key.pressed = true
	game._unhandled_key_input(key)
	for _frame: int in range(120):
		if UIManager.current_popup is PopupSkillChoice: break
		await wait_process_frames(1)
	assert_eq(board.run.initialization, "fixture_transform")
	var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	assert_not_null(popup)
	if popup == null: return
	await wait_process_frames(2)
	var skill_id: StringName = &"instant_core_transform"
	var offer: SkillOffer = board.run.state.rewards.active_offer
	var target: SkillTarget = offer.targets[skill_id]
	var nodes: Array[ChessPiece] = []
	for id: int in target.piece_ids: nodes.append(board.view.get_piece(id))
	popup.skill_selected.emit(offer.offer_id, skill_id)
	for _frame: int in range(180):
		if board.can_selected and not board.view.is_presenting(): break
		await wait_process_frames(1)
	assert_true(board.can_selected)
	assert_eq(board.run.state.phase, RunState.Phase.INPUT)
	for index: int in range(target.piece_ids.size()):
		var id: int = target.piece_ids[index]
		assert_same(board.view.get_piece(id), nodes[index])
		assert_eq(nodes[index].piece_type, board.rules.state.get_piece(id).match_color)
		assert_eq(board.rules.state.get_piece(id).content_id, &"special_demolition")
	var snapshot: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	board.run.recorder.finish(board.run, "abandoned", "conversion_scene_test")
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay_file(board.run.recorder.path), replay.error)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(replay.run)), snapshot)
	var viewer: ResultViewer = VIEWER.instantiate() as ResultViewer
	add_child_autofree(viewer)
	assert_true(viewer.load_record(board.run.recorder.path), viewer.error)
	viewer.view.presentation_speed = 16.0
	while viewer.cursor < viewer.records.size(): await viewer.step()
	assert_eq(viewer.error, "")
	assert_eq(RunSnapshot.digest(viewer.current_state), snapshot)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), snapshot)

func test_transform_plan_copies_snapshots_and_low_effects_preserve_nodes() -> void:
	assert_true(board.load_explosion_demo("fixture_transform"))
	var run: RunController = board.run
	var skill_id: StringName = &"instant_row_transform"
	var offer: SkillOffer = run.state.rewards.active_offer
	var result: SkillApplyResult = SkillRules.apply(run, offer.offer_id, skill_id)
	assert_true(result.success, result.error)
	var steps: Array[PresentationStep] = PlaybackPlanBuilder.skill(result, 0.12)
	assert_eq(steps.size(), 1)
	assert_eq(steps[0].kind, PresentationStep.Kind.TRANSFORM)
	var id: int = result.transformed[0].piece_id
	var node: ChessPiece = board.view.get_piece(id)
	result.transformed[0].match_color = (result.transformed[0].match_color + 1) % 5
	assert_eq(steps[0].pieces[0].match_color, run.state.rules.state.get_piece(id).match_color)
	board.view.set_low_effects(true)
	for piece: PieceState in steps[0].pieces: board.view.animate_transform(piece, 0.12)
	assert_same(board.view.get_piece(id), node)
	assert_false(board.view.is_presenting())

func test_compact_card_lands_before_piece_feedback(
	use_fuse: bool = use_parameters([false, true])
) -> void:
	var window: Window = get_window()
	var original_size: Vector2i = window.size
	window.size = Vector2i(568, 320)
	await wait_process_frames(3)
	var game: Node = board.get_parent()
	var transfer: CardTransfer = game.get_node("CardTransfer")
	var slot: TextureRect = game.get_node("UILayer/HUD/%RewardSlot")
	assert_true(slot.is_visible_in_tree())
	assert_true(board.load_explosion_demo("fixture_transform"))
	var offer: SkillOffer = board.run.state.rewards.active_offer
	var skill: SkillDefinition = offer.choices[0]
	if use_fuse:
		skill = preload("res://gameplay/progression/content/assign_fuse.tres")
		offer.choices[0] = skill
		offer.targets[skill.skill_id] = SkillRules.freeze_target(board.run.state, skill)
	board.can_selected = false
	BoardRunFlow.continue_run(board, board.run)
	for frame: int in range(180):
		if UIManager.current_popup is PopupSkillChoice: break
		await wait_process_frames(1)
	var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	assert_not_null(popup)
	if popup == null:
		window.size = original_size
		return
	await wait_process_frames(2)
	var tracked: Array[Node2D] = []
	for piece: PieceState in board.rules.state.get_snapshot():
		var visual: ChessPiece = board.view.get_piece(piece.piece_id)
		tracked.append(visual.get_node("FuseSpark" if use_fuse else "ConversionBurst"))
	popup._select(0)
	popup.confirm_selection()
	assert_true((transfer.get_node("FlightIcon") as TextureRect).visible)
	assert_true(tracked.all(func(visual: Node2D) -> bool: return not visual.visible))
	assert_null(slot.texture)
	for frame: int in range(180):
		if tracked.any(func(visual: Node2D) -> bool: return visual.visible): break
		await wait_process_frames(1)
	assert_true(tracked.any(func(visual: Node2D) -> bool: return visual.visible))
	assert_false((transfer.get_node("FlightIcon") as TextureRect).visible)
	assert_eq(slot.texture, SkillMechanicIcons.texture_for(skill.skill_id))
	window.size = original_size
