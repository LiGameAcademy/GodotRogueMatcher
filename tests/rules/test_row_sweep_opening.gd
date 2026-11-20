extends GutTest

const SNAPSHOT: Script = preload("res://services/run_checkpoint/run_state_snapshot.gd")
const PROGRESS: Script = preload("res://services/run_checkpoint/opening_progress.gd")
const STAGES: StageConfig = preload("res://gameplay/progression/stages/stage_config.tres")

func _run(seed_value: int = 23) -> RunController:
	return RunController.new(BoardRules.new(BoardState.new(9, 9), 5), seed_value, STAGES)

func test_opening_keeps_reward_sequence_and_restores_without_regranting() -> void:
	var run: RunController = _run()
	var initial: RunStepResult = run.initialize("normal", &"row_sweep")
	assert_eq(run.state.rule_error, "")
	assert_eq(initial.spawns.size(), RunController.CONFIG.initial_piece_count + 1)
	assert_true(run.state.line_clear.row_unlocked)
	assert_eq(run.state.rewards.consumed_count, 0)
	assert_eq(run.state.rewards.next_offer_id, 1)
	var frozen: Dictionary = SNAPSHOT.freeze(run)
	assert_true(frozen.ok, frozen.reason)
	if not frozen.ok: return
	var restored: Dictionary = SNAPSHOT.decode(frozen.payload, SNAPSHOT.manifest(run))
	assert_true(restored.ok, restored.reason)
	if not restored.ok: return
	var cold: RunController = restored.run
	assert_eq(cold.opening_id, &"row_sweep")
	assert_eq(cold.state.rules.state.get_snapshot().size(), run.state.rules.state.get_snapshot().size())
	assert_eq(cold.state.random_streams.data(), run.state.random_streams.data())

func test_production_header_recreates_row_sweep_with_same_seed() -> void:
	var run: RunController = _run()
	run.initialize("normal", &"row_sweep")
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "human", false)
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.restore_prefix(run.recorder.records))

func test_only_normal_termination_after_a_pass_qualifies() -> void:
	var run: RunController = _run()
	run.initialize()
	run.finish_game()
	assert_false(PROGRESS.eligible(run))
	run.state.stage.index = 1
	assert_true(PROGRESS.eligible(run))
	run.report_error("test_error")
	assert_false(PROGRESS.eligible(run))

func test_desktop_progress_survives_fresh_load_and_recovers_backup() -> void:
	var directory: String = "user://opening-test-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var progress: PROGRESS = PROGRESS.new()
	assert_eq(await progress.load_progress(directory), "")
	assert_false(progress.unlocked)
	assert_eq(await progress.grant(), "")
	assert_eq(await progress.grant(), "")
	var path: String = directory.path_join("opening_progress.json")
	var files: CheckpointFiles = CheckpointFiles.new()
	assert_eq(files.write_text(path, "broken"), OK)
	var reopened: PROGRESS = PROGRESS.new()
	assert_eq(await reopened.load_progress(directory), "")
	assert_true(reopened.unlocked)
	files.remove(path)
	files.remove(path + ".bak")
	DirAccess.remove_absolute(directory)

func test_full_profile_clear_removes_checkpoint_and_all_opening_copies() -> void:
	var directory: String = "user://opening-clear-test-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var run: RunController = _run()
	run.initialize("normal", &"row_sweep")
	var progress: PROGRESS = PROGRESS.new()
	assert_eq(await progress.load_progress(directory), "")
	assert_eq(await progress.grant(), "")
	var saved: Dictionary = await SNAPSHOT.save(CheckpointStore.new(directory), run)
	assert_true(saved.ok, saved.reason)
	assert_true(FileAccess.file_exists(directory.path_join("opening_progress.json.bak")))
	# Model clearing the isolated desktop profile after the game has closed.
	for name: String in DirAccess.get_files_at(directory):
		assert_eq(DirAccess.remove_absolute(directory.path_join(name)), OK)
	assert_eq(DirAccess.remove_absolute(directory), OK)
	var reopened: PROGRESS = PROGRESS.new()
	assert_eq(await reopened.load_progress(directory), "")
	assert_false(reopened.unlocked)
	var checkpoint: Dictionary = CheckpointStore.new(directory).inspect_latest()
	assert_false(checkpoint.ok)
	assert_eq(checkpoint.reason, "no_valid_checkpoint:missing")
	var new_run: RunController = _run()
	new_run.initialize()
	assert_eq(new_run.opening_id, &"standard")
	assert_false(new_run.state.line_clear.row_unlocked)
