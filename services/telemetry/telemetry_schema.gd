class_name TelemetrySchema
extends RefCounted

const VERSION: String = "1"
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
	if event.get("schema_version") != VERSION: return "unsupported_telemetry_schema"
	if not event.get("event_name") is String or not REQUIRED.has(event.event_name): return "unknown_telemetry_event"
	for key: String in ["event_id", "run_id", "session_id", "rule_version", "content_version", "offer_version", "build_id", "config_hash", "source", "initialization"]:
		if not event.get(key) is String: return "invalid_envelope_" + key
	if not safe_id(event.run_id) or not CommandCodec.valid_integer(event.get("telemetry_seq")) or event.telemetry_seq.to_int() <= 0: return "invalid_telemetry_id"
	if event.event_id != event.run_id + ":" + event.telemetry_seq: return "invalid_event_id"
	if not CommandCodec.valid_integer(event.get("elapsed_ms")) or event.elapsed_ms.to_int() < 0: return "invalid_elapsed"
	for key: String in ["action_id", "turn_index", "command_id", "experiment_id", "variant_id", "strategy_version"]:
		if not event.has(key) or (event[key] != null and not event[key] is String): return "invalid_envelope_" + key
	if not event.get("payload") is Dictionary or not plain(event): return "non_serializable_telemetry"
	if event.get("bot_config_hash") != null and not event.bot_config_hash is String: return "invalid_envelope_bot_config_hash"
	for key: String in REQUIRED[event.event_name]:
		if not event.payload.has(key): return "missing_payload_" + key
	return _payload(event.event_name, event.payload)

static func _payload(name: String, data: Dictionary) -> String:
	var integers: PackedStringArray = []
	var booleans: PackedStringArray = []
	var strings: PackedStringArray = []
	match name:
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
