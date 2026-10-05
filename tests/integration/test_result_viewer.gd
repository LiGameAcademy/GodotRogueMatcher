extends GutTest

const VIEWER: PackedScene = preload("res://tools/bot_testing/result_viewer.tscn")

func test_result_viewing_speeds_preserve_snapshot_without_counting_score() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	run.initialize("fixture_f6")
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "fixture")
	var move: MovePieceCommand = MovePieceCommand.new(run.state.run_id, 1, 0)
	move.piece_id = run.state.rules.state.get_piece_id(Vector2i(5, 5))
	move.target = Vector2i(5, 4)
	run.execute_command(move)
	while run.state.phase != RunState.Phase.INPUT: run.advance()
	run.recorder.finish(run, "abandoned", "viewer_test")
	var global_before: String = RunSnapshot.digest(RunSnapshot.capture(GameManager.run))
	for speed: float in [1.0, 16.0]:
		var viewer: ResultViewer = VIEWER.instantiate() as ResultViewer
		add_child_autofree(viewer)
		assert_true(viewer.load_record(run.recorder.path), viewer.error)
		viewer.view.presentation_speed = speed
		while viewer.cursor < viewer.records.size(): await viewer.step()
		assert_eq(viewer.error, "")
		assert_eq(RunSnapshot.digest(viewer.current_state), RunSnapshot.digest(RunSnapshot.capture(run)))
		assert_eq(RunSnapshot.digest(RunSnapshot.capture(GameManager.run)), global_before)
	await wait_process_frames(2)

func test_result_watching_accepts_old_config_while_rule_replay_rejects_it() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	run.initialize()
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "test", false)
	run.recorder.finish(run, "abandoned", "viewer_test")
	var records: Array[Dictionary] = run.recorder.records.duplicate(true)
	records[0].rules_version = "old-build"
	var path: String = "user://old_result_view.jsonl"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	for record: Dictionary in records: file.store_line(RunSnapshot.canonical(record))
	file.close()
	var viewer: ResultViewer = VIEWER.instantiate() as ResultViewer
	add_child_autofree(viewer)
	assert_true(viewer.load_record(path))
	var replay: RuleReplay = RuleReplay.new()
	assert_false(replay.replay_file(path))
	assert_eq(replay.error, "record_version_mismatch")

func test_malformed_consumed_records_fail_without_stalling_viewer() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	run.initialize()
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "test", false)
	var bad_rows: Array[Dictionary] = [
		{"kind": "Offer", "offer": {"choices": 7}},
		{"kind": "RuleResult", "move": "bad", "after": RunSnapshot.capture(run)},
		{"kind": "RuleResult", "after": {"pieces": [], "instances": [7], "total": "0", "moves": "0", "consumed": "0"}},
		{"kind": "SkillAcquired", "created": [], "removed": ["bad"]}
	]
	var viewer: ResultViewer = VIEWER.instantiate() as ResultViewer
	add_child_autofree(viewer)
	for row: Dictionary in bad_rows:
		row.seq = "2"
		var path: String = "user://malformed_view.jsonl"
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		file.store_line(RunSnapshot.canonical(run.recorder.records[0]))
		file.store_line(RunSnapshot.canonical(row))
		file.close()
		assert_false(viewer.load_record(path))
		assert_false(viewer.busy)
		assert_false(viewer.error.is_empty())
	await wait_process_frames(2)
