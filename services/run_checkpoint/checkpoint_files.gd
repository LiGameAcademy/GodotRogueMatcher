class_name CheckpointFiles
extends RefCounted

## Small synchronous file adapter. Completion is not a cross-file or power-loss guarantee.
## The store owns validation, generations and replacement order; no plugin or game state.
const MAX_BYTES: int = 16 * 1024 * 1024

func exists(path: String) -> bool:
	return FileAccess.file_exists(path)

func read_text(path: String) -> Dictionary:
	if not exists(path): return {"ok": false, "reason": "missing", "text": ""}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null: return {"ok": false, "reason": "read_failed", "text": ""}
	if file.get_length() > MAX_BYTES:
		file.close()
		return {"ok": false, "reason": "size_limit", "text": ""}
	var text: String = file.get_as_text()
	var error: Error = file.get_error()
	file.close()
	return {"ok": error == OK or error == ERR_FILE_EOF, "reason": "" if error in [OK, ERR_FILE_EOF] else "read_failed", "text": text}

func write_text(path: String, text: String) -> Error:
	if text.to_utf8_buffer().size() > MAX_BYTES: return ERR_OUT_OF_MEMORY
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if directory_error != OK: return directory_error
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	return error

func replace(source: String, destination: String) -> Error:
	return DirAccess.rename_absolute(source, destination)

func fingerprint(path: String) -> String:
	if not exists(path): return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null: return ""
	var allowed: bool = file.get_length() <= MAX_BYTES
	file.close()
	return FileAccess.get_sha256(path) if allowed else ""

## Preserve bytes rather than decoding corrupt originals as UTF-8.
func copy_verified(source: String, destination: String) -> Error:
	var before: String = fingerprint(source)
	if before.is_empty(): return ERR_CANT_OPEN
	var error: Error = DirAccess.copy_absolute(source, destination)
	if error != OK: return error
	if fingerprint(destination) != before or fingerprint(source) != before: return ERR_FILE_CORRUPT
	return OK

func remove(path: String) -> Error:
	return DirAccess.remove_absolute(path) if exists(path) else OK
