class_name CheckpointStore
extends RefCounted

## Owns one primary/previous slot, a rollback journal and durable per-run invalidation.
## Payloads are opaque values: the future run adapter validates safe points, versions
## and state invariants before constructing a fresh object graph. No rules or UI here.
## One synchronous owner per directory; no multi-process or absolute power-loss promise.
const FORMAT: String = "checkpoint-container-v1"
const INVALID_FORMAT: String = "checkpoint-invalid-v1"
const TRANSACTION_FORMAT: String = "checkpoint-transaction-v1"
const MAX_GENERATION: int = 9223372036854775807

var _directory: String
var _files: CheckpointFiles
var _active_run: String = ""
var _generation: int = 0
var _pending: Dictionary = {}
var _busy: bool = false
var _completed: int = 0
var _closing: Dictionary[String, bool] = {}
var _rejected_primary_digest: String = ""

func _init(directory: String, files: CheckpointFiles = null) -> void:
	_directory = directory
	_files = files if files != null else CheckpointFiles.new()

## The application retains exclusive ownership until the browser adapter acknowledges IO.
func sync() -> Dictionary:
	if _busy: return _failure("busy")
	_busy = true
	var result: Dictionary = await _files.sync()
	if not result.ok: _completed = 0
	_busy = false
	return result

## Requires verified invalidation before replacing another live identity.
func begin_run(run_id: String) -> Dictionary:
	if _busy: return _failure("busy")
	_busy = true
	var result: Dictionary = _begin_run(run_id)
	_busy = false
	return result

## Freezes an independent graph. Only the latest ticket can commit.
## All integers must already be decimal strings, never JSON numeric IDs.
func stage(payload: Dictionary, manifest: Dictionary) -> int:
	if _busy: return 0
	_busy = true
	var ticket: int = _stage(payload, manifest)
	_busy = false
	return ticket

## Success requires readback of both generations and retirement of the rollback journal.
func commit(ticket: int) -> Dictionary:
	if _busy: return _failure("busy")
	_busy = true
	var result: Dictionary = _commit_ticket(ticket)
	_busy = false
	return result

## Retains exclusive ownership across Web frame boundaries; sync acknowledgement is separate.
func commit_sliced(ticket: int, frame_yield: Callable) -> Dictionary:
	if _busy: return _failure("busy")
	if not frame_yield.is_valid(): return _failure("invalid_step_yield")
	_busy = true
	var prepared: Dictionary = _prepare_ticket(ticket)
	if not prepared.ok or prepared.get("duplicate", false):
		_busy = false
		return prepared
	var result: Dictionary = await _commit_pending_sliced(frame_yield)
	result = _finish_ticket(ticket, result)
	_busy = false
	return result

## A value copy and explicit fallback/recovery flags; never restores rules or consumes RNG.
func load_latest(expected_manifest: Dictionary) -> Dictionary:
	if _busy: return _failure("busy")
	_busy = true
	var result: Dictionary = _load_latest(expected_manifest)
	_busy = false
	return result

## Discovers compatibility and identity without restoring a run or bypassing invalidation.
func inspect_latest() -> Dictionary:
	if _busy: return _failure("busy")
	_busy = true
	var result: Dictionary = _inspect_latest()
	_busy = false
	return result

## Internal recovery only after the caller rejects this exact current primary payload.
## No arbitrary generation selection; invalidation and current compatibility still win.
func previous_after_rejection(expected_manifest: Dictionary, rejected: Dictionary) -> Dictionary:
	if _busy: return _failure("busy")
	_busy = true
	var result: Dictionary = _previous_after_rejection(expected_manifest, rejected)
	_busy = false
	return result

## Durable invalidation outranks primary and previous; failed attempts close local tickets.
func invalidate(run_id: String, reason: String) -> Dictionary:
	if _busy: return _failure("busy")
	_busy = true
	var result: Dictionary = _invalidate(run_id, reason)
	_busy = false
	return result

