extends SceneTree

## Autoload-safe O3 route smoke entry. Facts only; does not judge balance.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var per_route: int = 10
	var start_seed: int = 9200
	var move_limit: int = 60
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--per-route="): per_route = arg.trim_prefix("--per-route=").to_int()
		elif arg.begins_with("--seed="): start_seed = arg.trim_prefix("--seed=").to_int()
		elif arg.begins_with("--moves="): move_limit = arg.trim_prefix("--moves=").to_int()
	if per_route <= 0 or per_route > 100 or move_limit <= 0:
		push_error("Invalid O3 smoke bounds")
		quit(2)
		return
	var batch: Dictionary = O3RouteSmoke.run_batch(per_route, start_seed, move_limit)
	var directory: String = OS.get_environment("O3_EVIDENCE_DIR")
	if directory.is_empty(): directory = "res://.godot/o3-smoke"
	DirAccess.make_dir_recursive_absolute(directory)
	var path: String = directory.path_join("route-smoke-summary.json")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write %s" % path)
		quit(1)
		return
	file.store_string(JSON.stringify(RunSnapshot.normalize({
		"per_route": batch.per_route, "start_seed": batch.start_seed, "move_limit": batch.move_limit,
		"games": batch.games, "failures": batch.failures, "by_route": batch.by_route
	}), "\t", true) + "\n")
	file.flush()
	print("O3_SMOKE ", JSON.stringify({"games": batch.games, "failures": (batch.failures as Array).size(),
		"path": path, "by_route": batch.by_route}))
	quit(0 if (batch.failures as Array).is_empty() else 1)
