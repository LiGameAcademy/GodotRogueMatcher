extends Node

## Read-only repeated opening of the retained 476-record slot on the dedicated probe origin.
const FILES: Script = preload("res://services/run_checkpoint/checkpoint_web_files.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	if not OS.has_feature("web") or str(JavaScriptBridge.eval("window.location.origin", true)) != "http://127.0.0.1:8918":
		push_error("probe_origin_rejected")
		get_tree().quit(2)
		return
	if OS.get_cmdline_user_args() != PackedStringArray(["--profile-open"]):
		push_error("probe_arguments_rejected")
		get_tree().quit(2)
		return
	var samples: Array[Dictionary] = []
	for index: int in range(3):
		var files: FILES = FILES.new("user://profile")
		var result: Array[Dictionary] = [{}]
		var started: int = Time.get_ticks_usec()
		var frame_started: int = started
		var maximum_gap: int = 0
		_open.call_deferred(files, result)
		while result[0].is_empty():
			await get_tree().process_frame
			maximum_gap = maxi(maximum_gap, Time.get_ticks_usec() - frame_started)
			frame_started = Time.get_ticks_usec()
		var sample: Dictionary = result[0]
		sample["elapsed_usec"] = Time.get_ticks_usec() - started
		sample["maximum_gap_usec"] = maximum_gap
		sample["primary_sha256"] = files.fingerprint("user://profile/primary.json")
		sample["previous_sha256"] = files.fingerprint("user://profile/previous.json")
		sample["same_retained_pair"] = sample.primary_sha256 == "f6876b21b222bc76741fdf6d05ff3a4c6e36e69d89e4698181acb3354cdcf8cf" and sample.previous_sha256 == "ffc40724aec313f1e66847662ddebb607f9f709efa435a9521586224b6b93568"
		sample["ok"] = sample.ok and sample.same_retained_pair
		samples.append(sample)
		if not sample.ok: break
		await get_tree().process_frame
	print("O5_WEB_LONG_REPORT " + JSON.stringify({"purpose": "readonly_same_slot_open_profile", "origin": "http://127.0.0.1:8918", "samples": samples}))
	get_tree().quit()

func _open(files: FILES, result: Array[Dictionary]) -> void:
	result[0] = await files.open()