func _begin_run(run_id: String) -> Dictionary:
	if not _valid_id(run_id): return _failure("invalid_run_id")
	var recovery: Dictionary = _recover()
	if not recovery.ok: return recovery
	var error: String = _run_error(run_id)
	if not error.is_empty(): return _failure(error)
	var valid_count: int = 0
	var present_count: int = 0
	for name: String in ["primary.json", "previous.json"]:
		var found: Dictionary = _read_record(name)
		if found.reason == "missing": continue
		present_count += 1
		if found.reason == "schema_unsupported": return _failure(found.reason)
		if not found.ok: continue
		valid_count += 1
		var record: Dictionary = found.record
		_generation = maxi(_generation, String(record.generation).to_int())
		var previous_error: String = _run_error(record.run_id)
		if previous_error in ["invalidation_unreadable", "invalidation_pending"]: return _failure(previous_error)
		if record.run_id != run_id and previous_error != "run_invalidated": return _failure("previous_run_requires_invalidation")
	if present_count > 0 and valid_count == 0: return _failure("existing_checkpoint_unreadable")
	_active_run = run_id
	_pending.clear()
	_completed = 0
	return {"ok": true, "reason": "", "recovered_write": recovery.recovered}

func _stage(payload: Dictionary, manifest: Dictionary) -> int:
	if _active_run.is_empty() or _generation == MAX_GENERATION: return 0
	if not _pure(payload) or not _manifest_valid(manifest) or not _run_error(_active_run).is_empty(): return 0
	_generation += 1
	_pending = _seal({"format": FORMAT, "run_id": _active_run, "generation": str(_generation), "manifest": manifest.duplicate(true), "payload": payload.duplicate(true)})
	return _generation

func _commit_ticket(ticket: int) -> Dictionary:
	var prepared: Dictionary = _prepare_ticket(ticket)
	if not prepared.ok or prepared.get("duplicate", false): return prepared
	return _finish_ticket(ticket, _commit_pending())

func _prepare_ticket(ticket: int) -> Dictionary:
	if _active_run.is_empty(): return _failure("stale_ticket")
	var error: String = _run_error(_active_run)
	if not error.is_empty(): return _failure(error)
	if ticket == _completed and ticket == _generation and ticket > 0 and _pending.is_empty():
		return {"ok": true, "reason": "", "duplicate": true}
	if _pending.is_empty() or ticket != _generation or _pending.run_id != _active_run: return _failure("stale_ticket")
	var recovery: Dictionary = _recover()
	if not recovery.ok: return recovery
	return {"ok": true, "reason": ""}

func _finish_ticket(ticket: int, result: Dictionary) -> Dictionary:
	if not result.ok:
		var rollback: Dictionary = _recover()
		if not rollback.ok: result.reason += ";rollback_pending:" + String(rollback.reason)
		return result
	_completed = ticket
	_pending.clear()
	return result

func _load_latest(expected_manifest: Dictionary) -> Dictionary:
	if not _manifest_valid(expected_manifest): return _failure("invalid_manifest")
	var recovery: Dictionary = _recover()
	if not recovery.ok: return recovery
	var primary: Dictionary = _read_record("primary.json")
	if primary.reason == "schema_unsupported": return _failure(primary.reason)
	var candidate: Dictionary = primary
	var fallback: bool = not primary.ok
	if fallback: candidate = _read_record("previous.json")
	if not candidate.ok: return _failure("no_valid_checkpoint:" + candidate.reason)
	var record: Dictionary = candidate.record
	var error: String = _run_error(record.run_id)
	if not error.is_empty(): return _failure(error)
	if _json(record.manifest) != _json(expected_manifest): return _failure("manifest_incompatible")
	_generation = maxi(_generation, String(record.generation).to_int())
	return {"ok": true, "reason": "", "fallback": fallback, "recovered_write": recovery.recovered, "record": record.duplicate(true)}

func _inspect_latest() -> Dictionary:
	var recovery: Dictionary = _recover()
	if not recovery.ok: return recovery
	var candidate: Dictionary = _read_record("primary.json")
	if candidate.reason == "schema_unsupported": return _failure(candidate.reason)
	var fallback: bool = not candidate.ok
	if fallback: candidate = _read_record("previous.json")
	if not candidate.ok: return _failure("no_valid_checkpoint:" + candidate.reason)
	var record: Dictionary = candidate.record
	var error: String = _run_error(record.run_id)
	if not error.is_empty(): return {"ok": false, "reason": error, "run_id": record.run_id}
	return {"ok": true, "reason": "", "run_id": record.run_id, "manifest": record.manifest.duplicate(true), "generation": record.generation, "fallback": fallback}

