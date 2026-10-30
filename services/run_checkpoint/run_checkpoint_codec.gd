class_name RunCheckpointCodec
extends RefCounted

## Encodes a self-contained safe-point checkpoint, not a JSONL file or UI snapshot.
## Rebuilds only in an unobserved, memory-only run and verifies the exact endpoint.
const SCHEMA: String = "run-checkpoint-prefix-v1"
const MAX_PAYLOAD_BYTES: int = 15 * 1024 * 1024
const MAX_RECORDS: int = 4096
const REBUILD_BUDGET_USEC: int = 2000000
const PAYLOAD_KEYS: Array[String] = ["schema", "run_id", "master_seed", "point", "record_seq", "state", "state_hash", "records", "offer_cache"]

## Compatibility policy is independent of the saved seed and logical run identity.
static func manifest(run: RunController) -> Dictionary:
	var config: Dictionary = RunSnapshot.config(run)
	return {
		"save_schema_version": SCHEMA, "rules_version": RunSnapshot.RULES_VERSION,
		"rng_scheme_version": RunRandomStreams.SCHEME_VERSION,
		"engine_build": Engine.get_version_info().hash,
		"engine_version": Engine.get_version_info().string, "platform": OS.get_name(),
		"mode_id": String(run.state.mode_id()), "config_hash": RunSnapshot.digest(config),
		"content_hash": RunSnapshot.digest(config.skills),
		"offer_version": SkillOfferGenerator.version_for_mode(run.state.mode_id()),
	}

## Reads without advancing the source or adding a recorder checkpoint.
static func encode(run: RunController) -> Dictionary:
	var reason: String = safety_error(run)
	if not reason.is_empty(): return failure(reason)
	if run.recorder == null or run.recorder.ended: return failure("complete_prefix_required")
	var records: Array[Dictionary] = run.recorder.records
	if records.is_empty() or records.size() > MAX_RECORDS: return failure("prefix_record_limit")
	var state: Dictionary = RunSnapshot.capture(run)
	if records.back().get("kind") != "Checkpoint" or records.back().get("state") != state:
		return failure("endpoint_not_recorded")
	var payload: Dictionary = {
		"schema": SCHEMA, "run_id": run.state.run_id,
		"master_seed": str(run.state.random_streams.master_seed),
		"point": "input" if run.state.phase == RunState.Phase.INPUT else "frozen_reward",
		"record_seq": str(records.size()), "state": state,
		"state_hash": RunSnapshot.digest(state), "records": records.duplicate(true),
		"offer_cache": _offer_cache(run),
	}
	if not pure(payload): return failure("noncanonical_payload")
	if JSON.stringify(payload).to_utf8_buffer().size() > MAX_PAYLOAD_BYTES: return failure("payload_size_limit")
	return {"ok": true, "reason": "", "payload": payload, "manifest": manifest(run)}

## Returns a new run only on complete validation. Never retires or mutates a caller's run.
## The elapsed guard rejects slow results after replay; it cannot preempt a single rule call.
static func decode(payload: Variant, expected_manifest: Dictionary, budget_usec: int = REBUILD_BUDGET_USEC) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var reason: String = _payload_error(payload)
	if not reason.is_empty(): return failure(reason)
	if budget_usec <= 0: return failure("rebuild_budget_exceeded")
	var records: Array[Dictionary] = []
	records.assign(payload.records)
	var replay: RuleReplay = RuleReplay.new()
	if not replay.restore_prefix(records): return failure("rebuild_failed:" + replay.error)
	var run: RunController = replay.run
	if manifest(run) != expected_manifest: return failure("manifest_incompatible")
	if run.state.run_id != payload.run_id or str(run.state.random_streams.master_seed) != payload.master_seed:
		return failure("identity_mismatch")
	var state: Dictionary = RunSnapshot.capture(run)
	if state != payload.state or RunSnapshot.digest(state) != payload.state_hash:
		return failure("endpoint_mismatch")
	if _offer_cache(run) != payload.offer_cache: return failure("offer_cache_mismatch")
	reason = safety_error(run)
	if not reason.is_empty(): return failure(reason)
	var point: String = "input" if run.state.phase == RunState.Phase.INPUT else "frozen_reward"
	if point != payload.point: return failure("safe_point_mismatch")
	var elapsed: int = Time.get_ticks_usec() - started
	if elapsed > budget_usec: return failure("rebuild_budget_exceeded")
	# Replay's recorder has no file or external listeners. Keep it for subsequent safe saves.
	return {"ok": true, "reason": "", "run": run, "rebuild_usec": elapsed}

