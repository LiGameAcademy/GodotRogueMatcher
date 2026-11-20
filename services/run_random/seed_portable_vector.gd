class_name SeedPortableVector
extends RefCounted

## Cross-environment comparison payload for #161 RF01/RP matrix.
## Compares derived stream seeds and the first N draws; never claims full gameplay replay.
const PROTOCOL: String = "seed-portable-v1"
const DEFAULT_DRAWS: int = 8

static func build(master_seed: int, draws: int = DEFAULT_DRAWS) -> Dictionary:
	var streams: RunRandomStreams = RunRandomStreams.new(master_seed)
	var initial: Dictionary = streams.data()
	var first_draws: Dictionary = {}
	for id: StringName in RunRandomStreams.IDS:
		var values: Array[String] = []
		var rng: RandomNumberGenerator = streams.stream(id)
		for index: int in range(maxi(0, draws)):
			values.append(str(rng.randi()))
		first_draws[String(id)] = values
	return {
		"protocol": PROTOCOL,
		"rng_scheme_version": RunRandomStreams.SCHEME_VERSION,
		"master_seed": str(master_seed),
		"draws": draws,
		"streams": initial.streams,
		"first_draws": first_draws,
		"godot": Engine.get_version_info().string,
		"engine_build": str(Engine.get_version_info().hash),
		"platform": OS.get_name(),
	}

## Compares only scheme/seed/stream/draw fields; platform tags are informational.
static func gameplay_mismatch(expected: Dictionary, actual: Dictionary) -> String:
	if expected.get("protocol") != PROTOCOL or actual.get("protocol") != PROTOCOL:
		return "protocol_mismatch"
	for key: String in ["rng_scheme_version", "master_seed", "draws"]:
		if str(expected.get(key, "")) != str(actual.get(key, "")):
			return "field_mismatch:" + key
	if RunSnapshot.canonical(expected.get("streams", {})) != RunSnapshot.canonical(actual.get("streams", {})):
		return "stream_seed_mismatch"
	if RunSnapshot.canonical(expected.get("first_draws", {})) != RunSnapshot.canonical(actual.get("first_draws", {})):
		return "first_draw_mismatch"
	return ""
