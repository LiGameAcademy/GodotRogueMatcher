extends SceneTree

## Emits a #161 portable seed vector for desktop/Web comparison. Does not run gameplay.
## Usage: godot --headless --path . -s tools/seed_vector/seed_vector_cli.gd -- [master_seed] [draws]
const VECTOR: Script = preload("res://services/run_random/seed_portable_vector.gd")

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var master: int = 42
	var draws: int = VECTOR.DEFAULT_DRAWS
	if args.size() >= 1 and args[0].is_valid_int() and str(args[0].to_int()) == args[0] and args[0].to_int() >= 0:
		master = args[0].to_int()
	elif args.size() >= 1:
		push_error("master_seed must be a nonnegative decimal integer string")
		quit(2)
		return
	if args.size() >= 2 and args[1].is_valid_int() and str(args[1].to_int()) == args[1] and args[1].to_int() >= 0:
		draws = args[1].to_int()
	elif args.size() >= 2:
		push_error("draws must be a nonnegative decimal integer string")
		quit(2)
		return
	print(JSON.stringify(VECTOR.build(master, draws)))
	quit(0)