func _previous_after_rejection(expected_manifest: Dictionary, rejected: Dictionary) -> Dictionary:
	var latest: Dictionary = _load_latest(expected_manifest)
	if not latest.ok: return latest
	if latest.fallback or latest.record != rejected: return _failure("recovery_primary_changed")
	var previous: Dictionary = _read_record("previous.json")
	if not previous.ok: return _failure("no_valid_previous:" + previous.reason)
	var record: Dictionary = previous.record
	if record.run_id != rejected.run_id or String(record.generation).to_int() >= String(rejected.generation).to_int():
		return _failure("recovery_identity_or_generation_mismatch")
	var error: String = _run_error(record.run_id)
	if not error.is_empty(): return _failure(error)
	if _json(record.manifest) != _json(expected_manifest): return _failure("manifest_incompatible")
	_rejected_primary_digest = rejected.digest
	return {"ok": true, "reason": "", "fallback": true, "recovered_write": latest.recovered_write, "record": record.duplicate(true)}

func _invalidate(run_id: String, reason: String) -> Dictionary:
	if not _valid_id(run_id) or reason not in ["restart", "terminal", "abandoned"]: return _failure("invalid_invalidation")
	_closing[run_id] = true
	if _active_run == run_id:
		_active_run = ""
		_pending.clear()
		_completed = 0
	var recovery: Dictionary = _recover()
	if not recovery.ok: return recovery
	var error: String = _marker_error(run_id)
	if error == "invalidation_unreadable": return _failure(error)
	if error == "run_invalidated":
		_closing.erase(run_id)
		return {"ok": true, "reason": "", "duplicate": true}
	var marker: Dictionary = _seal({"format": INVALID_FORMAT, "run_id": run_id, "reason": reason})
	var path: String = _marker_path(run_id)
	var result: Dictionary = _write_verified(path + ".tmp", marker, INVALID_FORMAT)
	if result.ok and _files.replace(path + ".tmp", path) != OK: result = _failure("invalidation_commit_failed")
	if result.ok and _marker_error(run_id) != "run_invalidated": result = _failure("invalidation_verify_failed")
	if result.ok: _closing.erase(run_id)
	return result

func _commit_pending() -> Dictionary:
	var pair: Dictionary = _prepare_commit_pair()
	if not pair.ok: return pair
	var staged: Dictionary = _stage_commit_pair(pair.primary, pair.previous)
	if not staged.ok: return staged
	var replaced: Dictionary = _replace_commit_pair(pair.primary)
	if not replaced.ok: return replaced
	return _verify_commit_pair(pair.primary)

func _commit_pending_sliced(frame_yield: Callable) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var pair: Dictionary = _prepare_commit_pair()
	if not pair.ok: return pair
	var largest: int = Time.get_ticks_usec() - started
	await frame_yield.call()
	started = Time.get_ticks_usec()
	var staged: Dictionary = _stage_commit_pair(pair.primary, pair.previous)
	if not staged.ok: return staged
	largest = maxi(largest, Time.get_ticks_usec() - started)
	await frame_yield.call()
	started = Time.get_ticks_usec()
	var replaced: Dictionary = _replace_commit_pair(pair.primary)
	if not replaced.ok: return replaced
	largest = maxi(largest, Time.get_ticks_usec() - started)
	await frame_yield.call()
	started = Time.get_ticks_usec()
	var result: Dictionary = _verify_commit_pair(pair.primary)
	result["largest_store_slice_usec"] = maxi(largest, Time.get_ticks_usec() - started)
	return result

func _prepare_commit_pair() -> Dictionary:
	var primary: Dictionary = _read_record("primary.json")
	var previous: Dictionary = _read_record("previous.json")
	for found: Dictionary in [primary, previous]:
		if found.ok and String(found.record.generation).to_int() >= _generation: return _failure("stale_disk_generation")
		if found.reason == "schema_unsupported": return _failure(found.reason)
		if found.reason in ["read_failed", "size_limit"]: return _failure("existing_checkpoint_unreadable")
	if primary.ok and primary.record.digest == _rejected_primary_digest:
		primary = {"ok": false, "reason": "rule_payload_rejected", "record": {}}
	return {"ok": true, "reason": "", "primary": primary, "previous": previous}

