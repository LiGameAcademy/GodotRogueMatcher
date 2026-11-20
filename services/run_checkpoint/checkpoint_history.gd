class_name CheckpointHistory
extends RefCounted

## Private immutable copies of append-only recorder history. New saves copy only new records.
## Outer arrays are independent; shared cached dictionaries and nested arrays are read-only.
var _source: RunRecorder
var _records: Array[Dictionary] = []
var _compatibility: Dictionary = {}

## May run in a worker only for that worker's independent restored run, never an active scene run.
func prime(run: RunController) -> void:
	_source = run.recorder
	_records = []
	_compatibility = RunCheckpointCodec.manifest(run)
	_append_new()

func freeze(run: RunController) -> Dictionary:
	if run.recorder == null: return RunCheckpointCodec.failure("complete_prefix_required")
	if run.recorder.records.size() > RunCheckpointCodec.MAX_RECORDS: return RunCheckpointCodec.failure("prefix_record_limit")
	if _source != run.recorder or run.recorder.records.size() < _records.size() or (not _records.is_empty() and _records[0] != run.recorder.records[0]): prime(run)
	else: _append_new()
	var snapshot: Array[Dictionary] = _records.duplicate(false)
	snapshot.make_read_only()
	return RunCheckpointCodec.freeze(run, snapshot, _compatibility)

func _append_new() -> void:
	for index: int in range(_records.size(), _source.records.size()):
		var record: Dictionary = _source.records[index].duplicate(true)
		_lock(record)
		_records.append(record)

func _lock(value: Variant) -> void:
	if value is Dictionary:
		for key: Variant in value: _lock(value[key])
		value.make_read_only()
	elif value is Array:
		for element: Variant in value: _lock(element)
		value.make_read_only()
