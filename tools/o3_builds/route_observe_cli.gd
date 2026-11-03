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
	var moves_explicit: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--target="): target = arg.trim_prefix("--target=").to_int()
		elif arg.begins_with("--max-scan="): max_scan = arg.trim_prefix("--max-scan=").to_int()
		elif arg.begins_with("--seed="): start_seed = arg.trim_prefix("--seed=").to_int()
		elif arg.begins_with("--moves="):
			move_limit = arg.trim_prefix("--moves=").to_int()
			moves_explicit = true
		elif arg == "--complete-windows": prefer_complete = true
	if prefer_complete and not moves_explicit:
		move_limit = 240
	if target <= 0 or max_scan <= 0 or target > max_scan or move_limit <= 0:
		push_error("Invalid O3 observe bounds")
		quit(2)
		return
	var batch: Dictionary = O3RouteObserve.run_batch(target, max_scan, start_seed, move_limit, prefer_complete)
	var directory: String = OS.get_environment("O3_EVIDENCE_DIR")
	if directory.is_empty(): directory = "res://.godot/o3-observe"
	DirAccess.make_dir_recursive_absolute(directory)
	var filename: String = "route-observe-complete.json" if prefer_complete else "route-observe-summary.json"
	var path: String = directory.path_join(filename)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write %s" % path)
		quit(1)
		return
	file.store_string(JSON.stringify(RunSnapshot.normalize({
		"target": batch.target, "max_scan": batch.max_scan, "start_seed": batch.start_seed,
		"move_limit": batch.move_limit, "prefer_complete": batch.prefer_complete,
		"pass_line": batch.pass_line, "failures": batch.failures,
		"by_route": batch.by_route, "note": batch.note
	}), "\t", true) + "\n")
	file.flush()
	print("O3_OBSERVE ", JSON.stringify({"path": path, "prefer_complete": prefer_complete,
		"failures": (batch.failures as Array).size(), "by_route": batch.by_route}))
	quit(0 if (batch.failures as Array).is_empty() else 1)