func _stage_commit_pair(primary: Dictionary, previous: Dictionary) -> Dictionary:
	var staged: Dictionary = _write_verified(_path("checkpoint.tmp"), _pending, FORMAT)
	if not staged.ok: return staged
	for name: String in ["primary.json", "previous.json"]:
		var found: Dictionary = primary if name == "primary.json" else previous
		if found.ok or found.reason == "missing": continue
		var preserved: Dictionary = _preserve_corrupt(name)
		if not preserved.ok: return preserved
	var transaction: Dictionary = _start_transaction()
	if not transaction.ok: return transaction
	return {"ok": true, "reason": ""}

func _replace_commit_pair(primary: Dictionary) -> Dictionary:
	if primary.ok:
		var backup: Dictionary = _write_verified(_path("previous.tmp"), primary.record, FORMAT)
		if not backup.ok: return backup
		if _files.replace(_path("previous.tmp"), _path("previous.json")) != OK: return _failure("backup_commit_failed")
	if _files.replace(_path("checkpoint.tmp"), _path("primary.json")) != OK: return _failure("primary_commit_failed")
	return {"ok": true, "reason": ""}

func _verify_commit_pair(primary: Dictionary) -> Dictionary:
	var verified: Dictionary = _read_record("primary.json")
	if not verified.ok or verified.record != _pending: return _failure("primary_verify_failed")
	if primary.ok:
		var verified_backup: Dictionary = _read_record("previous.json")
		if not verified_backup.ok or verified_backup.record != primary.record: return _failure("backup_verify_failed")
	if _files.remove(_path("transaction.json")) != OK or _files.exists(_path("transaction.json")): return _failure("transaction_finish_failed")
	return {"ok": true, "reason": "", "duplicate": false, "generation": str(_generation)}

func _start_transaction() -> Dictionary:
	var record: Dictionary = {"format": TRANSACTION_FORMAT, "run_id": _active_run, "generation": str(_generation), "primary_hash": "", "previous_hash": ""}
	for name: String in ["primary", "previous"]:
		var source: String = _path(name + ".json")
		if not _files.exists(source): continue
		var fingerprint: String = _files.fingerprint(source)
		if fingerprint.is_empty() or _files.copy_verified(source, _path(name + ".rollback")) != OK: return _failure("rollback_copy_failed")
		record[name + "_hash"] = fingerprint
	var written: Dictionary = _write_verified(_path("transaction.tmp"), _seal(record), TRANSACTION_FORMAT)
	if not written.ok: return written
	if _files.replace(_path("transaction.tmp"), _path("transaction.json")) != OK: return _failure("journal_commit_failed")
	return {"ok": true, "reason": ""}

## Unfinished transactions restore the exact old pair before any normal read/write.
func _recover() -> Dictionary:
	if not _files.exists(_path("transaction.json")): return {"ok": true, "reason": "", "recovered": false}
	var raw: Dictionary = _files.read_text(_path("transaction.json"))
	if not raw.ok: return _failure("journal_unreadable")
	var journal: Dictionary = _decode(raw.text, TRANSACTION_FORMAT)
	if not journal.ok: return _failure("journal_invalid:" + String(journal.reason))
	for name: String in ["primary", "previous"]:
		var expected: String = journal.record[name + "_hash"]
		var destination: String = _path(name + ".json")
		if expected.is_empty():
			if _files.remove(destination) != OK or _files.exists(destination): return _failure("rollback_remove_failed")
			continue
		var source: String = _path(name + ".rollback")
		if _files.fingerprint(source) != expected: return _failure("rollback_copy_invalid")
		if _files.copy_verified(source, _path(name + ".restore")) != OK: return _failure("rollback_restore_failed")
		if _files.replace(_path(name + ".restore"), destination) != OK: return _failure("rollback_restore_failed")
		if _files.fingerprint(destination) != expected: return _failure("rollback_verify_failed")
	if _files.remove(_path("transaction.json")) != OK or _files.exists(_path("transaction.json")): return _failure("rollback_finish_failed")
	return {"ok": true, "reason": "", "recovered": true}

func _write_verified(path: String, record: Dictionary, format: String) -> Dictionary:
	if _files.write_text(path, _json(record)) != OK: return _failure("temporary_write_failed:" + path.get_file())
	var readback: Dictionary = _files.read_text(path)
	if not readback.ok: return _failure("temporary_read_failed:" + path.get_file())
	var decoded: Dictionary = _decode(readback.text, format)
	if not decoded.ok or decoded.record != record: return _failure("temporary_verify_failed:" + path.get_file())
	return {"ok": true, "reason": ""}

