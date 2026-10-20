extends GutTest

const MAIN: PackedScene = preload("res://main.tscn")
var main: Node2D
var board: Board

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	UIManager.close_popup()
	main = MAIN.instantiate() as Node2D
	main.get_node("Game").set("persist_preferences", false)
	add_child_autofree(main)
	board = main.get_node("Game/Board") as Board
	await board.initialized

func after_each() -> void:
	get_tree().paused = false
	UIManager.close_popup()
	await wait_process_frames(2)

func test_human_fast_scene_and_headless_command_have_same_state() -> void:
	await _compare_command(0.01)

func test_human_slow_scene_and_headless_command_have_same_state() -> void:
	await _compare_command(0.3)

func _compare_command(duration: float) -> void:
	var shadow: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), board.run.state.random.seed, board.run.state.stage.config)
	shadow.state.run_id = board.run.state.run_id
	shadow.initialize()
	var command: MovePieceCommand = RandomLegalBot.new(99).choose(shadow) as MovePieceCommand
	command.source = "human"
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), RunSnapshot.digest(RunSnapshot.capture(shadow)))
	assert_true(shadow.execute_command(command).accepted)
	while shadow.state.phase != RunState.Phase.INPUT and not shadow.state.is_game_over: shadow.advance()
	board.selected_piece = board.view.get_piece(command.piece_id)
	assert_true(await board.move_selected_piece(board.get_cell(command.target), duration))
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), RunSnapshot.digest(RunSnapshot.capture(shadow)))
	board.run.recorder.finish(board.run, "abandoned", "scene_test")
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay_file(board.run.recorder.path), replay.error)

func test_retry_preserves_earned_reward_state_in_old_record() -> void:
	var old: RunController = _bind_earned_run()
	await board.retry_game(BoardRules.new(BoardState.new(9, 9), 5))
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay(old.recorder.records), replay.error)
	assert_eq(old.recorder.records.back().status, "abandoned")

func test_fixture_restart_preserves_old_record() -> void:
	var old: RunController = _bind_earned_run()
	assert_true(board.load_explosion_demo())
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay(old.recorder.records), replay.error)

func _bind_earned_run() -> RunController:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 1000)
	run.initialize()
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "test", false)
	var bot: GreedyBot = GreedyBot.new(101000)
	for attempt: int in range(300):
		if run.state.rewards.consumed_count > 0 and run.state.phase == RunState.Phase.INPUT: break
		if run.state.phase in [RunState.Phase.INPUT, RunState.Phase.REWARDS]:
			var command: RunCommand = bot.choose(run)
			if command == null: break
			run.execute_command(command)
			if command is ChooseSkillCommand: run.advance()
		else: run.advance()
	assert_gt(run.state.rewards.consumed_count, 0)
	board.run.recorder.finish(board.run, "abandoned", "test_bind")
	board.run = run
	board.rules = run.state.rules
	GameManager.reset_game(run)
	board.view.rebuild(run.state.rules.state.get_snapshot())
	board.can_selected = true
	return run
