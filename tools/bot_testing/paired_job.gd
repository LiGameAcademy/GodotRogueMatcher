extends Node

func _ready() -> void:
	_run.call_deferred()

## 从指定真实日志的首个安全三选一，或显式标记的F6诊断盘面生成窗口。
func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("Usage: -- paired <record.jsonl|fixture> <fresh output> [--seed=1] [--strategy=greedy|random]")
		get_tree().quit(2)
		return
	var seed_value: int = 1
	var strategy: String = "greedy"
	for arg: String in args:
		if arg.begins_with("--seed="): seed_value = arg.trim_prefix("--seed=").to_int()
		elif arg.begins_with("--strategy="): strategy = arg.trim_prefix("--strategy=")
	var prefix: Array[Dictionary] = []
	if args[1] == "fixture": prefix = fixture_prefix(seed_value)
	else:
		var replay: RuleReplay = RuleReplay.new()
		var records: Array[Dictionary] = replay.read_file(args[1])
		if not replay.error.is_empty() or not replay.replay(records):
			push_error(replay.error)
			get_tree().quit(1)
			return
		for row: Dictionary in records:
			prefix.append(row)
			if row.kind == "Checkpoint" and row.state.get("offer", {}).get("choices", []).size() >= 2: break
	var validator: RuleReplay = RuleReplay.new()
	if prefix.is_empty() or not validator.restore_prefix(prefix) or validator.run.state.rewards.active_offer == null:
		push_error("No legal safe offer: " + validator.error)
		get_tree().quit(1)
		return
	var choices: Array[SkillDefinition] = validator.run.state.rewards.active_offer.choices
	for horizon: int in [20, 50]:
		for index: int in range(choices.size()):
			var pair: PairedWindow = PairedWindow.new()
			var control: StringName = choices[(index + 1) % choices.size()].skill_id
			if not pair.compare(prefix, choices[index].skill_id, control, horizon, strategy, seed_value + 100000) or not pair.write(args[2]):
				push_error(pair.error)
				get_tree().quit(1)
				return
			print(JSON.stringify(pair.report))
	get_tree().quit(0)

static func fixture_prefix(seed_value: int) -> Array[Dictionary]:
	var config: StageConfig = preload("res://gameplay/progression/stages/stage_config.tres").duplicate(true) as StageConfig
	config.targets = [1, 150, 200, 300, 400, 550, 750, 1000]
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), seed_value, config)
	run.initialize("fixture_f6")
	run.recorder = RunRecorder.new()
	run.recorder.metadata = {"strategy": "greedy-v1", "bot_config": RunSnapshot.resource_fields(preload("res://tools/bot_testing/bot_config.tres")), "collection_context": "fixture", "fixture_purpose": "rare skill diagnosis; not normal pool availability"}
	run.recorder.begin(run, "fixture", false)
	var piece_id: int = run.state.rules.state.get_piece_id(Vector2i(5, 5))
	var command: MovePieceCommand = MovePieceCommand.new(run.state.run_id, 1, 0)
	command.piece_id = piece_id
	command.target = Vector2i(5, 4)
	command.source = "bot"
	if not run.execute_command(command).accepted: return []
	for index: int in range(30):
		if run.state.phase == RunState.Phase.REWARDS and run.state.rewards.active_offer != null: return run.recorder.records.duplicate(true)
		if run.state.is_game_over or not run.state.rule_error.is_empty(): return []
		run.advance()
	return []
