extends CheckpointFiles

## Deterministically pauses a real file transaction for an external, PID-checked kill.
## The host must terminate only the process reported by its own launch receipt.
var phase: String = ""
var signal_path: String = ""

func write_text(path: String, text: String) -> Error:
	if phase != "partial" or path.get_file() != "checkpoint.tmp":
		return super.write_text(path, text)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if directory_error != OK: return directory_error
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	var bytes: PackedByteArray = text.to_utf8_buffer()
	file.store_buffer(bytes.slice(0, maxi(1, bytes.size() / 2)))
	file.flush()
	_pause(path)
	return ERR_BUSY

func replace(source: String, destination: String) -> Error:
	var result: Error = super.replace(source, destination)
	if result != OK: return result
	if (phase == "backup" and destination.get_file() == "previous.json") or (phase == "primary" and destination.get_file() == "primary.json"):
		_pause(destination)
	return result

func _pause(path: String) -> void:
	var directory: String = path.get_base_dir()
	var signal_file: FileAccess = FileAccess.open(signal_path, FileAccess.WRITE)
	if signal_file == null: return
	signal_file.store_string(JSON.stringify({"pid": OS.get_process_id(), "phase": phase,
		"primary_hash": fingerprint(directory.path_join("primary.json")),
		"previous_hash": fingerprint(directory.path_join("previous.json")),
		"journal": exists(directory.path_join("transaction.json")), "paused_path": path}))
	signal_file.flush()
	signal_file.close()
	# No graceful shutdown here: it would join this deliberately paused worker.
	while true: OS.delay_msec(5)