func _read_record(name: String) -> Dictionary:
	var readback: Dictionary = _files.read_text(_path(name))
	if not readback.ok: return {"ok": false, "reason": readback.reason, "record": {}}
	return _decode(readback.text, FORMAT)

func _run_error(run_id: String) -> String:
	var error: String = _marker_error(run_id)
	if not error.is_empty(): return error
	return "invalidation_pending" if _closing.has(run_id) else ""

func _marker_error(run_id: String) -> String:
	var path: String = _marker_path(run_id)
	if not _files.exists(path):
		# Even an incomplete intent is fail-closed; retry must durably finish the marker.
		return "invalidation_pending" if _files.exists(path + ".tmp") else ""
	var readback: Dictionary = _files.read_text(path)
	if not readback.ok: return "invalidation_unreadable"
	var decoded: Dictionary = _decode(readback.text, INVALID_FORMAT)
	if not decoded.ok or decoded.record.run_id != run_id: return "invalidation_unreadable"
	return "run_invalidated"

func _preserve_corrupt(name: String) -> Dictionary:
	var source: String = _path(name)
	var fingerprint: String = _files.fingerprint(source)
	if fingerprint.is_empty(): return _failure("corrupt_original_unreadable")
	if _files.copy_verified(source, _path(name + ".corrupt-" + fingerprint + ".json")) != OK: return _failure("corrupt_original_preserve_failed")
	return {"ok": true, "reason": ""}

func _path(name: String) -> String:
	return _directory.path_join(name)

func _marker_path(run_id: String) -> String:
	return _path("invalid-" + run_id.sha256_text() + ".json")

static func _seal(value: Dictionary) -> Dictionary:
	var record: Dictionary = value.duplicate(true)
	record["digest"] = _json(value).sha256_text()
	return record

static func _decode(text: String, format: String) -> Dictionary:
	var parser: JSON = JSON.new()
	if parser.parse(text) != OK: return _failure("malformed_json")
	var value: Variant = parser.data
	if not value is Dictionary: return _failure("malformed_json")
	var record: Dictionary = value as Dictionary
	if not record.get("format") is String: return _failure("invalid_envelope")
	if record.format != format: return _failure("schema_unsupported")
	if not record.get("digest") is String or not record.get("run_id") is String or not _valid_id(record.run_id): return _failure("invalid_envelope")
	var content: Dictionary = record.duplicate(true)
	content.erase("digest")
	if record.digest != _json(content).sha256_text(): return _failure("checksum_mismatch")
	if format == INVALID_FORMAT:
		if record.size() != 4 or record.get("reason") not in ["restart", "terminal", "abandoned"]: return _failure("invalid_marker")
	else:
		if record.size() != 6 or not record.get("generation") is String: return _failure("invalid_envelope")
		var generation: String = record.generation
		if not generation.is_valid_int() or str(generation.to_int()) != generation or generation.to_int() <= 0: return _failure("invalid_generation")
		if format == TRANSACTION_FORMAT:
			for key: String in ["primary_hash", "previous_hash"]:
				if not record.get(key) is String: return _failure("invalid_journal")
				if not record[key].is_empty() and RegEx.create_from_string("^[0-9a-f]{64}$").search(record[key]) == null: return _failure("invalid_journal")
		else:
			if not record.get("manifest") is Dictionary or not _manifest_valid(record.manifest): return _failure("invalid_manifest")
			if not record.get("payload") is Dictionary or not _pure(record.payload): return _failure("invalid_payload")
	return {"ok": true, "reason": "", "record": record}

static func _manifest_valid(value: Dictionary) -> bool:
	if value.is_empty(): return false
	for key: Variant in value:
		if not key is String or key.is_empty() or not value[key] is String or value[key].is_empty(): return false
	return true

static func _pure(value: Variant, depth: int = 0) -> bool:
	if depth > 64: return false
	if value == null or value is String or value is bool: return true
	if value is float: return is_finite(value)
	if value is Array:
		for element: Variant in value:
			if not _pure(element, depth + 1): return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not key is String or not _pure(value[key], depth + 1): return false
		return true
	return false

static func _valid_id(run_id: String) -> bool:
	return run_id.length() <= 128 and RegEx.create_from_string("^[A-Za-z0-9][A-Za-z0-9_.-]*$").search(run_id) != null

static func _json(value: Dictionary) -> String:
	return JSON.stringify(value, "", true)

static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "record": {}}
