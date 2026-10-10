class_name PairedWindow
extends RefCounted

const PROTOCOL: String = "legal-choice-window-v1"
var error: String = ""
var branches: Array[RunController] = []
var report: Dictionary = {}

## A/B消费同一真实奖励的不同合法候选；不是删除技能的伪反事实。
func compare(prefix: Array[Dictionary], target: StringName, control: StringName, horizon: int, strategy_name: String = "greedy", strategy_seed: int = 1, command_limit: int = 3000, timeout_ms: int = 60000) -> bool:
	error = ""
	branches.clear()
	report = {}
	if horizon not in [20, 50] or strategy_name not in ["random", "greedy"] or command_limit < 0 or timeout_ms < 0: return _fail("invalid_window_parameters")
	var validation: RuleReplay = RuleReplay.new()
	if not validation.restore_prefix(prefix): return _fail(validation.error)
	var original: RunController = validation.run
	if original.state.phase != RunState.Phase.REWARDS or original.state.rewards.active_offer == null: return _fail("missing_legal_offer")
	var offer: SkillOffer = original.state.rewards.active_offer
	if target == control or not offer.targets.has(target) or not offer.targets.has(control): return _fail("illegal_comparator")
	var before: Dictionary = RunSnapshot.capture(original)
	var parent_id: String = prefix[0].run_id
	var pair_id: String = RunSnapshot.digest([PROTOCOL, parent_id, prefix.size(), target, control, horizon, strategy_name, strategy_seed, command_limit, timeout_ms]).left(24)
	var results: Array[Dictionary] = []
	for variant: String in ["treatment", "control"]:
		var frozen: Array[Dictionary] = prefix.duplicate(true)
		var id: String = parent_id + "-" + pair_id + "-" + variant
		frozen[0].run_id = id
		frozen[0].source = "fixture"
		var metadata: Dictionary = frozen[0].get("metadata", {}).duplicate(true)
		var strategy_version: String = "greedy-v1" if strategy_name == "greedy" else "random-legal-v1"
		metadata.merge({"experiment_id": PROTOCOL, "variant_id": variant, "parent_run_id": parent_id, "strategy": strategy_version + "+hold-target-v1", "strategy_seed": str(strategy_seed), "bot_config": RunSnapshot.resource_fields(preload("res://tools/bot_testing/bot_config.tres")), "window_command_limit": str(command_limit), "window_timeout_ms": str(timeout_ms)}, true)
		metadata.bot_config["window_policy"] = PROTOCOL
		metadata.bot_config["window_command_limit"] = str(command_limit)
		metadata.bot_config["window_timeout_ms"] = str(timeout_ms)
		frozen[0].metadata = metadata
		for row: Dictionary in frozen:
			if row.kind == "CommandAttempt": row.command.run_id = id
		var replay: RuleReplay = RuleReplay.new()
		if not replay.restore_prefix(frozen): return _fail(replay.error)
		var run: RunController = replay.run
		branches.append(run)
		var bot: RuleBot = GreedyBot.new(strategy_seed) if strategy_name == "greedy" else RandomLegalBot.new(strategy_seed)
		bot.config = bot.config.duplicate(true) as BotConfig
		# 从应用技能之前计量，包含即时得分/空间收益；两边独立策略RNG。
		var choice: ChooseSkillCommand = bot.skill_command(run, target if variant == "treatment" else control)
		var accepted: CommandResult = run.execute_command(choice)
		if not accepted.accepted: return _fail("illegal_intervention:" + accepted.reason)
		var result: Dictionary = _continue(run, bot, target, horizon, before, command_limit, timeout_ms)
		results.append(result)
		if result.status == "rule_error": return _fail(result.reason)
	var known: bool = results[0].known and results[1].known
	report = {"protocol": PROTOCOL, "pair_id": pair_id, "parent_run_id": parent_id, "skill_id": String(target), "control_skill_id": String(control), "level_before": offer.targets[target].level_before, "level": offer.targets[target].level_after, "H": horizon, "strategy_seed": str(strategy_seed), "start_digest": RunSnapshot.digest(before), "config_hash": prefix[0].config_hash, "known": known, "delta_score": results[0].score_delta - results[1].score_delta if known else null, "delta_space": results[0].space_delta - results[1].space_delta if known else null, "missing_reason": "" if known else "externally_censored_window", "observed_prefix_delta_score": results[0].score_delta - results[1].score_delta, "observed_prefix_delta_space": results[0].space_delta - results[1].space_delta, "branches": results, "estimand": "choice versus named alternative, including opportunity cost; not isolated skill value"}
	report["target_trigger_count"] = null
	report["target_trigger_missing_reason"] = "all_ability_attempts_not_recorded; zero score is not proof of no trigger"
	return true

