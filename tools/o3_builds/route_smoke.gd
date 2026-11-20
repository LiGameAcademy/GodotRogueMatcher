class_name O3RouteSmoke
extends RefCounted

## Per-route bot smoke. Pre-installs engines via shipped choose commands, records facts.
## Synthetic reward offers are not a supported RuleReplay prefix; smoke does not require disk replay.
const STAGES: StageConfig = preload("res://gameplay/progression/stages/stage_config.tres")
const BOT_CONFIG: BotConfig = preload("res://tools/bot_testing/bot_config.tres")

static func skill(skill_id: StringName) -> SkillDefinition:
	for entry: SkillDefinition in SkillOfferGenerator.CATALOG:
		if entry.skill_id == skill_id: return entry
	return null

## Install through the shipped choose-skill command so smoke JSONL stays replayable.
static func install_command(run: RunController, skill_id: StringName) -> CommandResult:
	var definition: SkillDefinition = skill(skill_id)
	var rejected: CommandResult = CommandResult.new()
	rejected.accepted = false
	if definition == null:
		rejected.reason = "missing_skill"
		return rejected
	run.state.pending_rewards = 1
	run.enter_rewards()
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = run.state.rewards.next_offer_id
	run.state.rewards.next_offer_id += 1
	offer.reward_id = run.state.rewards.consumed_count + 1
	offer.choices = [definition]
	offer.targets[skill_id] = SkillRules.freeze_target(run.state, definition)
	run.state.rewards.active_offer = offer
	var command: ChooseSkillCommand = ChooseSkillCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
	command.source = "fixture"
	command.offer_id = offer.offer_id
	command.reward_id = offer.reward_id
	command.skill_id = skill_id
	return run.execute_command(command)

static func install_engines(run: RunController, route_id: StringName) -> Dictionary:
	var installed: Array[StringName] = []
	var route: Dictionary = O3BuildRoutes.routes()[route_id]
	for skill_id: StringName in route.engines:
		var response: CommandResult = install_command(run, skill_id)
		if not response.accepted:
			return {"ok": false, "error": "%s/%s: %s" % [route_id, skill_id, response.reason], "installed": installed}
		installed.append(skill_id)
		if run.state.phase == RunState.Phase.REWARDS: run.advance()
	return {"ok": true, "error": "", "installed": installed}

static func observe_matches(matches: Array[MatchResult], tallies: Dictionary) -> void:
	for match_result: MatchResult in matches:
		var cause: String = String(match_result.cause)
		tallies.causes[cause] = int(tallies.causes.get(cause, 0)) + 1
		tallies.max_generation = maxi(int(tallies.max_generation), match_result.generation)
		if match_result.cross_radius >= 0: tallies.cross_events = int(tallies.cross_events) + 1
		if match_result.generation >= 2 and cause == "explosion":
			tallies.explosion_descendants = int(tallies.explosion_descendants) + 1

