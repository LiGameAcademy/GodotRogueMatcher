class_name TelemetrySchema
extends RefCounted

const VERSION: String = "2"
const REQUIRED_V2: Dictionary[String, Array] = {
	"action_resolved": ["complete", "action_score_delta", "q_frozen", "P_before", "P_after", "stage_before", "stage_after", "created_ids", "removed_ids"],
	"stage_goal_completed": ["result", "P_before", "P_after", "installed_build", "goal_effects_implemented"],
	"rule_fact": ["fact"],
	"ui_observed": ["ui", "category", "phase", "root_complete"],
	"observation_checkpoint": ["ui", "category", "phase", "root_complete"]
}
const REQUIRED: Dictionary[String, Array] = {
	"run_started": ["columns", "rows", "ordinary", "companions", "score"],
	"command_resolved": ["type", "accepted", "reason", "buffered", "buffer_wait_ms", "action_before", "action_after"],
	"turn_resolved": ["turn_id", "score_before", "score_after", "occupied_before", "occupied_after", "created", "removed", "complete"],
	"offer_generated": ["offer_id", "reward_id", "choices", "weights", "density", "build"],
	"offer_presented": ["offer_id", "presentation_id", "choices", "density"],
	"skill_acquired": ["offer_id", "skill_id", "count_before", "count_after", "tool_role", "score_delta", "net_empty", "game_over"],
	"observation_interval_closed": ["category", "start_ms", "end_ms", "duration_ms"],
	"input_resolved": ["input_id", "type", "disposition", "reason", "buffered", "buffer_wait_ms"],
	"run_ended": ["status", "reason", "score", "moves", "choices", "times", "record_complete"]
}

static func safe_id(value: String) -> bool:
	return not value.is_empty() and RegEx.create_from_string("^[A-Za-z0-9_-]+$").search(value) != null

static func plain(value: Variant) -> bool:
	if value == null or value is String or value is bool: return true
	if value is float: return is_finite(value)
	if value is Array:
		for child: Variant in value:
			if not plain(child): return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not key is String or not plain(value[key]): return false
		return true
	return false

static func validate(event: Dictionary) -> String:
	if event.get("schema_version") not in ["1", VERSION]: return "unsupported_telemetry_schema"
	if not event.get("event_name") is String or (not REQUIRED.has(event.event_name) and (event.schema_version == "1" or not REQUIRED_V2.has(event.event_name))): return "unknown_telemetry_event"
	for key: String in ["event_id", "run_id", "session_id", "rule_version", "content_version", "offer_version", "build_id", "config_hash", "source", "initialization"]:
		if not event.get(key) is String: return "invalid_envelope_" + key
	if not safe_id(event.run_id) or not CommandCodec.valid_integer(event.get("telemetry_seq")) or event.telemetry_seq.to_int() <= 0: return "invalid_telemetry_id"
	if event.event_id != event.run_id + ":" + event.telemetry_seq: return "invalid_event_id"
	if not CommandCodec.valid_integer(event.get("elapsed_ms")) or event.elapsed_ms.to_int() < 0: return "invalid_elapsed"
	for key: String in ["action_id", "turn_index", "command_id", "experiment_id", "variant_id", "strategy_version"]:
		if not event.has(key) or (event[key] != null and not event[key] is String): return "invalid_envelope_" + key
	if not event.get("payload") is Dictionary or not plain(event): return "non_serializable_telemetry"
	if event.get("bot_config_hash") != null and not event.bot_config_hash is String: return "invalid_envelope_bot_config_hash"
	if event.schema_version == VERSION:
		for key: String in ["mode_id", "collection_context", "commit_id", "seed", "pressure_version", "collection_config_hash"]:
			if not event.get(key) is String: return "invalid_envelope_" + key
		for key: String in ["rule_event_id", "parent_event_id", "root_action_id", "batch_id", "stage_id", "reward_id", "offer_id"]:
			if not event.has(key) or (event[key] != null and not event[key] is String): return "invalid_envelope_" + key
	var required: Array = REQUIRED.get(event.event_name, REQUIRED_V2.get(event.event_name, []))
	for key: String in required:
		if not event.payload.has(key): return "missing_payload_" + key
	return _payload(event.event_name, event.payload)

