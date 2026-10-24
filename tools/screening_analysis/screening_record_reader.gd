class_name ScreeningRecordReader
extends RefCounted

var error: String = ""
var warnings: Array[String] = []

func read(path: String) -> Dictionary:
	error = ""
	warnings.clear()
	var replay: RuleReplay = RuleReplay.new()
	var records: Array[Dictionary] = replay.read_file(path)
	if not replay.error.is_empty(): return _fail(replay.error)
	if records.is_empty(): return _fail("empty_record")
	var header: Dictionary = records[0]
	if not header.get("config") is Dictionary: return _fail("missing_config")
	if header.config.get("prototype_profile") not in [String(RunController.SCREENING_PROFILE), String(RunController.SCREENING_FIXED_PROFILE)]: return _fail("not_screening_record")
	if not replay.replay(records): return _fail(replay.error)
	var footer: Dictionary = records.back()
	if not header.get("metadata", {}) is Dictionary or not header.get("source") is String or not header.get("build") is String: return _fail("invalid_metadata")
	var metadata: Dictionary = header.get("metadata", {})
	var fixed: bool = header.config.prototype_profile == String(RunController.SCREENING_FIXED_PROFILE)
	var key: String = ScreeningDeck.key_of(header.initialization) if fixed else "baseline"
	if not fixed and header.config.has("prototype_match_templates"):
		if header.config.prototype_match_templates.size() != 1: return _fail("not_single_shape")
		key = str(header.config.prototype_match_templates[0].shape_id)
	if key not in ScreeningDeck.CONFIGS: return _fail("unknown_configuration")
	var expected_templates: Array[Dictionary] = []
	var settings: ScreeningConfig = ScreeningDeck.config(key)
	if settings.template != null:
		expected_templates.append({"shape_id": String(settings.template.shape_id), "offsets": settings.template.offsets})
	if RunSnapshot.canonical(header.config.get("prototype_match_templates", [])) != RunSnapshot.canonical(RunSnapshot.normalize(expected_templates)): return _fail("configuration_geometry_mismatch")
	if header.config.columns != "9" or header.config.rows != "9" or header.config.match_count != "5" or header.config.mode_id != "classic_endless": return _fail("unsupported_screening_rules")
	var task: String = ScreeningDeck.task_of(header.initialization) if fixed else "free"
	if task not in ScreeningDeck.TASKS: return _fail("unknown_task")
	var config_id: String = "screening-%s-v1" % key
	if metadata.get("configuration") is Dictionary and metadata.configuration.get("config_id") != config_id: return _fail("configuration_identity_mismatch")
	if metadata.has("config_id") and metadata.config_id != config_id: return _fail("configuration_identity_mismatch")
	var sidecar: Dictionary = {}
	var side_path: String = path.get_basename() + "-screening.json"
	if FileAccess.file_exists(side_path):
		var file: FileAccess = FileAccess.open(side_path, FileAccess.READ)
		if file == null: return _fail("sidecar_unreadable")
		var parser: JSON = JSON.new()
		if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary: return _fail("sidecar_invalid_json")
		sidecar = parser.data
		if sidecar.get("run_id") != header.run_id or sidecar.get("config_id") != config_id or sidecar.get("task") != task: return _fail("sidecar_identity_mismatch")
		if sidecar.get("record_error") != "": return _fail("sidecar_record_error")
		if not _integer(sidecar.get("actions")) or int(sidecar.actions) != int(footer.actions): return _fail("sidecar_actions_mismatch")
		if not _integer(sidecar.get("elapsed_ms")): return _fail("sidecar_elapsed_invalid")
		var expected: String = "screening_" + str(sidecar.get("reason", ""))
		if footer.status == "completed":
			if sidecar.get("reason") != "natural_end": return _fail("sidecar_reason_mismatch")
		elif footer.reason != expected: return _fail("sidecar_reason_mismatch")
	var elapsed: Variant = sidecar.get("elapsed_ms")
	var source_kind: String = "unknown"
	if header.source == "screening_playground": source_kind = "human_unobserved"
	elif str(header.source).begins_with("bot") or str(header.source).contains("automated_fixture"): source_kind = "automated"
	else: warnings.append("unclassified_source")
	var window: Variant = false
	if fixed and footer.reason == "screening_fixed_complete": window = int(footer.actions) == 1
	elif not fixed and footer.reason == "screening_action_limit": window = int(footer.actions) == 15
	elif not fixed and footer.reason == "screening_time_limit": window = null if elapsed == null else int(elapsed) >= 480000
	elif not fixed and footer.status == "completed": window = true
	if window != true: warnings.append("window_incomplete_or_unverified")
	var metrics: Dictionary = _metrics(records)
	var result: Dictionary = {"run_id": header.run_id, "record": path, "sha256": FileAccess.get_sha256(path), "config_id": config_id, "config_hash": header.config_hash, "build": header.build, "seed": header.seed, "task": task, "source_kind": source_kind, "status": footer.status, "reason": footer.reason, "window_complete": window, "elapsed_ms": elapsed, "actions": int(footer.actions), "score": int(footer.score), "metrics": metrics, "warnings": warnings.duplicate(), "human": blank_human()}
	result["sidecar_sha256"] = FileAccess.get_sha256(side_path) if not sidecar.is_empty() else null
	return result

