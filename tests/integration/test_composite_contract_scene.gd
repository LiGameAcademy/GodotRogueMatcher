extends GutTest

const MAIN: PackedScene = preload("res://main.tscn")
const Fixture: Script = preload("res://tests/support/composite_contract_fixture.gd")
var main: Node2D
var game: Node2D
var board: Board

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	UIManager.close_popup()
	main = MAIN.instantiate() as Node2D
	game = main.get_node("Game") as Node2D
	game.set("persist_preferences", false)
	game.set("record_runs", false)
	game.set("collect_telemetry", false)
	board = game.get_node("Board") as Board
	board.game_mode = GameModes.CLASSIC
	add_child_autofree(main)
	await board.initialized
	for piece: PieceState in board.rules.state.get_snapshot(): board.remove_piece(piece.coordinate)
	Fixture.populate(board.run)
	board.view.rebuild(board.rules.state.get_snapshot())
	board.can_selected = false

func after_each() -> void:
	UIManager.close_popup()
	get_tree().paused = false
	if is_instance_valid(main): main.queue_free()
	await wait_process_frames(3)

func _open(fail: bool, fast: bool, low: bool) -> PopupSkillChoice:
	game.call("_set_fast", fast, false)
	game.call("_set_low_effects", low, false)
	var first: ChoiceEffect = Fixture.first(board.run)
	var a: int = board.rules.state.get_piece_at(Vector2i(5, 2)).piece_id
	var q: int = board.rules.state.get_piece_at(Vector2i(3, 3)).piece_id
	var second: Fixture.FixedDye = Fixture.FixedDye.new()
	second.ids = [a, q]
	second.selected = 1
	var multiplier: DemolitionStatEffect = DemolitionStatEffect.new()
	multiplier.stat = DemolitionStatEffect.Stat.MULTIPLIER
	var effect: CompositeEffect = CompositeEffect.new()
	effect.fixed_target_policy = CompositeEffect.FixedTargetPolicy.SKIP_INVALID
	effect.children = [first, second, Fixture.FailAfterMatch.new() if fail else multiplier]
	var definition: SkillDefinition = Fixture.skill(effect)
	# Local fixture keeps a known identity for the real command gate; it never enters the catalog.
	definition.skill_id = &"composite_clear_dye"
	var generator: SkillOfferGenerator = SkillOfferGenerator.new()
	generator.set_catalog([definition])
	assert_not_null(generator.generate(board.run))
	BoardRunFlow.continue_run(board, board.run)
	await wait_process_frames(6)
	return UIManager.current_popup as PopupSkillChoice

func _success(fast: bool, low: bool) -> void:
	var popup: PopupSkillChoice = await _open(false, fast, low)
	assert_not_null(popup)
	if popup == null: return
	var old_callback: Callable = popup.skill_selected.get_connections()[0].callable
	var id: int = popup.offer.offer_id
	popup._select(0)
	popup.confirm_selection()
	await board.finish_presentation()
	await wait_process_frames(8)
	assert_eq(board.run.state.ledger.total, 50)
	assert_eq(board.run.state.rewards.consumed_count, 1)
	assert_eq(board.run.state.explosion.multiplier_level, 1)
	assert_true(board.can_selected)
	assert_false(get_tree().paused)
	var before: String = RunSnapshot.canonical(RunSnapshot.capture(board.run))
	old_callback.call(id, &"composite_clear_dye")
	assert_eq(RunSnapshot.canonical(RunSnapshot.capture(board.run)), before)

func test_t09_partial_result_normal_presentation_and_duplicate_confirmation() -> void:
	await _success(false, false)

func test_t09_partial_result_fast_and_low_effects_preserves_rules() -> void:
	await _success(true, true)

func test_t09_error_locks_input_retry_retires_run_and_old_callback() -> void:
	var popup: PopupSkillChoice = await _open(true, true, true)
	assert_not_null(popup)
	if popup == null: return
	var old_callback: Callable = popup.skill_selected.get_connections()[0].callable
	var id: int = popup.offer.offer_id
	var old_run: RunController = board.run
	popup._select(0)
	popup.confirm_selection()
	await wait_process_frames(6)
	assert_eq(old_run.state.phase, RunState.Phase.ERROR)
	assert_eq(old_run.state.ledger.total, 50)
	assert_eq(old_run.state.rewards.consumed_count, 0)
	assert_false(board.can_selected)
	assert_false(is_instance_valid(UIManager.current_popup))
	assert_false(get_tree().paused)
	game.call("_on_retry_requested")
	await board.initialized
	assert_true(old_run.is_retired())
	assert_true(old_run.abilities.flush_held_blasts().is_empty())
	assert_false(old_run.state.ability_events.data().active)
	var before: String = RunSnapshot.canonical(RunSnapshot.capture(board.run))
	old_callback.call(id, &"composite_clear_dye")
	assert_eq(RunSnapshot.canonical(RunSnapshot.capture(board.run)), before)
	assert_true(board.can_selected)
