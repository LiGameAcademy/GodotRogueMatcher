class_name BotRunner
extends RefCounted

var last_replay_error: String = ""
var telemetry_factory: TelemetryFactory
var last_telemetry: TelemetryProjector

func play(seed_value: int, strategy_seed: int, strategy: RuleBot, save: bool = true, verify: bool = true) -> RunRecorder:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), seed_value)
	run.initialize()
	var recorder: RunRecorder = RunRecorder.new()
	run.recorder = recorder
	strategy.random.seed = strategy_seed
	if strategy is GreedyBot: strategy.version = "greedy-v1"
	recorder.metadata = {"strategy": strategy.version, "strategy_seed": str(strategy_seed), "bot_config": RunSnapshot.resource_fields(strategy.config)}
	if telemetry_factory != null: last_telemetry = telemetry_factory.attach(recorder, run.state.run_id)
	recorder.begin(run, "bot", save)
	if last_telemetry != null: last_telemetry.set_interval("busy")
	var started: int = Time.get_ticks_msec()
	var handled: int = 0
	var status: String = "censored"
	var reason: String = "move_limit"
	while true:
		if not run.state.rule_error.is_empty():
			status = "rule_error"
			reason = run.state.rule_error
			break
		if run.state.is_game_over:
			status = "completed"
			reason = "board_full"
			break
		if handled >= strategy.config.command_limit:
			reason = "command_limit"
			break
		if Time.get_ticks_msec() - started >= strategy.config.timeout_ms:
			reason = "timeout"
			break
		if run.state.phase != RunState.Phase.INPUT and run.state.phase != RunState.Phase.REWARDS:
			run.advance()
			handled += 1
			continue
		if run.state.phase == RunState.Phase.INPUT and run.state.valid_moves >= strategy.config.move_limit: break
		var compute_started: int = Time.get_ticks_msec()
		var command: RunCommand = strategy.choose(run)
		recorder.times.robot_compute += Time.get_ticks_msec() - compute_started
		if command == null:
			reason = "no_legal_move" if run.state.phase == RunState.Phase.INPUT else "no_candidate"
			if run.state.phase != RunState.Phase.INPUT:
				status = "rule_error"
				run.report_error(reason)
			break
		var result: CommandResult = run.execute_command(command)
		handled += 1
		if not result.accepted:
			status = "rule_error"
			reason = result.reason
			run.report_error(reason)
			break
		# 技能应用后留在REWARDS；advance决定下一候选或剩余回合，不跳过。
		if command is ChooseSkillCommand: run.advance()
	recorder.finish(run, status, reason)
	if verify:
		var replay: RuleReplay = RuleReplay.new()
		last_replay_error = "" if replay.replay(recorder.records) else replay.error
	return recorder
