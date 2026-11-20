extends "res://services/telemetry/web_telemetry_persistence.gd"

## Native transaction-control fixture, not evidence of actual browser persistence.
signal release_write
var stored: Dictionary = {}
var hold: bool = false
var fail_write: bool = false
var fail_prefix: String = ""
var writing: bool = false

func open() -> Dictionary:
	await (Engine.get_main_loop() as SceneTree).process_frame
	return {"ok": true, "reason": "", "data": JSON.stringify(stored)}

func snapshot() -> Dictionary:
	await (Engine.get_main_loop() as SceneTree).process_frame
	return {"ok": true, "reason": "", "data": JSON.stringify(stored)}

func append(name: String, revision: int, text: String) -> Dictionary:
	assert(not writing)
	writing = true
	if hold: await release_write
	else: await (Engine.get_main_loop() as SceneTree).process_frame
	writing = false
	if fail_write and name.begins_with(fail_prefix): return {"ok": false, "reason": "web_telemetry_write_failed", "data": ""}
	var previous: Dictionary = stored.get(name, {"revision": 0, "text": ""})
	if int(previous.revision) != revision: return {"ok": false, "reason": "web_telemetry_conflict", "data": ""}
	stored[name] = {"schema": "web-collection-file-v1", "revision": revision + 1, "text": String(previous.text) + text}
	return {"ok": true, "reason": "", "data": ""}
