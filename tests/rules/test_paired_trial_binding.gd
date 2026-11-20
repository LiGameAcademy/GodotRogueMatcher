extends GutTest

## Synthetic trial parents exercise proven paired ancestry, never calibration observations.
func _prefix(a: String = "0.5") -> Array[Dictionary]:
	var options: OfferTrialOptions = OfferTrialOptions.from_args(PackedStringArray(["--offer-a=" + a, "--offer-d=0.25", "--experiment=synthetic_parent", "--variant=trial"]))
	var stage: StageConfig = preload("res://gameplay/progression/stages/stage_config.tres").duplicate(true) as StageConfig
	stage.targets = [1, 150, 200, 300, 400, 550, 750, 1000]
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 23, stage, &"", options.config)
	run.initialize("fixture_f6")
	run.recorder = RunRecorder.new()
	run.recorder.metadata = options.metadata()
	run.recorder.metadata["synthetic"] = true
	run.recorder.metadata["commit_id"] = "synthetic-parent"
	run.recorder.begin(run, "bot", false)
	var command: MovePieceCommand = MovePieceCommand.new(run.state.run_id, 1, 0)
	command.piece_id = run.state.rules.state.get_piece_id(Vector2i(5, 5))
	command.target = Vector2i(5, 4)
	assert_true(run.execute_command(command).accepted)
	for index: int in range(30):
		if run.state.rewards.active_offer != null: return run.recorder.records.duplicate(true)
		run.advance()
	return []

func _pair(prefix: Array[Dictionary], horizon: int = 20) -> PairedWindow:
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.restore_prefix(prefix), replay.error)
	var choices: Array[SkillDefinition] = replay.run.state.rewards.active_offer.choices
	var pair: PairedWindow = PairedWindow.new()
	assert_true(pair.compare(prefix, choices[0].skill_id, choices[1].skill_id, horizon, "random", 77, 0, 60000, "synthetic-execution"), pair.error)
	return pair

func test_all_grid_parents_bind_h20_h50_without_mutation_or_counting_new_parents() -> void:
	for a: String in ["0.0", "0.25", "0.5"]:
		var prefix: Array[Dictionary] = _prefix(a)
		var before: String = JSON.stringify(prefix, "", true, true)
		for horizon: int in [20, 50]:
			var pair: PairedWindow = _pair(prefix, horizon)
			assert_eq(pair.branches.size(), 2)
			for branch: RunController in pair.branches:
				var header: Dictionary = branch.recorder.records[0]
				assert_eq(header.source, "fixture")
				assert_eq(header.metadata.collection_context, "paired_window")
				assert_eq(header.metadata.parent_run_id, prefix[0].run_id)
				assert_eq(header.metadata.parent_commit_id, "synthetic-parent")
				assert_eq(header.metadata.commit_id, "synthetic-execution")
				assert_eq(header.config_hash, prefix[0].config_hash)
				assert_eq(branch.offer_configuration().related_gain, a.to_float())
				var replay: RuleReplay = RuleReplay.new()
				assert_true(replay.replay(branch.recorder.records), replay.error)
			assert_false(pair.report.known)
			assert_null(pair.report.delta_score)
		assert_eq(JSON.stringify(prefix, "", true, true), before)

func test_claimed_fixture_identity_cannot_replace_parent_replay_and_legal_offer_proof() -> void:
	var pair: PairedWindow = _pair(_prefix())
	var records: Array[Dictionary] = pair.branches[0].recorder.records
	for field: String in ["missing", "source", "parent", "prefix", "hash", "trial", "reward", "candidate", "history", "choice", "other_config", "parent_commit"]:
		var changed: Array[Dictionary] = records.duplicate(true)
		var header: Dictionary = changed[0]
		var proof: Dictionary = header.metadata.paired_trial
		match field:
			"missing": header.metadata.erase("paired_trial")
			"source": proof.parent_header.source = "fixture"
			"parent": header.metadata.parent_run_id = "another-run"
			"prefix": proof.prefix_records = "02"
			"hash": proof.parent_header.config_hash = "wrong"
			"trial": header.metadata.offer_trial.related_gain = 0.0
			"reward": proof.reward_id = "999"
			"candidate": proof.target = "not_a_candidate"
			"history": changed[1].hash = "corrupt-parent-checkpoint"
			"choice": changed[int(proof.prefix_records)].command.skill_id = proof.control
			"other_config": header.config.offer.maximum_utility_picks = "2"
			"parent_commit": header.metadata.parent_commit_id = "another-parent"
		var replay: RuleReplay = RuleReplay.new()
		assert_false(replay.replay(changed), field)

func test_unbound_trial_fixture_and_human_still_reject() -> void:
	for source: String in ["fixture", "human"]:
		var changed: Array[Dictionary] = _prefix()
		changed[0].source = source
		var replay: RuleReplay = RuleReplay.new()
		assert_false(replay.restore_prefix(changed))
		assert_eq(replay.error, "invalid_offer_trial_binding")