static func blank_human() -> Dictionary:
	return {"participant": null, "role": null, "round": null, "explanation_count": null, "prediction_correct": null, "planned_layout": null, "willing_again": null, "use_case": null, "interference": null, "notes": null}

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0 and float(value) == floorf(float(value))

func _fail(reason: String) -> Dictionary:
	error = reason
	return {}

static func _metrics(records: Array[Dictionary]) -> Dictionary:
	var removed: Dictionary[String, bool] = {}
	var born: Dictionary[String, bool] = {}
	var events: Dictionary[String, Dictionary] = {}
	var birth_sources: Dictionary = {}
	for record: Dictionary in records:
		if record.kind == "SkillAcquired": _pieces(record.get("removed", []), removed)
		if record.kind != "RuleResult": continue
		_pieces(record.get("removed", []), removed)
		_events(record.get("events", []), events, removed)
		for birth: Dictionary in record.get("births", []):
			if not born.has(str(birth.piece.id)):
				var source: String = str(birth.source)
				birth_sources[source] = int(birth_sources.get(source, 0)) + 1
			born[str(birth.piece.id)] = true
			_events(birth.get("events", []), events, removed)
	var by_source: Dictionary = {}
	var match_events: int = 0
	var shape_events: Dictionary = {}
	for event: Dictionary in events.values():
		var source: String = str(event.match_source) if not str(event.match_source).is_empty() else str(event.cause)
		if not by_source.has(source): by_source[source] = {"events": 0, "removed": 0, "score": 0}
		by_source[source].events += 1
		by_source[source].removed += event.removed.size()
		by_source[source].score += int(event.score.final_score)
		if event.cause == "match":
			match_events += 1
			var ids: Dictionary[String, bool] = {}
			for hit: Dictionary in event.get("match_hits", []): ids[str(hit.shape_id)] = true
			if ids.is_empty(): ids["line"] = true
			for id: String in ids: shape_events[id] = int(shape_events.get(id, 0)) + 1
	var initial: Dictionary = records.front().initial
	var final: Dictionary = records.back().final
	return {"match_events": match_events, "shape_event_counts": shape_events, "removed_unique_entities": removed.size(), "births_in_window": born.size(), "births_by_source": birth_sources, "net_empty_cells": initial.pieces.size() - final.pieces.size(), "by_source": by_source}

static func _pieces(values: Array, destination: Dictionary[String, bool]) -> void:
	for piece: Dictionary in values: destination[str(piece.id)] = true

static func _events(values: Array, events: Dictionary[String, Dictionary], removed: Dictionary[String, bool]) -> void:
	for event: Dictionary in values:
		_pieces(event.removed, removed)
		if int(event.score.event_id) > 0: events[str(event.score.event_id)] = event
