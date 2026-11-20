class_name O3RouteExplore
extends RefCounted

## Natural engine-acquisition scan. No pre-install. Does not judge pass rates or fill quotas.
const STAGES: StageConfig = preload("res://gameplay/progression/stages/stage_config.tres")
const BOT_CONFIG: BotConfig = preload("res://tools/bot_testing/bot_config.tres")

static func engine_ids(route_id: StringName) -> Array[StringName]:
	var ids: Array[StringName] = []
	for skill_id: StringName in O3BuildRoutes.routes()[route_id].engines:
		ids.append(skill_id)
	return ids

static func acquisitions_in(records: Array[Dictionary], engines: Array[StringName]) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var seen: Dictionary = {}
	for record: Dictionary in records:
		if record.get("kind", "") != "SkillAcquired": continue
		var skill_id: StringName = StringName(str(record.get("skill_id", "")))
		if not engines.has(skill_id) or seen.has(skill_id): continue
		seen[skill_id] = true
		found.append({"skill_id": String(skill_id), "reward_id": str(record.get("reward_id", "")),
			"offer_id": str(record.get("offer_id", "")), "count_after": str(record.get("count_after", ""))})
	return found

static func play_one(route_id: StringName, seed_value: int, move_limit: int = 80) -> Dictionary:
	var engines: Array[StringName] = engine_ids(route_id)
	var strategy: GreedyBot = GreedyBot.new(BotRunner.strategy_seed_for(seed_value))
	strategy.config = BOT_CONFIG.duplicate(true) as BotConfig
	strategy.config.move_limit = move_limit
	var runner: BotRunner = BotRunner.new()
	runner.stage_config = STAGES
	var recorder: RunRecorder = runner.play(seed_value, BotRunner.strategy_seed_for(seed_value), strategy, false, false)
	var engine_names: Array[String] = []
	for skill_id: StringName in engines: engine_names.append(String(skill_id))
	if recorder == null:
		return {"source": "bot/natural", "route": String(route_id), "seed": str(seed_value),
			"status": "rule_error", "reason": runner.last_replay_error, "acquired": false,
			"acquisitions": [], "engines": engine_names, "rule_error": true}
	var footer: Dictionary = recorder.records.back() if not recorder.records.is_empty() else {}
	var hits: Array[Dictionary] = acquisitions_in(recorder.records, engines)
	return {"source": "bot/natural", "route": String(route_id), "seed": str(seed_value),
		"rules_version": RunSnapshot.RULES_VERSION, "engines": engine_names,
		"status": str(footer.get("status", "")), "reason": str(footer.get("reason", "")),
		"score": footer.get("score", ""), "moves": footer.get("moves", ""),
		"choices": footer.get("choices", ""), "acquired": not hits.is_empty(),
		"acquisitions": hits, "acquisition_count": hits.size(),
		"rule_error": str(footer.get("status", "")) == "rule_error"}

static func scan_route(route_id: StringName, target: int = 30, max_scan: int = 100, start_seed: int = 12000, move_limit: int = 80) -> Dictionary:
	var rows: Array[Dictionary] = []
	var acquired_rows: Array[Dictionary] = []
	var failures: Array[Dictionary] = []
	var seed_value: int = start_seed
	while rows.size() < max_scan and acquired_rows.size() < target:
		var report: Dictionary = play_one(route_id, seed_value, move_limit)
		rows.append(report)
		if report.rule_error or report.status == "rule_error":
			failures.append({"seed": report.seed, "status": report.status, "reason": report.reason})
		if report.acquired: acquired_rows.append(report)
		seed_value += 1
	var stop_reason: String = "target_reached" if acquired_rows.size() >= target else "scan_cap"
	if rows.size() >= max_scan and acquired_rows.size() < target: stop_reason = "scan_cap"
	return {"source": "bot/natural", "route": String(route_id), "target": target, "max_scan": max_scan,
		"start_seed": start_seed, "move_limit": move_limit, "scanned": rows.size(),
		"acquired_parents": acquired_rows.size(), "coverage_gap": acquired_rows.size() < target,
		"stop_reason": stop_reason, "failures": failures, "acquisition_rate":
			(float(acquired_rows.size()) / float(rows.size())) if rows.size() > 0 else 0.0,
		"rows": rows, "acquired_rows": acquired_rows}

static func run_batch(target: int = 30, max_scan: int = 100, start_seed: int = 12000, move_limit: int = 80, routes: Array[StringName] = []) -> Dictionary:
	var selected: Array[StringName] = routes if not routes.is_empty() else O3BuildRoutes.ORDER.duplicate()
	var by_route: Dictionary = {}
	var failures: Array[Dictionary] = []
	var seed_cursor: int = start_seed
	for route_id: StringName in selected:
		var report: Dictionary = scan_route(route_id, target, max_scan, seed_cursor, move_limit)
		by_route[String(route_id)] = {
			"scanned": report.scanned, "acquired_parents": report.acquired_parents,
			"coverage_gap": report.coverage_gap, "stop_reason": report.stop_reason,
			"acquisition_rate": report.acquisition_rate, "failures": report.failures,
			"rows": report.rows
		}
		for failure: Dictionary in report.failures:
			failure["route"] = String(route_id)
			failures.append(failure)
		seed_cursor += max_scan
	var route_names: Array[String] = []
	for route_id: StringName in selected: route_names.append(String(route_id))
	return {"source": "bot/natural", "purpose": "O3 natural engine acquisition explore",
		"target": target, "max_scan": max_scan, "start_seed": start_seed, "move_limit": move_limit,
		"rules_version": RunSnapshot.RULES_VERSION, "routes": route_names,
		"failures": failures, "by_route": by_route}
