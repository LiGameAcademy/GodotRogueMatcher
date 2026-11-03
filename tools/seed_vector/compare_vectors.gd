extends SceneTree

const VECTOR: Script = preload("res://services/run_random/seed_portable_vector.gd")

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: compare_vectors.gd -- expected.json actual.json")
		quit(2)
		return
	var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var actual: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	if not expected is Dictionary or not actual is Dictionary:
		push_error("invalid json")
		quit(2)
		return
	var mismatch: String = VECTOR.gameplay_mismatch(expected, actual)
	print("mismatch=", mismatch if not mismatch.is_empty() else "OK")
	print("expected_platform=", expected.get("platform", ""))
	print("actual_platform=", actual.get("platform", ""))
	quit(0 if mismatch.is_empty() else 1)
