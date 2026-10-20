class_name TelemetrySummary
extends RefCounted

## 一局一份，先写临时文件再原子改名；已有同内容幂等，冲突不覆盖。
static func write_unique(path: String, data: Dictionary) -> String:
	var encoded: String = RunSnapshot.canonical(data)
	if FileAccess.file_exists(path):
		return "" if FileAccess.get_file_as_string(path) == encoded else "summary_conflict"
	var temporary: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return "summary_open_failed"
	file.store_string(encoded)
	file.flush()
	var code: Error = file.get_error()
	file.close()
	if code != OK: return "summary_write_failed"
	return "" if DirAccess.rename_absolute(temporary, path) == OK else "summary_rename_failed"

## 恢复只读校验后的持久前缀；不制造Footer、完整行动或主动退出。
static func recover(path: String) -> Dictionary:
	var reader: TelemetryReader = TelemetryReader.new()
	var events: Array[Dictionary] = reader.read_file(path)
	if events.is_empty(): return {"error": reader.error, "data_integrity": "corrupt"}
	var first: Dictionary = events.front()
	var final: Dictionary = events.back()
	var observation: Dictionary = first.payload.get("initial_observation", {}).duplicate(true)
	var last_complete: String = "0"
	var completed: int = 0
	for event: Dictionary in events:
		if event.event_name in ["ui_observed", "observation_checkpoint"]: observation.merge(event.payload, true)
		if event.event_name == "action_resolved" and event.payload.complete:
			last_complete = event.root_action_id
			completed += 1
	var malformed: bool = reader.error not in ["", "incomplete_last_line", "incomplete_telemetry_no_complete_ending"]
	var result: Dictionary = {"summary_version": "recovered-run-summary-v2", "run_id": first.run_id, "session_id": first.session_id, "mode_id": first.get("mode_id"), "collection_context": first.get("collection_context", "unknown"), "source": first.source, "end_class": "unexpected_stop", "reason": "unknown", "data_integrity": "corrupt" if malformed else "prefix_only", "record_complete": false, "last_persisted_seq": final.telemetry_seq, "last_observed_elapsed_ms": final.elapsed_ms, "last_observation": observation, "last_complete_action_id": last_complete, "complete_actions": completed, "recovered_at_utc": Time.get_datetime_string_from_system(true), "original_path": path, "read_error": reader.error}
	if final.event_name == "run_ended" and not malformed:
		result.merge(final.payload, true)
		result["end_class"] = TelemetryFacts.ending(final.payload.status)
		result["data_integrity"] = "complete" if reader.complete else "write_failed"
	result["last_observed_utc"] = final.get("observed_at_utc")
	return RunSnapshot.normalize(result)
