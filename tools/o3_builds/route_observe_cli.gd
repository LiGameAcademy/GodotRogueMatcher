extends SceneTree

## Autoload-safe post-acquisition window scan. Facts only; pass_line stays null.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var target: int = 30
	var max_scan: int = 100
	var start_seed: int = 13000
	var move_limit: int = 120
	var prefer_complete: bool = false
	var target_mode: String = "acquired"
	var moves_explicit: bool = false
	var target_explicit: bool = false
	var max_scan_explicit: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--target="):
			target = arg.trim_prefix("--target=").to_int()
			target_explicit = true
		elif arg.begins_with("--max-scan="):
			max_scan = arg.trim_prefix("--max-scan=").to_int()
			max_scan_explicit = true
		elif arg.begins_with("--seed="): start_seed = arg.trim_prefix("--seed=").to_int()
		elif arg.begins_with("--moves="):
			move_limit = arg.trim_prefix("--moves=").to_int()
			moves_explicit = true
		elif arg == "--complete-windows": prefer_complete = true
		elif arg == "--target-resolved":
			target_mode = "resolved"
			prefer_complete = true
	if target_mode == "resolved":
		if not target_explicit: target = 10
		if not max_scan_explicit: max_scan = 300
		if not moves_explicit: move_limit = 240
	elif prefer_complete and not moves_explicit:
		move_limit = 240
	if target <= 0 or max_scan <= 0 or target > max_scan or move_limit <= 0:
		push_error("Invalid O3 observe bounds")
		quit(2)
		return
	var batch: Dictionary = O3RouteObserve.run_batch(target, max_scan, start_seed, move_limit, prefer_complete, target_mode)
	var directory: String = OS.get_environment("O3_EVIDENCE_DIR")
	if directory.is_empty(): directory = "res://.godot/o3-observe"
	DirAccess.make_dir_recursive_absolute(directory)
	var filename: String = "route-observe-summary.json"
	if target_mode == "resolved": filename = "route-observe-resolved.json"
	elif prefer_complete: filename = "route-observe-complete.json"
	var path: String = directory.path_join(filename)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write %s" % path)
		quit(1)
		return
	file.store_string(JSON.stringify(RunSnapshot.normalize({
		"target": batch.target, "max_scan": batch.max_scan, "start_seed": batch.start_seed,
		"move_limit": batch.move_limit, "prefer_complete": batch.prefer_complete,
		"target_mode": batch.target_mode, "pass_line": batch.pass_line, "failures": batch.failures,
		"by_route": batch.by_route, "note": batch.note, "purpose": batch.purpose
	}), "\t", true) + "\n")
	file.flush()
	print("O3_OBSERVE ", JSON.stringify({"path": path, "prefer_complete": prefer_complete,
		"target_mode": target_mode, "failures": (batch.failures as Array).size(),
		"by_route": batch.by_route}))
	quit(0 if (batch.failures as Array).is_empty() else 1)