func _continue(run: RunController, bot: RuleBot, held_skill: StringName, horizon: int, before: Dictionary, command_limit: int, timeout_ms: int) -> Dictionary:
	var start_actions: int = _actions(run)
	var started: int = Time.get_ticks_msec()
	var handled: int = 0
	var reason: String = "horizon_reached"
	var status: String = "censored"
	var known: bool = false
	while true:
		if not run.state.rule_error.is_empty():
			status = "rule_error"
			reason = run.state.rule_error
			break
		if run.state.is_game_over:
			status = "completed"
			reason = String(run.state.end_reason)
			known = true
			break
		var safe: bool = run.state.phase == RunState.Phase.INPUT or (run.state.phase == RunState.Phase.REWARDS and run.state.rewards.active_offer != null)
		if safe and run.continuation in [&"idle", &"after_spawn"] and _actions(run) - start_actions >= horizon:
			known = true
			break
		if handled >= command_limit or Time.get_ticks_msec() - started >= timeout_ms:
			reason = "command_limit" if handled >= command_limit else "timeout"
			break
		if not safe:
			run.advance()
			handled += 1
			continue
		var command: RunCommand = bot.choose(run)
		# 保持干预等级差：两边均不再选目标技能，不删除引擎或依赖。
		if command is ChooseSkillCommand and (command as ChooseSkillCommand).skill_id == held_skill:
			command = null
			for candidate: SkillDefinition in run.state.rewards.active_offer.choices:
				if candidate.skill_id != held_skill:
					command = bot.skill_command(run, candidate.skill_id)
					break
		if command == null:
			reason = "no_legal_policy_action"
			break
		var result: CommandResult = run.execute_command(command)
		handled += 1
		if not result.accepted:
			run.report_error(result.reason)
			continue
		if command is ChooseSkillCommand: run.advance()
	var final: Dictionary = RunSnapshot.capture(run)
	run.recorder.finish(run, status, reason)
	return {"run_id": run.state.run_id, "known": known, "status": status, "reason": reason, "actual_actions": _actions(run) - start_actions, "score_delta": int(final.total) - int(before.total), "space_delta": before.pieces.size() - final.pieces.size(), "final_score": final.total, "final_occupied": final.pieces.size(), "final_digest": RunSnapshot.digest(final), "strategy_rng_end": RunSnapshot.random_data(bot.random)}

## 保存完整规则前缀+分支，必须从磁盘再回放；测量事件仅写一次。
func write(directory: String) -> bool:
	if report.is_empty() or branches.size() != 2: return _fail("missing_pair")
	if DirAccess.make_dir_recursive_absolute(directory) != OK: return _fail("cannot_create_pair_directory")
	for index: int in range(branches.size()):
		var run: RunController = branches[index]
		var path: String = directory.path_join(run.state.run_id + ".jsonl")
		if FileAccess.file_exists(path): return _fail("pair_file_already_exists")
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if file == null: return _fail("cannot_write_pair_record")
		for row: Dictionary in run.recorder.records: file.store_line(JSON.stringify(row))
		file.flush()
		if file.get_error() != OK: return _fail("pair_record_write_failed")
		file.close()
		var replay: RuleReplay = RuleReplay.new()
		if not replay.replay_file(path): return _fail(replay.error)
		report.branches[index]["record_path"] = path
		var projector: TelemetryProjector = TelemetryProjector.new(LocalJsonlSink.new(run.state.run_id, directory.path_join("telemetry")), "pair-" + report.pair_id)
		for row: Dictionary in run.recorder.records:
			if row.kind == "Footer" and index == 0: projector.paired_window_resolved(report)
			projector.observe_record(row)
			if projector.needs_flush: projector.flush_pending()
		if not projector.error.is_empty(): return _fail(projector.error)
	var output: FileAccess = FileAccess.open(directory.path_join(report.pair_id + ".pair.json"), FileAccess.WRITE)
	if output == null: return _fail("cannot_write_pair_report")
	output.store_string(JSON.stringify(RunSnapshot.normalize(report), "\t"))
	output.flush()
	return output.get_error() == OK

func _actions(run: RunController) -> int:
	return run.state.valid_moves + run.state.activations

func _fail(reason: String) -> bool:
	error = reason
	return false
