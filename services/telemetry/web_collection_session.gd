extends CollectionSession

## Browser observation journal; a document close never invents a process-death timestamp.
const BACKEND: Script = preload("res://services/telemetry/web_telemetry_backend.gd")
var _backend: BACKEND

func _init(backend: BACKEND) -> void:
	_backend = backend

func start(factory: TelemetryFactory, _recover_existing: bool = true) -> void:
	if not path.is_empty():
		error = "web_session_already_started"
		return
	path = "sessions/" + factory.session_id + ".jsonl"
	if not _backend.reserve(path):
		error = "web_session_unavailable"
		return
	append("session_started", {"session_id": factory.session_id, "pid": null, "platform": "Web", "context": factory.collection_context})

func append(kind: String, payload: Dictionary) -> void:
	if _closed or not error.is_empty(): return
	_sequence += 1
	var row: Dictionary = {"session_schema": "collection-session-v1", "seq": _sequence, "event": kind, "observed_at_utc": Time.get_datetime_string_from_system(true), "payload": payload}
	if not _backend.append(path, RunSnapshot.canonical(row) + "\n", _sequence):
		error = _backend.error if not _backend.error.is_empty() else "web_session_append_rejected"

func flush() -> void:
	if not _backend.error.is_empty(): error = _backend.error

func pending_persistence() -> bool:
	return _sequence > _backend.persisted_sequence(path)

func close(reason: String) -> void:
	if _closed: return
	append("session_closed", {"reason": reason})
	_closed = true
	flush()
