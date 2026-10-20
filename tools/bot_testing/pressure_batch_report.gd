class_name PressureBatchReport
extends RefCounted

var groups: Dictionary[String, Dictionary] = {}
var error: String = ""

func add(recorder: RunRecorder, projector: TelemetryProjector, replay_error: String) -> void:
	var header: Dictionary = recorder.records[0]
	var footer: Dictionary = recorder.records.back()
	var key: String = RunSnapshot.digest([header.config_hash, header.metadata.strategy, header.metadata.bot_config, header.metadata.get("commit_id")])
	if not groups.has(key):
		groups[key] = {"mode": header.config.mode_id, "config_hash": header.config_hash, "rules_version": header.rules_version, "strategy": header.metadata.strategy, "bot_config": header.metadata.bot_config, "commit_id": header.metadata.get("commit_id"), "runs": [], "stages": {}, "skills": {}, "q": [], "P": [], "carry": [], "errors": []}
		for skill: SkillDefinition in SkillOfferGenerator.CATALOG: _skill(groups[key], String(skill.skill_id))
	var group: Dictionary = groups[key]
	group.runs.append({"seed": header.seed, "run_id": header.run_id, "record": recorder.path, "status": footer.status, "reason": footer.reason, "actions": footer.actions, "final_digest": RunSnapshot.digest(footer.final)})
	if not replay_error.is_empty() or not recorder.error.is_empty() or projector == null or not projector.error.is_empty():
		group.errors.append({"run_id": header.run_id, "replay": replay_error, "record": recorder.error, "telemetry": "missing" if projector == null else projector.error})
		return
	var reached: Dictionary[int, bool] = {}
	var passed: Dictionary[int, int] = {}
	for event: Dictionary in projector.events:
		var data: Dictionary = event.payload
		var stage: Dictionary = data.get("stage_before", data.get("stage", {}))
		if event.event_name == "run_started": stage = data.initial_observation.stage
		if stage.get("enabled", false) and stage.has("stage_id"): reached[int(stage.stage_id)] = true
		if event.event_name == "action_resolved":
			group.q.append(int(data.q_frozen))
			group.P.append(float(data.P_before.P))
			for id: String in data.build_before:
				var skill: Dictionary = _skill(group, id)
				skill.action_exposure += 1
		if event.event_name == "stage_goal_completed":
			var id: int = int(data.result.stage_id)
			reached[id] = true
			passed[id] = int(data.result.used_actions)
			group.carry.append(int(data.result.carry_out))
		if event.event_name == "offer_generated":
			for id: String in data.choices: _skill(group, id).offered += 1
		if event.event_name == "skill_acquired": _skill(group, data.skill_id).selected += 1
		if event.event_name == "rule_fact":
			var score: Dictionary = data.get("score", {})
			var id: String = score.get("ability_id", "")
			if not id.is_empty():
				var skill: Dictionary = _skill(group, id)
				skill.attributed_score_events += 1
				if skill.first_effect == null: skill.first_effect = {"run_id": header.run_id, "event_id": event.event_id}
	for id: int in reached:
		var stage_key: String = str(id)
		if not group.stages.has(stage_key): group.stages[stage_key] = {"reached": 0, "completed": 0, "board_full_unmet": 0, "censored": 0, "used_actions": []}
		var row: Dictionary = group.stages[stage_key]
		row.reached += 1
		if passed.has(id):
			row.completed += 1
			row.used_actions.append(passed[id])
		elif footer.status == "completed" and footer.reason == "board_full": row.board_full_unmet += 1
		else: row.censored += 1

func _skill(group: Dictionary, id: String) -> Dictionary:
	if not group.skills.has(id): group.skills[id] = {"offered": 0, "selected": 0, "action_exposure": 0, "attributed_score_events": 0, "first_effect": null, "attempt_denominator": null, "missing_reason": "all_ability_attempts_not_recorded"}
	return group.skills[id]

func write(directory: String) -> bool:
	for group: Dictionary in groups.values():
		for row: Dictionary in group.stages.values():
			row["completion_rate_known"] = float(row.completed) / (row.completed + row.board_full_unmet) if row.completed + row.board_full_unmet > 0 else null
			row["actions_p50_p90"] = quantiles(row.used_actions)
		for name: String in ["q", "P", "carry"]: group[name + "_p50_p90"] = quantiles(group[name])
		for skill: Dictionary in group.skills.values():
			skill["coverage"] = "not_offered" if skill.offered == 0 else "not_selected" if skill.selected == 0 else "no_attributed_score_event" if skill.attributed_score_events == 0 else "observed_attributed_score"
	var file: FileAccess = FileAccess.open(directory.path_join("pressure_summary.json"), FileAccess.WRITE)
	if file == null:
		error = "cannot_write_pressure_report"
		return false
	file.store_string(JSON.stringify({"protocol": "pressure-batch-v1", "groups": groups, "limits": "tool limits are censored; bot observations do not measure human understanding", "first_effect_scope": "attributed score events only; non-score effects remain unmeasured"}, "\t"))
	file.flush()
	return file.get_error() == OK

static func quantiles(values: Array) -> Array:
	if values.is_empty(): return [null, null]
	var ordered: Array = values.duplicate()
	ordered.sort()
	return [ordered[int(floor(0.5 * (ordered.size() - 1)))], ordered[int(floor(0.9 * (ordered.size() - 1)))]]
