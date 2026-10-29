extends GutTest
## Exercises preparation cost and a shipped sweep upgrade; no natural acquisition claims.

const F: Script = preload("res://tests/support/o3_fixed_fixture.gd")

func test_immediate_five_and_prepared_six_keep_real_refill_and_pressure() -> void:
	for seed_value: int in [23, 77]:
		var immediate: Dictionary = F.trace(seed_value, false)
		var prepared: Dictionary = F.trace(seed_value, true)
		assert_true(immediate.actions[0].accepted)
		assert_eq(immediate.final.score, 55)
		assert_eq(immediate.final.spawned, 0)
		assert_true(prepared.actions[0].accepted)
		assert_eq(prepared.actions[0].after.score, 0)
		assert_eq(prepared.actions[0].after.spawned, 3)
		assert_eq(prepared.actions[0].after.occupied, prepared.initial.occupied + 3)
		assert_eq(prepared.actions[0].after.next_refill, 4)
		assert_true(prepared.actions[1].accepted)
		assert_eq(prepared.actions[1].matches[0].score.N, "6")
		assert_eq(prepared.final.score, 86)
		assert_eq(prepared.final.valid_moves, 2)
		assert_eq(prepared.final.spawned, 3)
		assert_eq(prepared.final.occupied, 4)
		for action: Dictionary in prepared.actions: assert_eq(action.steps.back().kind, &"input")
		assert_eq(prepared.final.error, "")
		# Reconstruct the explicit initial state and re-execute encoded-equivalent commands.
		# This is deterministic fixture reproduction, not RuleReplay support for custom states.
		assert_eq(RunSnapshot.canonical(prepared), RunSnapshot.canonical(F.trace(seed_value, true)))
		assert_eq(F.write_evidence("preparation-%d" % seed_value, {"immediate": immediate, "prepared": prepared}), OK)
		var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(F.evidence_path("preparation-%d" % seed_value)))
		var reproduced: Dictionary = F.reproduce(disk.prepared)
		assert_eq(RunSnapshot.canonical(reproduced.final), RunSnapshot.canonical(prepared.final))
		for index: int in range(prepared.actions.size()):
			assert_eq(RunSnapshot.canonical(reproduced.actions[index].after), RunSnapshot.canonical(prepared.actions[index].after))
		print("O3_FP ", JSON.stringify({"seed": seed_value, "immediate": immediate.final.score,
			"prepared": prepared.final.score, "second_accepted": prepared.actions[1].accepted,
			"reason": prepared.actions[1].reason, "occupied": prepared.final.occupied}))

func test_preparation_can_close_the_only_landing_path() -> void:
	var immediate: Dictionary = F.trace(77, false, true)
	var prepared: Dictionary = F.trace(77, true, true)
	assert_true(immediate.actions[0].accepted)
	assert_true(prepared.actions[0].accepted)
	assert_false(prepared.actions[1].accepted)
	assert_true(prepared.actions[1].target_empty)
	assert_eq(prepared.actions[1].reason, "NO_PATH")
	assert_eq(prepared.final.score, 0)
	assert_eq(prepared.final.valid_moves, 1)
	assert_eq(prepared.final.error, "")
	assert_eq(F.write_evidence("blocked-path", {"immediate": immediate, "prepared": prepared}), OK)

func test_shipped_line_fixture_scores_same_targets_with_upgrade_and_replays() -> void:
	var reports: Array[Dictionary] = []
	for upgraded: bool in [false, true]:
		var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 77)
		run.initialize("fixture_line_score" if upgraded else "fixture_line")
		run.recorder = RunRecorder.new()
		run.recorder.metadata = {"collection_context": "fixture", "purpose": "O3 L1 score upgrade causality"}
		run.recorder.begin(run, "fixture", false)
		var before: Dictionary = F.observe(run)
		var command: ActivateLineCommand = ActivateLineCommand.new(run.state.run_id, 1, run.state.action_id)
		command.source = "fixture"
		command.piece_id = run.state.rules.state.get_piece_id(Vector2i.ZERO)
		var response: CommandResult = run.execute_command(command)
		assert_true(response.accepted, response.reason)
		F.settle(run)
		run.recorder.finish(run, "censored", "tool_limit")
		var name: String = "line-upgraded" if upgraded else "line-baseline"
		assert_eq(F.write_records(name, run.recorder.records), OK)
		var replay: RuleReplay = RuleReplay.new()
		assert_true(replay.replay_file(F.evidence_path(name, "jsonl")), replay.error)
		reports.append({"before": before, "after": F.observe(run), "record_file": name + ".jsonl",
			"replay_complete": replay.complete, "checked_records": replay.checked_records})
	assert_eq(reports[0].after.score, 14)
	assert_eq(reports[1].after.score, 18)
	assert_eq(reports[0].after.occupied, reports[1].after.occupied)
	assert_eq(reports[0].after.spawned, 3)
	var baseline_entry: Dictionary = reports[0].after.state.ledger[0]
	var upgraded_entry: Dictionary = reports[1].after.state.ledger[0]
	assert_eq(baseline_entry.reason, "line_clear")
	assert_eq(upgraded_entry.reason, "line_clear")
	assert_eq(baseline_entry.targets, upgraded_entry.targets)
	assert_eq(baseline_entry.N, "2")
	assert_eq(upgraded_entry.E, "4")
	assert_eq(F.write_evidence("line-upgrade", {"source": "fixture/automated", "reports": reports}), OK)
