class_name ScreeningAnnotations
extends RefCounted

var errors: Array[String] = []

func apply(document: Dictionary, runs: Array[Dictionary]) -> Array[Dictionary]:
	errors.clear()
	for run: Dictionary in runs: run.human = ScreeningRecordReader.blank_human()
	var decisions: Array[Dictionary] = []
	if document.is_empty(): return decisions
	if document.get("schema") != "screening-observations-v1" or not document.get("observations") is Array or not document.get("decisions") is Array:
		errors.append("invalid_observations_document")
		return decisions
	for field: String in document:
		if field not in ["schema", "observations", "decisions"]:
			errors.append("unknown_observations_field:" + field)
			return decisions
	var by_id: Dictionary[String, Dictionary] = {}
	for run: Dictionary in runs: by_id[run.run_id] = run
	var seen: Dictionary[String, bool] = {}
	for value: Variant in document.observations:
		if not value is Dictionary or not value.get("run_id") is String:
			errors.append("invalid_observation")
			continue
		var row: Dictionary = value
		var id: String = row.run_id
		if not by_id.has(id) or seen.has(id):
			if by_id.has(id): by_id[id].human = ScreeningRecordReader.blank_human()
			errors.append("unknown_or_duplicate_observation:" + id)
			continue
		seen[id] = true
		var human: Dictionary = ScreeningRecordReader.blank_human()
		var valid: bool = true
		for key: String in row:
			if key != "run_id" and not human.has(key): valid = false
		for key: String in human:
			var item: Variant = row.get(key)
			if item == null: continue
			if key in ["prediction_correct", "planned_layout", "willing_again"]:
				if not item is bool: valid = false
			elif key == "explanation_count":
				if not ScreeningRecordReader._integer(item) or float(item) > 100: valid = false
			elif not item is String or item.strip_edges().is_empty(): valid = false
			human[key] = item
		if human.role != null and human.role not in ["author", "new_player"]: valid = false
		if human.round != null and human.round not in ["initial", "retest"]: valid = false
		var observed: bool = human.values().any(func(v: Variant) -> bool: return v != null)
		if observed and (human.participant == null or human.role == null or human.round == null): valid = false
		if observed and by_id[id].source_kind != "human_unobserved": valid = false
		if not valid:
			errors.append("invalid_human_annotation:" + id)
			continue
		by_id[id].human = human
	var decision_keys: Dictionary[String, bool] = {}
	for value: Variant in document.decisions:
		if not value is Dictionary:
			errors.append("invalid_decision")
			continue
		var row: Dictionary = value
		var config: Variant = row.get("config_id")
		if not config is String or config not in ScreeningDeck.CONFIGS.map(func(k: String) -> String: return "screening-%s-v1" % k):
			errors.append("invalid_decision_configuration")
			continue
		if decision_keys.has(config):
			decisions = decisions.filter(func(d: Dictionary) -> bool: return d.config_id != config)
			errors.append("duplicate_decision:" + config)
			continue
		decision_keys[config] = true
		var fields_valid: bool = true
		for field: String in row:
			if field not in ["config_id", "config_hash", "build", "decision", "reason", "author_confirmed", "evidence_run_ids"]: fields_valid = false
		if not fields_valid:
			errors.append("invalid_decision:" + config)
			continue
		var decision: Variant = row.get("decision")
		if decision == null:
			if row.get("reason") != null or row.get("author_confirmed") != null or row.get("evidence_run_ids") != null or row.get("config_hash") != null or row.get("build") != null: errors.append("incomplete_decision:" + config)
			continue
		var valid: bool = row.get("config_hash") is String and not str(row.config_hash).is_empty()
		valid = valid and row.get("build") is String and not str(row.build).is_empty()
		valid = valid and decision in ["retain", "adjust", "disable", "insufficient"]
		valid = valid and row.get("reason") is String and not str(row.reason).strip_edges().is_empty()
		valid = valid and row.get("author_confirmed") is bool and row.get("evidence_run_ids") is Array
		var human_evidence: bool = false
		if valid:
			for id: Variant in row.evidence_run_ids:
				if not id is String or not by_id.has(id):
					valid = false
					continue
				var evidence: Dictionary = by_id[id]
				if evidence.config_id != config or evidence.config_hash != row.config_hash or evidence.build != row.build: valid = false
				if evidence.human.participant != null: human_evidence = true
			if decision != "insufficient" and (row.evidence_run_ids.is_empty() or not human_evidence): valid = false
		if not valid:
			errors.append("invalid_decision:" + config)
			continue
		decisions.append(row.duplicate(true))
	return decisions

static func template(runs: Array[Dictionary]) -> Dictionary:
	var observations: Array[Dictionary] = []
	for run: Dictionary in runs:
		if run.source_kind != "human_unobserved": continue
		var row: Dictionary = ScreeningRecordReader.blank_human()
		row["run_id"] = run.run_id
		observations.append(row)
	var decisions: Array[Dictionary] = []
	for key: String in ScreeningDeck.CONFIGS:
		decisions.append({"config_id": "screening-%s-v1" % key, "config_hash": null, "build": null, "decision": null, "reason": null, "author_confirmed": null, "evidence_run_ids": null})
	return {"schema": "screening-observations-v1", "observations": observations, "decisions": decisions}

static func accuracy(runs: Array[Dictionary]) -> Array[Dictionary]:
	var groups: Dictionary[String, Array] = {}
	for run: Dictionary in runs:
		if run.human.participant == null or run.task == "free" or run.window_complete != true: continue
		var key: String = JSON.stringify([run.human.participant, run.human.role, run.human.round, run.config_id, run.config_hash, run.build, run.get("seed")])
		if not groups.has(key): groups[key] = []
		groups[key].append(run)
	var result: Array[Dictionary] = []
	for key: String in groups:
		var rows: Array = groups[key]
		var tasks: Dictionary[String, bool] = {}
		var correct: int = 0
		var observed: int = 0
		var explained_once: bool = true
		var duplicate: bool = false
		for row: Dictionary in rows:
			if tasks.has(row.task): duplicate = true
			tasks[row.task] = true
			if row.human.prediction_correct is bool:
				observed += 1
				if row.human.prediction_correct: correct += 1
			if row.human.explanation_count != 1: explained_once = false
		var ready: bool = tasks.size() == 4 and not duplicate and observed == 4 and explained_once
		result.append({"participant": rows[0].human.participant, "role": rows[0].human.role, "round": rows[0].human.round, "config_id": rows[0].config_id, "config_hash": rows[0].config_hash, "build": rows[0].build, "seed": rows[0].get("seed"), "annotated_trials": rows.size(), "prediction_observed": observed, "prediction_correct": correct if observed > 0 else null, "once_explained_three_of_four": correct >= 3 if ready else null, "duplicate_task": duplicate})
	return result