static func play_one(route_id: StringName, seed_value: int, move_limit: int = 80, verify: bool = false) -> Dictionary:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), seed_value, STAGES)
	run.initialize()
	var recorder: RunRecorder = RunRecorder.new()
	run.recorder = recorder
	recorder.metadata = {"collection_context": "fixture", "purpose": "O3 route smoke", "route": String(route_id)}
	recorder.begin(run, "bot", false)
	var setup: Dictionary = install_engines(run, route_id)
	if not setup.ok:
		recorder.finish(run, "rule_error", setup.error)
		return {"source": "fixture/automated", "route": String(route_id), "seed": str(seed_value),
			"status": "rule_error", "reason": setup.error, "replay_error": "", "rule_error": setup.error,
			"causes": {}, "max_generation": 0, "cross_events": 0, "explosion_descendants": 0,
			"installed_engines": [], "score": 0, "handled": 0, "occupied": 0}
	var installed: Array[StringName] = setup.installed
	var installed_names: Array[String] = []
	for skill_id: StringName in installed: installed_names.append(String(skill_id))
	recorder.metadata["installed_engines"] = installed_names
	var strategy: GreedyBot = GreedyBot.new(BotRunner.strategy_seed_for(seed_value))
	strategy.config = BOT_CONFIG.duplicate(true) as BotConfig
	strategy.config.move_limit = move_limit
	strategy.version = "greedy-v1"
	var tallies: Dictionary = {"causes": {}, "max_generation": 0, "cross_events": 0, "explosion_descendants": 0}
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
			reason = String(run.state.end_reason)
			break
		if handled >= strategy.config.command_limit:
			reason = "command_limit"
			break
		if Time.get_ticks_msec() - started >= strategy.config.timeout_ms:
			reason = "timeout"
			break
		if run.state.phase == RunState.Phase.REWARDS and run.state.rewards.active_offer == null:
			run.advance()
			handled += 1
			continue
		if run.state.phase != RunState.Phase.INPUT and run.state.phase != RunState.Phase.REWARDS:
			run.advance()
			handled += 1
			continue
		if run.state.phase == RunState.Phase.INPUT and run.state.valid_moves + run.state.activations >= strategy.config.move_limit:
			break
		var command: RunCommand = strategy.choose(run)
		if command == null:
			reason = "no_legal_move" if run.state.phase == RunState.Phase.INPUT else "no_candidate"
			if run.state.phase != RunState.Phase.INPUT:
				status = "rule_error"
				run.report_error(reason)
			break
		var response: CommandResult = run.execute_command(command)
		handled += 1
		if not response.accepted:
			status = "rule_error"
			reason = response.reason
			run.report_error(reason)
			break
		if response.turn != null: observe_matches(response.turn.matches, tallies)
		if command is ChooseSkillCommand: run.advance()
	recorder.finish(run, status, reason)
	var replay_error: String = ""
	if verify:
		var replay: RuleReplay = RuleReplay.new()
		if not replay.replay(recorder.records): replay_error = replay.error
	return {"source": "fixture/automated", "route": String(route_id), "seed": str(seed_value),
		"rules_version": RunSnapshot.RULES_VERSION, "installed_engines": installed_names,
		"status": status, "reason": reason, "score": run.state.ledger.total, "handled": handled,
		"occupied": run.state.rules.state.get_piece_count(), "causes": tallies.causes,
		"max_generation": tallies.max_generation, "cross_events": tallies.cross_events,
		"explosion_descendants": tallies.explosion_descendants, "replay_error": replay_error,
		"rule_error": run.state.rule_error}

static func run_batch(per_route: int = 10, start_seed: int = 9000, move_limit: int = 80) -> Dictionary:
	var rows: Array[Dictionary] = []
	var failures: Array[Dictionary] = []
	for route_id: StringName in O3BuildRoutes.ORDER:
		for index: int in range(per_route):
			var report: Dictionary = play_one(route_id, start_seed + rows.size(), move_limit)
			rows.append(report)
			if report.status == "rule_error":
				failures.append({"route": report.route, "seed": report.seed, "status": report.status,
					"reason": report.reason})
	var by_route: Dictionary = {}
	for route_id: StringName in O3BuildRoutes.ORDER:
		var subset: Array[Dictionary] = []
		for row: Dictionary in rows:
			if row.route == String(route_id): subset.append(row)
		var cause_union: Dictionary = {}
		var synergy_games: int = 0
		for row: Dictionary in subset:
			for cause: String in row.causes:
				cause_union[cause] = int(cause_union.get(cause, 0)) + int(row.causes[cause])
			match String(route_id):
				"B2":
					if int(row.explosion_descendants) > 0: synergy_games += 1
				"L2":
					if int(row.cross_events) > 0: synergy_games += 1
				"M1", "M2":
					if row.causes.has("explosion") and row.causes.has("line_clear"): synergy_games += 1
				_:
					if not (row.causes as Dictionary).is_empty(): synergy_games += 1
		var rule_errors: int = 0
		for row: Dictionary in subset:
			if row.status == "rule_error": rule_errors += 1
		by_route[String(route_id)] = {"games": subset.size(), "synergy_games": synergy_games,
			"cause_totals": cause_union, "rule_errors": rule_errors}
	return {"source": "fixture/automated", "purpose": "O3 per-route smoke", "per_route": per_route,
		"start_seed": start_seed, "move_limit": move_limit, "rules_version": RunSnapshot.RULES_VERSION,
		"games": rows.size(), "failures": failures, "by_route": by_route, "rows": rows}
