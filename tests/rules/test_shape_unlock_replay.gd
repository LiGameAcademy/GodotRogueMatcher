extends GutTest

const FIXTURE: Script = preload("res://tests/support/shape_unlock_fixture.gd")

func test_unlock_recovery_disk_replay_and_safe_prefix_keep_budget_and_acquisition() -> void:
	var run: RunController = FIXTURE.run(true)
	FIXTURE.record(run, true)
	assert_true(FIXTURE.choose(run).accepted)
	var prefix: Array[Dictionary] = run.recorder.records.duplicate(true)
	var restore: RuleReplay = RuleReplay.new()
	assert_true(restore.restore_prefix(prefix), restore.error)
	assert_true(restore.run.state.rules.shape_unlocks.contains(&"l"))
	assert_true(restore.run.state.rules.shape_unlocks.recovery_pending)
	assert_false(restore.run.state.rules.shape_unlocks.recovery_attempted)
	var expected: RunStepResult = run.advance()
	var actual: RunStepResult = restore.run.advance()
	assert_eq(actual.kind, &"recovery")
	assert_eq(actual.spawns.size(), expected.spawns.size())
	assert_eq(RunSnapshot.canonical(RunSnapshot.capture(restore.run)), RunSnapshot.canonical(RunSnapshot.capture(run)))
	run.advance()
	run.recorder.finish(run, "censored", "unlock_recovery_acceptance")
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay_file(run.recorder.path), replay.error)
	assert_eq(replay.checked_records, run.recorder.records.size())
	assert_eq(replay.run.state.rewards.acquired.get(&"fixture_unlock_l"), 1)
	assert_eq(replay.run.state.rules.shape_unlocks.recovery_batch_id, 1)
	var found: bool = false
	for row: Dictionary in run.recorder.records:
		if row.get("stage") == "recovery":
			found = true
			assert_eq(row.births.size(), 3)
			assert_eq(row.births[0].source, "empty_recovery")
			assert_eq(row.births[0].batch_id, "1")
	assert_true(found)

func test_shape_state_and_profile_tampering_are_rejected_and_v41_is_explicitly_old() -> void:
	var run: RunController = FIXTURE.run()
	FIXTURE.record(run)
	assert_true(FIXTURE.choose(run).accepted)
	run.advance()
	run.recorder.finish(run, "censored", "fixture")
	var replay: RuleReplay = RuleReplay.new()
	var changed: Array[Dictionary] = run.recorder.records.duplicate(true)
	changed[0].config.prototype_profile = "arbitrary_script_path"
	assert_false(replay.replay(changed))
	assert_eq(replay.error, "invalid_prototype_profile")
	changed = run.recorder.records.duplicate(true)
	changed[0].rules_version = "run-commands-v41-followup-strength"
	assert_false(replay.replay(changed))
	assert_eq(replay.error, "record_version_mismatch")
	changed = run.recorder.records.duplicate(true)
	for row: Dictionary in changed:
		if row.kind == "Checkpoint" and not row.state.shape_unlocks.enabled.is_empty():
			row.state.shape_unlocks.enabled.clear()
			break
	assert_false(replay.replay(changed))
	assert_true(replay.error.contains("seq="))
