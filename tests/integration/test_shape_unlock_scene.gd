extends GutTest

const MAIN: PackedScene = preload("res://main.tscn")
const FIXTURE: Script = preload("res://tests/support/shape_unlock_fixture.gd")
var main: Node2D
var game: Node2D
var board: Board
var restart_on_spawn: bool = false
var retired_run: RunController

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
	board.run.retire()
	var active: RunController = FIXTURE.run(true)
	board.run = active
	board.rules = active.state.rules
	game.set("board_rules", board.rules)
	GameManager.reset_game(active)
	board.view.rebuild(board.rules.state.get_snapshot())
	board.can_selected = false
	board.director.step_requested.connect(_observe_step)

func after_each() -> void:
	restart_on_spawn = false
	UIManager.close_popup()
	get_tree().paused = false
	if is_instance_valid(main): main.queue_free()
	await wait_process_frames(3)

func _choose(fast: bool, low: bool) -> void:
	game.call("_set_fast", fast, false)
	game.call("_set_low_effects", low, false)
	board.resume_run(board.run)
	await wait_process_frames(6)
	var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	assert_not_null(popup)
	if popup == null: return
	for index: int in range(popup.offer.choices.size()):
		if popup.offer.choices[index].skill_id != &"fixture_unlock_l": continue
		popup._select(index)
		popup.confirm_selection()
		return
	fail_test("L fixture must appear in the real popup")

func _success(fast: bool, low: bool) -> void:
	var run: RunController = board.run
	await _choose(fast, low)
	assert_true(await wait_until(func() -> bool: return board.can_selected or not run.state.rule_error.is_empty(), 6.0))
	assert_eq(run.state.rule_error, "")
	assert_true(board.can_selected)
	assert_eq(run.state.ledger.total, 50)
	assert_eq(run.state.spawn_history.size(), 3)
	assert_eq(run.state.rules.shape_unlocks.recovery_batch_id, 1)
	assert_eq(run.state.rewards.consumed_count, 1)
	assert_eq(run.state.valid_moves, 0)
	assert_eq(board.view._pieces.size(), run.state.rules.state.get_piece_count())

func test_normal_real_popup_unlock_and_recovery() -> void:
	await _success(false, false)

func test_fast_real_popup_unlock_and_recovery() -> void:
	await _success(true, false)

func test_low_effects_real_popup_unlock_and_recovery() -> void:
	await _success(false, true)

func test_fast_low_effects_real_popup_unlock_and_recovery() -> void:
	await _success(true, true)

func test_retry_during_recovery_discards_old_run_identity_and_callbacks() -> void:
	restart_on_spawn = true
	await _choose(true, true)
	assert_true(await wait_until(func() -> bool: return retired_run != null and board.run != retired_run and board.can_selected, 6.0))
	assert_true(retired_run.is_retired())
	assert_false(board.run.state.rules.shape_unlocks.contains(&"l"))
	assert_eq(board.run.state.rules.shape_unlocks.recovery_batch_id, 0)
	assert_eq(board.run.state.rewards.consumed_count, 0)
	var before: String = RunSnapshot.canonical(RunSnapshot.capture(board.run))
	assert_eq(retired_run.advance().kind, &"closed")
	await wait_process_frames(6)
	assert_eq(RunSnapshot.canonical(RunSnapshot.capture(board.run)), before)

func _observe_step(step: PresentationStep, _ticket: int, _epoch: int) -> void:
	if not restart_on_spawn or step.kind != PresentationStep.Kind.SPAWN: return
	restart_on_spawn = false
	retired_run = board.run
	board.retry_game(BoardRules.new(BoardState.new(9, 9), 5))
