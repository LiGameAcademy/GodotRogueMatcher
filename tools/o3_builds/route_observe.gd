class_name O3RouteObserve
extends RefCounted

## Post-acquisition observation windows on natural bot parents. Facts only; missing = null.
const STAGES: StageConfig = preload("res://gameplay/progression/stages/stage_config.tres")
const BOT_CONFIG: BotConfig = preload("res://tools/bot_testing/bot_config.tres")
const PLAYER_TYPES: Array[String] = ["move", "detonate", "activate_line"]

static func growth_ids(route_id: StringName) -> Array[StringName]:
	var ids: Array[StringName] = []
	for skill_id: StringName in O3BuildRoutes.routes()[route_id].growth:
		ids.append(skill_id)
	return ids

static func effective_causes(route_id: StringName) -> Array[String]:
	match String(route_id):
		"L1", "L2":
			return ["line_clear"]
		"B1", "B2":
			return ["explosion"]
		_:
			return ["explosion", "line_clear"]

static func _event_effective(event: Dictionary, causes: Array[String]) -> bool:
	if not causes.has(str(event.get("cause", ""))): return false
	return (event.get("removed", []) as Array).size() > 0

static func _events_effective(events: Array, causes: Array[String]) -> bool:
	for event: Variant in events:
		if event is Dictionary and _event_effective(event, causes): return true
	return false

static func analyze(records: Array[Dictionary], route_id: StringName) -> Dictionary:
	var engines: Array[StringName] = O3RouteExplore.engine_ids(route_id)
	var growth: Array[StringName] = growth_ids(route_id)
	var causes: Array[String] = effective_causes(route_id)
	var acquired: bool = false
	var acquire_skill: String = ""
	var actions_after: int = 0
	var startup_wait = null
	var startup_complete: bool = false
	var sustain_wait = null
	var sustain_complete: bool = false
	var offers_after: int = 0
	var upgrade_offered = null
	var upgrade_taken = null
	var upgrade_complete: bool = false
	var offered_growth: Array[String] = []
	var taken_growth: Array[String] = []
	var truncated: String = ""
	var acquire_command_id: String = ""
	var awaiting_acquire_result: bool = false
	var footer: Dictionary = {}
	for record: Dictionary in records:
		var kind: String = str(record.get("kind", ""))
		if kind == "Footer":
			footer = record
			truncated = str(record.get("reason", ""))
		if not acquired:
			if kind == "SkillAcquired":
				var skill_id: StringName = StringName(str(record.get("skill_id", "")))
				if engines.has(skill_id):
					acquired = true
					acquire_skill = String(skill_id)
					acquire_command_id = str(record.get("command_id", ""))
					awaiting_acquire_result = true
					upgrade_offered = false
					upgrade_taken = false
			continue
		if awaiting_acquire_result and kind == "RuleResult":
			awaiting_acquire_result = false
			if str(record.get("command_id", "")) == acquire_command_id \
					and _events_effective(record.get("events", []) as Array, causes):
				startup_wait = 0
				startup_complete = true
			continue
		if kind == "CommandAttempt" and record.get("accepted", false):
			var command: Dictionary = record.get("command", {})
			var command_type: String = str(command.get("type", ""))
			if PLAYER_TYPES.has(command_type):
				actions_after += 1
		if kind == "RuleResult":
			var events: Array = record.get("events", []) as Array
			if _events_effective(events, causes):
				if startup_wait == null:
					startup_wait = actions_after
					startup_complete = true
				elif sustain_wait == null:
					var since_startup: int = actions_after - int(startup_wait)
					sustain_wait = since_startup
					sustain_complete = since_startup <= 10
		if kind == "Offer" and offers_after < 3:
			var choices: Array = record.get("offer", {}).get("choices", []) as Array
			var hit: bool = false
			for choice: Variant in choices:
				var choice_id: StringName = StringName(str(choice))
				if growth.has(choice_id):
					hit = true
					if not offered_growth.has(String(choice_id)): offered_growth.append(String(choice_id))
			if hit: upgrade_offered = true
			offers_after += 1
			if offers_after >= 3: upgrade_complete = true
		if kind == "SkillAcquired":
			var skill_id: StringName = StringName(str(record.get("skill_id", "")))
			if growth.has(skill_id) and offers_after <= 3:
				upgrade_taken = true
				if not taken_growth.has(String(skill_id)): taken_growth.append(String(skill_id))
		if startup_complete and actions_after - int(startup_wait) >= 10 and sustain_wait == null:
			sustain_complete = true
	if not acquired:
		return {"acquired": false, "startup": null, "sustain": null, "upgrade": null, "truncated": truncated}
	if startup_wait == null:
		startup_complete = actions_after >= 8
	if sustain_wait == null and startup_wait != null:
		sustain_complete = actions_after - int(startup_wait) >= 10
	if offers_after >= 3: upgrade_complete = true
	var startup: Dictionary = {
		"wait_actions": startup_wait,
		"within_4": null if startup_wait == null and not startup_complete else (startup_wait != null and int(startup_wait) <= 4),
		"within_8": null if startup_wait == null and not startup_complete else (startup_wait != null and int(startup_wait) <= 8),
		"window_complete": startup_complete or startup_wait != null,
		"actions_observed": actions_after,
	}
	var sustain: Dictionary = {
		"second_wait_actions": sustain_wait,
		"within_10": null if sustain_wait == null and not sustain_complete else (sustain_wait != null and int(sustain_wait) <= 10),
		"window_complete": sustain_complete or sustain_wait != null,
		"requires_startup": startup_wait != null,
	}
	var upgrade: Dictionary = {
		"offers_observed": offers_after,
		"offered": upgrade_offered if acquired else null,
		"taken": upgrade_taken if acquired else null,
		"offered_ids": offered_growth,
		"taken_ids": taken_growth,
		"window_complete": upgrade_complete,
	}
	return {"acquired": true, "acquire_skill": acquire_skill, "startup": startup, "sustain": sustain,
		"upgrade": upgrade, "synergy": null, "truncated": truncated,
		"status": str(footer.get("status", "")), "reason": str(footer.get("reason", "")),
		"telemetry_note": "all_ability_attempts=false; opportunity rate not claimed"}

