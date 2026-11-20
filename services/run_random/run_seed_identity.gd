class_name RunSeedIdentity
extends RefCounted

## Author premise for 0.0.3 (#161): one master seed per run; named streams grow from it.
## Returns "" when the live run matches; otherwise a stable reason string.

static func error(run: RunController) -> String:
	if run == null or run.state == null or run.state.random_streams == null:
		return "missing_run_streams"
	var streams: RunRandomStreams = run.state.random_streams
	if streams.master_seed < 0:
		return "negative_master_seed"
	var expected: Dictionary = RunRandomStreams.new(streams.master_seed).data()
	for id: StringName in RunRandomStreams.IDS:
		var live: RandomNumberGenerator = streams.stream(id)
		var derived: Dictionary = expected.streams[String(id)]
		if str(live.seed) != derived.seed:
			return "stream_seed_not_derived_from_master:" + String(id)
	if run.state.random != streams.stream(&"spawn_position"):
		return "spawn_position_not_owned"
	if run.state.spawning == null or run.state.spawning.content_random != streams.stream(&"spawn_content"):
		return "spawn_content_not_owned"
	if run.state.rewards == null:
		return "missing_rewards"
	if run.state.rewards.candidate_random != streams.stream(&"offer_candidates"):
		return "offer_candidates_not_owned"
	if run.state.rewards.display_random != streams.stream(&"offer_order"):
		return "offer_order_not_owned"
	if run.state.rewards.target_random != streams.stream(&"offer_targets"):
		return "offer_targets_not_owned"
	return ""

static func header_error(header: Dictionary, run: RunController) -> String:
	var identity: String = error(run)
	if not identity.is_empty():
		return identity
	if str(header.get("seed", "")) != str(run.state.random_streams.master_seed):
		return "header_seed_mismatch"
	var rng: Variant = header.get("rng")
	if not rng is Dictionary:
		return "missing_header_rng"
	if str(rng.get("master_seed", "")) != str(run.state.random_streams.master_seed):
		return "header_rng_master_mismatch"
	if str(rng.get("rng_scheme_version", "")) != RunRandomStreams.SCHEME_VERSION:
		return "header_rng_scheme_mismatch"
	return ""
