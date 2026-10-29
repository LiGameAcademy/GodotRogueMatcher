class_name RunRandomStreams
extends RefCounted

## Owns the six independent gameplay RNGs for one run. No UI or disk access.
## Runtime seed/state use canonical signed 64-bit decimal strings, never JSON numbers.
const SCHEME_VERSION: String = "sl-rng-v1"
const IDS: Array[StringName] = [&"spawn_content", &"spawn_position", &"offer_candidates", &"offer_order", &"offer_targets", &"effect_execution"]

var master_seed: int
var _streams: Dictionary[StringName, RandomNumberGenerator] = {}

func _init(seed_value: int = 0) -> void:
	assert(seed_value >= 0, "master seed must be a nonnegative 63-bit integer")
	master_seed = seed_value
	for id: StringName in IDS:
		_streams[id] = create(seed_value, id)

## IDs are protocol constants, independent of construction order and resource paths.
static func create(seed_value: int, id: StringName) -> RandomNumberGenerator:
	assert(seed_value >= 0 and IDS.has(id), "invalid random stream identity")
	var bytes: PackedByteArray = (SCHEME_VERSION + "\n" + str(seed_value) + "\n" + String(id) + "\n").sha256_buffer()
	var derived: int = int(bytes[0]) & 0x7f
	for index: int in range(1, 8): derived = (derived << 8) | int(bytes[index])
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = derived
	return random

func stream(id: StringName) -> RandomNumberGenerator:
	assert(_streams.has(id), "unknown random stream")
	return _streams[id]

## Frozen value suitable for the checkpoint owner; modifying it cannot change this run.
func data() -> Dictionary:
	var values: Dictionary = {}
	for id: StringName in IDS:
		var random: RandomNumberGenerator = _streams[id]
		values[String(id)] = {"seed": str(random.seed), "state": str(random.state)}
	return {"rng_scheme_version": SCHEME_VERSION, "master_seed": str(master_seed), "streams": values}

## Validate the complete candidate before constructing a replacement; never repair missing streams.
## Rules/content/engine/schema compatibility and checkpoint takeover belong to the caller.
static func from_data(value: Variant) -> RunRandomStreams:
	if not value is Dictionary or not value.get("rng_scheme_version") is String: return null
	if value.rng_scheme_version != SCHEME_VERSION: return null
	if not _integer(value.get("master_seed")) or value.master_seed.to_int() < 0: return null
	if not value.get("streams") is Dictionary or value.streams.size() != IDS.size(): return null
	for id: StringName in IDS:
		var record: Variant = value.streams.get(String(id))
		if not record is Dictionary or record.size() != 2: return null
		if not _integer(record.get("seed")) or not _integer(record.get("state")): return null
	var result: RunRandomStreams = RunRandomStreams.new(value.master_seed.to_int())
	for id: StringName in IDS:
		var record: Dictionary = value.streams[String(id)]
		result.stream(id).seed = record.seed.to_int()
		result.stream(id).state = record.state.to_int()
	return result

static func _integer(value: Variant) -> bool:
	return value is String and value.is_valid_int() and str(value.to_int()) == value
