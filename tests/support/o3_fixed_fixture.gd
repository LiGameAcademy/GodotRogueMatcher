extends RefCounted
## Builds bounded O3 technical fixtures and drives shipped commands without replacing rules.
## Custom F-P state is reconstructed explicitly; it is not a supported RuleReplay initialization.

const STAGES: StageConfig = preload("res://gameplay/progression/stages/stage_config.tres")

static func preparation(seed_value: int, blocked: bool = false) -> RunController:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), seed_value, STAGES)
	run.initialization = "o3_custom_preparation"
	run.state.run_id = "fixture-o3-%d-%s" % [seed_value, str(blocked)]
	for x: int in range(1, 5): run.state.rules.place_piece(Vector2i(x, 4), 0)
	run.state.rules.place_piece(Vector2i(5, 6), 0)
	run.state.rules.place_piece(Vector2i(6, 6), 0)
	run.state.rules.place_piece(Vector2i(0, 0), 1)
	if blocked:
		run.state.rules.place_piece(Vector2i(5, 3), 1)
		run.state.rules.place_piece(Vector2i(5, 5), 2)
	# Explicit hypothetical pressure boundary, not a fabricated three-action history.
	run.state.stage.used_actions = 3
	run.state.explosion.upgrades[&"precision_reward"] = 1
	run.state.explosion.upgrades[&"longline_reward"] = 1
	run.start_turn()
	return run

static func observe(run: RunController) -> Dictionary:
	return {"state": RunSnapshot.capture(run), "occupied": run.state.rules.state.get_piece_count(),
		"score": run.state.ledger.total, "used_actions": run.state.stage.used_actions,
		"next_refill": run.state.next_refill_count(), "valid_moves": run.state.valid_moves,
		"spawned": run.state.spawn_history.size(), "error": run.state.rule_error}

static func move(run: RunController, source: Vector2i, target: Vector2i) -> Dictionary:
	var command: MovePieceCommand = MovePieceCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
	command.source = "fixture"
	command.piece_id = run.state.rules.state.get_piece_id(source)
	command.target = target
	var before: Dictionary = observe(run)
	var target_empty: bool = run.state.rules.state.get_piece_id(target) == 0
	var response: CommandResult = run.execute_command(command)
	var result: Dictionary = {"command": CommandCodec.encode(command), "before": before,
		"target_empty": target_empty,
		"accepted": response.accepted, "reason": response.reason, "steps": []}
	if response.turn != null and response.turn.move != null:
		result["path"] = RunSnapshot.normalize(response.turn.move.path)
	if response.turn != null: result["matches"] = RunRecorder.matches(response.turn.matches)
	if response.accepted: result["steps"] = settle(run)
	result["after"] = observe(run)
	return result

static func settle(run: RunController) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	for index: int in range(8):
		var step: RunStepResult = run.advance()
		var births: Array[Dictionary] = []
		for spawn: SpawnResult in step.spawns:
			births.append({"id": spawn.piece.piece_id if spawn.piece != null else 0,
				"coordinate": spawn.piece.coordinate if spawn.piece != null else Vector2i(-1, -1)})
		steps.append({"kind": step.kind, "births": births, "after": observe(run)})
		if step.kind in [&"input", &"offer", &"error", &"finished"]: break
	if steps.size() == 8 and steps.back().kind not in [&"input", &"offer", &"error", &"finished"]:
		steps.append({"kind": "fixture_step_limit", "after": observe(run)})
	return steps

static func trace(seed_value: int, prepare: bool, blocked: bool = false) -> Dictionary:
	var run: RunController = preparation(seed_value, blocked)
	var result: Dictionary = {"source": "fixture/automated", "seed": str(seed_value),
		"blocked": blocked, "prepare": prepare, "rules_version": RunSnapshot.RULES_VERSION,
		"config": RunSnapshot.config(run), "initial": observe(run), "actions": []}
	if prepare:
		result.actions.append(move(run, Vector2i(6, 6), Vector2i(6, 4)))
	result.actions.append(move(run, Vector2i(5, 6), Vector2i(5, 4)))
	result["final"] = observe(run)
	return result

## Replay only fixture commands against the explicit reconstructed board, never a saved game.
static func reproduce(trace_data: Dictionary) -> Dictionary:
	var run: RunController = preparation(String(trace_data.seed).to_int(), trace_data.blocked)
	var results: Array[Dictionary] = []
	for action: Dictionary in trace_data.actions:
		var command: RunCommand = CommandCodec.decode(action.command)
		if command == null: return {"error": "fixture_command_decode"}
		var response: CommandResult = run.execute_command(command)
		if response.accepted: settle(run)
		results.append({"accepted": response.accepted, "reason": response.reason, "after": observe(run)})
	return {"actions": results, "final": observe(run)}

static func evidence_path(name: String, extension: String = "json") -> String:
	var directory: String = OS.get_environment("O3_EVIDENCE_DIR")
	if directory.is_empty(): directory = "res://.godot/o3-fixed"
	return directory.path_join(name + "." + extension)

static func write_records(name: String, records: Array[Dictionary]) -> Error:
	var error: Error = DirAccess.make_dir_recursive_absolute(evidence_path(name).get_base_dir())
	if error != OK: return error
	var file: FileAccess = FileAccess.open(evidence_path(name, "jsonl"), FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	for record: Dictionary in records: file.store_line(JSON.stringify(record, "", true))
	file.flush()
	return file.get_error()

static func write_evidence(name: String, value: Dictionary) -> Error:
	var directory: String = evidence_path(name).get_base_dir()
	var error: Error = DirAccess.make_dir_recursive_absolute(directory)
	if error != OK: return error
	var file: FileAccess = FileAccess.open(evidence_path(name), FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(RunSnapshot.normalize(value), "\t", true) + "\n")
	file.flush()
	return file.get_error()