static func play_one(route_id: StringName, seed_value: int, move_limit: int = 120) -> Dictionary:
	var strategy: GreedyBot = GreedyBot.new(BotRunner.strategy_seed_for(seed_value))
	strategy.config = BOT_CONFIG.duplicate(true) as BotConfig
	strategy.config.move_limit = move_limit
	var runner: BotRunner = BotRunner.new()
	runner.stage_config = STAGES
	var recorder: RunRecorder = runner.play(seed_value, BotRunner.strategy_seed_for(seed_value), strategy, false, false)
	if recorder == null:
		return {"source": "bot/natural", "route": String(route_id), "seed": str(seed_value),
			"acquired": false, "rule_error": true, "reason": runner.last_replay_error}
	var windows: Dictionary = analyze(recorder.records, route_id)
	windows["source"] = "bot/natural"
	windows["route"] = String(route_id)
	windows["seed"] = str(seed_value)
	windows["rules_version"] = RunSnapshot.RULES_VERSION
	windows["move_limit"] = move_limit
	windows["rule_error"] = str(windows.get("status", "")) == "rule_error"
	return windows

static func scan_route(route_id: StringName, target: int = 30, max_scan: int = 100, start_seed: int = 13000, move_limit: int = 120) -> Dictionary:
	var rows: Array[Dictionary] = []
	var acquired_rows: Array[Dictionary] = []
	var failures: Array[Dictionary] = []
	var seed_value: int = start_seed
	while rows.size() < max_scan and acquired_rows.size() < target:
		var report: Dictionary = play_one(route_id, seed_value, move_limit)
		rows.append(report)
		if report.get("rule_error", false):
			failures.append({"seed": report.seed, "reason": report.get("reason", "")})
		if report.get("acquired", false): acquired_rows.append(report)
		seed_value += 1
	var stop_reason: String = "target_reached" if acquired_rows.size() >= target else "scan_cap"
	var startup_4: int = 0
	var startup_8: int = 0
	var startup_denom: int = 0
	var sustain_hit: int = 0
	var sustain_denom: int = 0
	var upgrade_offer: int = 0
	var upgrade_take: int = 0
	var upgrade_denom: int = 0
	for row: Dictionary in acquired_rows:
		var startup: Dictionary = row.get("startup", {})
		if startup.get("window_complete", false):
			startup_denom += 1
			if startup.get("within_4", false): startup_4 += 1
			if startup.get("within_8", false): startup_8 += 1
		var sustain: Dictionary = row.get("sustain", {})
		if sustain.get("requires_startup", false) and sustain.get("window_complete", false):
			sustain_denom += 1
			if sustain.get("within_10", false): sustain_hit += 1
		var upgrade: Dictionary = row.get("upgrade", {})
		if upgrade.get("window_complete", false):
			upgrade_denom += 1
			if upgrade.get("offered", false): upgrade_offer += 1
			if upgrade.get("taken", false): upgrade_take += 1
	return {"source": "bot/natural", "route": String(route_id), "target": target, "max_scan": max_scan,
		"start_seed": start_seed, "move_limit": move_limit, "scanned": rows.size(),
		"acquired_parents": acquired_rows.size(), "coverage_gap": acquired_rows.size() < target,
		"stop_reason": stop_reason, "failures": failures,
		"windows": {
			"startup_within_4": {"hits": startup_4, "denom": startup_denom},
			"startup_within_8": {"hits": startup_8, "denom": startup_denom},
			"sustain_within_10": {"hits": sustain_hit, "denom": sustain_denom},
			"upgrade_offered_in_3": {"hits": upgrade_offer, "denom": upgrade_denom},
			"upgrade_taken_in_3": {"hits": upgrade_take, "denom": upgrade_denom},
		},
		"rows": rows, "acquired_rows": acquired_rows}

static func run_batch(target: int = 30, max_scan: int = 100, start_seed: int = 13000, move_limit: int = 120) -> Dictionary:
	var by_route: Dictionary = {}
	var failures: Array[Dictionary] = []
	var seed_cursor: int = start_seed
	for route_id: StringName in O3BuildRoutes.ORDER:
		var report: Dictionary = scan_route(route_id, target, max_scan, seed_cursor, move_limit)
		by_route[String(route_id)] = {
			"scanned": report.scanned, "acquired_parents": report.acquired_parents,
			"coverage_gap": report.coverage_gap, "stop_reason": report.stop_reason,
			"windows": report.windows, "failures": report.failures,
		}
		for failure: Dictionary in report.failures:
			failure["route"] = String(route_id)
			failures.append(failure)
		seed_cursor += max_scan
	return {"source": "bot/natural", "purpose": "O3 post-acquisition observation windows",
		"target": target, "max_scan": max_scan, "start_seed": start_seed, "move_limit": move_limit,
		"rules_version": RunSnapshot.RULES_VERSION, "failures": failures, "by_route": by_route,
		"pass_line": null, "note": "trial windows only; not formal acceptance; synergy left null pending opportunity telemetry"}