## A phase enum alone is insufficient: no unresolved descendants or ability tickets may remain.
static func safety_error(run: RunController) -> String:
	if run == null or run.is_retired(): return "run_closed"
	if run.state.is_game_over or not run.state.rule_error.is_empty(): return "run_not_resumable"
	if not run.state.ability_events.data().active: return "events_closed"
	if run.abilities.has_pending_work(): return "pending_descendants"
	if run.state.phase == RunState.Phase.INPUT:
		if run.continuation != &"idle" or run.state.pending_rewards != 0 or run.state.rewards.active_offer != null:
			return "unsafe_input"
	elif run.state.phase == RunState.Phase.REWARDS and run.state.pending_rewards > 0:
		var offer: SkillOffer = run.state.rewards.active_offer
		if offer == null or offer.choices.is_empty() or offer.choices.size() > 3: return "unfrozen_reward"
		if run.continuation not in [&"idle", &"before_end", &"after_end", &"after_spawn"]: return "invalid_continuation"
		if offer.reward_id != run.state.rewards.consumed_count + 1 or offer.offer_id <= 0:
			return "invalid_reward_identity"
		for skill: SkillDefinition in offer.choices:
			if skill == null or not offer.targets.has(skill.skill_id): return "missing_frozen_target"
			if not _target_valid(offer.targets[skill.skill_id], {}, 0): return "invalid_frozen_target"
	else:
		return "unsafe_phase"
	var state: Dictionary = RunSnapshot.capture(run)
	for instance: Dictionary in state.instances:
		if instance.pending_event_id != "0": return "pending_ability"
	return ""

## Validate the target graph before snapshot traversal, including malformed nested/cyclic leaves.
static func _target_valid(target: SkillTarget, visiting: Dictionary, depth: int) -> bool:
	if target == null or depth > 32 or visiting.has(target.get_instance_id()): return false
	visiting[target.get_instance_id()] = true
	if target is CompositeSkillTarget:
		for leaf: SkillTarget in (target as CompositeSkillTarget).leaf_targets:
			if not _target_valid(leaf, visiting, depth + 1): return false
	visiting.erase(target.get_instance_id())
	return true

static func _payload_error(payload: Variant) -> String:
	if not payload is Dictionary or payload.size() != PAYLOAD_KEYS.size(): return "invalid_payload"
	for key: String in PAYLOAD_KEYS:
		if not payload.has(key): return "missing_payload_field:" + key
	if not pure(payload): return "noncanonical_payload"
	if JSON.stringify(payload).to_utf8_buffer().size() > MAX_PAYLOAD_BYTES: return "payload_size_limit"
	if payload.schema != SCHEMA: return "schema_unsupported"
	if not payload.run_id is String or payload.run_id.is_empty(): return "invalid_run_id"
	if not CommandCodec.valid_integer(payload.master_seed) or payload.master_seed.to_int() < 0: return "invalid_master_seed"
	if not payload.state is Dictionary or not payload.state_hash is String or not payload.offer_cache is Dictionary:
		return "invalid_endpoint"
	if RunSnapshot.digest(payload.state) != payload.state_hash: return "endpoint_hash_mismatch"
	if payload.point not in ["input", "frozen_reward"]: return "invalid_safe_point"
	if not payload.records is Array or payload.records.is_empty() or payload.records.size() > MAX_RECORDS:
		return "prefix_record_limit"
	if not CommandCodec.valid_integer(payload.record_seq) or payload.record_seq.to_int() != payload.records.size():
		return "prefix_sequence_mismatch"
	for index: int in range(payload.records.size()):
		var row: Variant = payload.records[index]
		if not row is Dictionary or not CommandCodec.valid_integer(row.get("seq")) or row.seq.to_int() != index + 1:
			return "invalid_record_sequence"
		if not row.get("kind") is String: return "invalid_record_kind"
		if index == 0:
			if row.kind != "Header" or not row.get("metadata") is Dictionary or not row.get("source") is String:
				return "invalid_prefix_header"
			if row.get("run_id") != payload.run_id or row.get("seed") != payload.master_seed: return "identity_mismatch"
		elif row.kind == "CommandAttempt":
			if not row.get("command") is Dictionary or CommandCodec.decode(row.command) == null: return "invalid_command"
		elif row.kind not in ["Checkpoint", "RuleResult", "SkillAcquired", "Offer"]:
			return "unsupported_record"
	var last: Dictionary = payload.records.back()
	if last.kind != "Checkpoint" or last.get("state") != payload.state or last.get("hash") != payload.state_hash:
		return "incomplete_prefix"
	return ""

static func _offer_cache(run: RunController) -> Dictionary:
	var offer: SkillOffer = run.state.rewards.active_offer
	if offer == null: return {}
	return RunSnapshot.normalize({"profile_id": offer.profile_id, "unavailable": offer.unavailable})

## Bounds recursion and excludes objects and raw integers before canonicalization/replay.
static func pure(value: Variant, depth: int = 0) -> bool:
	if depth > 64: return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING: return true
		TYPE_FLOAT: return is_finite(value)
		TYPE_ARRAY:
			for element: Variant in value:
				if not pure(element, depth + 1): return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if not key is String or not pure(value[key], depth + 1): return false
			return true
	return false

static func failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
