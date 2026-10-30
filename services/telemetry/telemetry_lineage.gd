class_name TelemetryLineage
extends RefCounted

## Resolves explicit observation segment ancestry. Never chooses a longest/latest ambiguous leaf.
## Raw events are retained separately; normalized v2 rows are an analysis view, not rewritten logs.
const COMPATIBILITY: Array[String] = ["source", "initialization", "mode_id", "rule_version", "content_version", "offer_version", "build_id", "commit_id", "config_hash", "seed", "collection_context", "pressure_version", "collection_config_hash", "strategy_version", "bot_config_hash", "experiment_id", "variant_id"]

static func normalize(source: Array[Dictionary]) -> Dictionary:
	var families: Dictionary[String, Array] = {}
	for event: Dictionary in source:
		if not families.has(event.run_id): families[event.run_id] = []
		families[event.run_id].append(event)
	var streams: Array[Array] = []
	var diagnostics: Array[Dictionary] = []
	var branches: Array[Dictionary] = []
	for run_id: String in families:
		var rows: Array[Dictionary] = []
		rows.assign(families[run_id])
		var resolved: Dictionary = _family(rows)
		branches.append({"run_id": run_id, "ok": resolved.ok, "reason": resolved.get("reason", ""), "segments": resolved.get("segments", []), "discarded_event_ids": resolved.get("discarded_event_ids", [])})
		if resolved.ok: streams.append(resolved.events)
		else: diagnostics.append({"run_id": run_id, "reason": resolved.reason})
	return {"streams": streams, "errors": diagnostics, "branches": branches}

static func _family(rows: Array[Dictionary]) -> Dictionary:
	var segments: Dictionary[String, Array] = {}
	var seen: Dictionary[String, String] = {}
	var has_resume: bool = false
	for row: Dictionary in rows:
		var validation: String = TelemetrySchema.validate(row)
		if not validation.is_empty(): return _fail(validation)
		has_resume = has_resume or row.schema_version == TelemetrySchema.RESUME_VERSION
		var encoded: String = RunSnapshot.canonical(row)
		if seen.has(row.event_id):
			if seen[row.event_id] != encoded: return _fail("conflicting_event_id")
			continue
		seen[row.event_id] = encoded
		var id: String = row.segment_id if row.schema_version == TelemetrySchema.RESUME_VERSION else row.session_id
		if not segments.has(id): segments[id] = []
		segments[id].append(row)
	if not has_resume:
		var unchanged: Array[Dictionary] = []
		for id: String in segments: unchanged.append_array(segments[id])
		unchanged.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.telemetry_seq.to_int() < b.telemetry_seq.to_int())
		return {"ok": true, "events": unchanged, "segments": segments.keys(), "discarded_event_ids": []}
	var roots: Array[String] = []
	var children: Dictionary[String, Array] = {}
	for id: String in segments:
		segments[id].sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.telemetry_seq.to_int() < b.telemetry_seq.to_int())
		var first: Dictionary = segments[id][0]
		for index: int in range(segments[id].size()):
			if segments[id][index].telemetry_seq != str(index + 1): return _fail("resume_segment_sequence_gap")
		if first.event_name == "run_started":
			roots.append(id)
			continue
		if first.event_name != "run_resumed" or not first.resume.lineage_known: return _fail("unknown_resume_parent")
		var parent: String = first.resume.parent_segment_id
		if not segments.has(parent): return _fail("missing_resume_parent")
		if not children.has(parent): children[parent] = []
		children[parent].append(id)
	if roots.size() != 1: return _fail("ambiguous_resume_roots")
	var root: String = roots[0]
	var header: Dictionary = segments[root][0]
	if header.schema_version != "2": return _fail("unsupported_resume_parent_schema")
	var chain: Array[String] = []
	var current: String = root
	while not current.is_empty():
		if current in chain: return _fail("resume_lineage_cycle")
		chain.append(current)
		var next: Array = children.get(current, [])
		if next.size() > 1: return _fail("ambiguous_resume_branches")
		current = String(next[0]) if not next.is_empty() else ""
	if chain.size() != segments.size(): return _fail("disconnected_resume_lineage")
	var result: Array[Dictionary] = []
	var discarded: Array[String] = []
	var offset: int = 0
	for position: int in range(chain.size()):
		var id: String = chain[position]
		var stream: Array = segments[id]
		for key: String in COMPATIBILITY:
			if stream[0].get(key) != header.get(key): return _fail("resume_metadata_mismatch:" + key)
		var cutoff: int = stream.size()
		if position + 1 < chain.size():
			var resume: Dictionary = segments[chain[position + 1]][0].resume
			cutoff = resume.parent_telemetry_seq.to_int()
			if cutoff <= 0 or cutoff > stream.size(): return _fail("resume_anchor_not_persisted")
			var anchor: Dictionary = stream[cutoff - 1]
			if anchor.event_id != resume.parent_last_event_id or RunSnapshot.digest(anchor) != resume.parent_last_event_hash:
				return _fail("resume_anchor_mismatch")
		for index: int in range(stream.size()):
			var source: Dictionary = stream[index]
			if index >= cutoff:
				discarded.append(source.event_id)
				continue
			if source.event_name == "resume_segment_closed": continue
			var row: Dictionary = source.duplicate(true)
			row["source_event_id"] = source.event_id
			row["source_event"] = source.duplicate(true)
			row["source_segment_id"] = id
			row["source_elapsed_ms"] = source.elapsed_ms
			row["resume_reassembled"] = true
			row.schema_version = "2"
			row.session_id = header.session_id
			row.parent_run_id = header.get("parent_run_id")
			row.event_id = header.run_id + ":" + str(result.size() + 1)
			row.telemetry_seq = str(result.size() + 1)
			row.elapsed_ms = str(source.elapsed_ms.to_int() + offset)
			row.erase("segment_id")
			row.erase("resume")
			if source.event_name == "run_resumed":
				row.event_name = "observation_checkpoint"
				row.payload = source.payload.initial_observation.duplicate(true)
				row.payload["resume_boundary"] = source.resume.duplicate(true)
			if row.event_name == "observation_interval_closed":
				row.payload.start_ms = str(source.payload.start_ms.to_int() + offset)
				row.payload.end_ms = str(source.payload.end_ms.to_int() + offset)
			if not TelemetrySchema.validate(row).is_empty(): return _fail("invalid_reassembled_event")
			result.append(row)
		if cutoff > 0: offset += stream[cutoff - 1].elapsed_ms.to_int()
	return {"ok": true, "events": result, "segments": chain, "discarded_event_ids": discarded}

static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
