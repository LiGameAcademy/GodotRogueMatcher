extends "res://services/run_checkpoint/checkpoint_web_persistence.gd"

## Controlled asynchronous commit acknowledgements for native adapter/ownership tests.
signal release_write
var image: String = JSON.stringify({"schema": "checkpoint-web-files-v1", "files": {}})
var hold: bool = false
var fail_write: bool = false
var failure_reason: String = "web_storage_write_failed"
var writing: bool = false
var writes: int = 0

func open() -> Dictionary:
	await (Engine.get_main_loop() as SceneTree).process_frame
	return {"ok": true, "reason": "", "data": image}

func save(data: String) -> Dictionary:
	writing = true
	writes += 1
	if hold: await release_write
	else: await (Engine.get_main_loop() as SceneTree).process_frame
	writing = false
	if fail_write: return {"ok": false, "reason": failure_reason, "data": ""}
	image = data
	return {"ok": true, "reason": "", "data": ""}