static func _payload(name: String, data: Dictionary) -> String:
	var integers: PackedStringArray = []
	var booleans: PackedStringArray = []
	var strings: PackedStringArray = []
	match name:
		"action_resolved":
			if not data.complete is bool or not data.P_before is Dictionary or not data.P_after is Dictionary: return "invalid_action_summary"
			if not _pressure(data.P_before) or not _pressure(data.P_after) or not _stage(data.stage_before) or not _stage(data.stage_after): return "invalid_action_observation"
			if not _ids(data.created_ids) or not _ids(data.removed_ids) or not data.get("ledger_entries") is Array: return "invalid_action_entities"
			for entry: Variant in data.ledger_entries:
				if not _ledger(entry): return "invalid_action_ledger"
			integers = ["action_score_delta", "q_frozen", "created", "removed", "event_count", "max_generation", "score_before", "score_after", "occupied_before", "occupied_after"]
			booleans = ["complete", "space_consistent", "spawn_skipped"]
		"stage_goal_completed":
			if not data.result is Dictionary or not data.installed_build is Dictionary or not data.goal_effects_implemented is bool: return "invalid_goal_summary"
			if not _pressure(data.P_before) or (data.P_after != null and not _pressure(data.P_after)): return "invalid_goal_pressure"
		"rule_fact": strings = ["fact"]
		"ui_observed", "observation_checkpoint":
			strings = ["ui", "category"]
			booleans = ["root_complete"]
			if not _pressure(data.get("pressure")) or not _stage(data.get("stage")): return "invalid_ui_observation"
		"run_started": integers = ["columns", "rows", "ordinary", "companions", "score"]
		"command_resolved":
			integers = ["buffer_wait_ms", "action_before", "action_after"]
			booleans = ["accepted", "buffered"]
			strings = ["type", "reason"]
		"turn_resolved":
			integers = ["turn_id", "score_before", "score_after", "occupied_before", "occupied_after", "created", "removed"]
			booleans = ["complete"]
		"offer_generated", "offer_presented":
			integers = ["offer_id"]
			if not data.choices is Array: return "invalid_choices"
			for id: Variant in data.choices:
				if not id is String: return "invalid_choices"
			if not data.density is float or data.density < 0.0 or data.density > 1.0: return "invalid_density"
			if name == "offer_generated":
				integers.append("reward_id")
				if not data.weights is Dictionary or not data.build is Dictionary: return "invalid_offer_details"
			else: strings = ["presentation_id"]
		"skill_acquired":
			integers = ["offer_id", "count_before", "count_after", "score_delta", "net_empty"]
			booleans = ["game_over"]
			strings = ["skill_id"]
			if data.tool_role != null and not data.tool_role is String: return "invalid_tool_role"
		"observation_interval_closed":
			integers = ["start_ms", "end_ms", "duration_ms"]
			if data.category not in ["pause", "choice", "busy", "input", "inactive"]: return "invalid_interval"
		"input_resolved":
			integers = ["buffer_wait_ms"]
			booleans = ["buffered"]
			strings = ["input_id", "type", "disposition", "reason"]
		"run_ended":
			integers = ["score", "moves", "choices", "observed_ms", "active_ms"]
			booleans = ["record_complete"]
			strings = ["status", "reason"]
			if data.status not in ["completed", "abandoned", "rule_error", "censored"] or not data.times is Dictionary: return "invalid_ending"
	for key: String in integers:
		if not CommandCodec.valid_integer(data.get(key)): return "invalid_integer_" + key
	for key: String in booleans:
		if not data.get(key) is bool: return "invalid_boolean_" + key
	for key: String in strings:
		if not data.get(key) is String: return "invalid_string_" + key
	return ""

static func _pressure(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key: String in ["n", "empty", "L"]:
		if not CommandCodec.valid_integer(value.get(key)) or int(value[key]) < 0: return false
	return value.get("P") is float and float(value.P) >= 0.0 and float(value.P) <= 100.0 and int(value.L) <= int(value.empty)

static func _stage(value: Variant) -> bool:
	if not value is Dictionary or not value.get("enabled") is bool: return false
	if value.get("invalid", false): return value.invalid is bool
	if not CommandCodec.valid_integer(value.get("q")) or int(value.q) < 1 or int(value.q) > 6: return false
	if not value.enabled: return value.get("u") == null and value.get("T") == null
	for key: String in ["stage_id", "u", "T", "action_score", "carry", "missing"]:
		if not CommandCodec.valid_integer(value.get(key)): return false
	return true

static func _ids(value: Variant) -> bool:
	if not value is Array: return false
	for id: Variant in value:
		if not CommandCodec.valid_integer(id) or int(id) <= 0: return false
	return true

static func _ledger(value: Variant) -> bool:
	if not value is Dictionary or not value.get("reason") is String or not _ids(value.get("targets")): return false
	for key: String in ["event_id", "action_id", "source_id", "N", "B", "E", "final_score"]:
		if not CommandCodec.valid_integer(value.get(key)): return false
	return value.get("G") is float
