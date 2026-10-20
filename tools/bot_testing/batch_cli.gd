extends SceneTree

## Autoload安装后才解析批测依赖，避免CoreSystem提前解析失败。
func _initialize() -> void:
	_start_job.call_deferred()

func _start_job() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var script: Script = load("res://tools/bot_testing/paired_job.gd" if args.size() > 0 and args[0] == "paired" else "res://tools/bot_testing/batch_job.gd") as Script
	if script == null or not script.can_instantiate():
		push_error("Cannot load bot batch job")
		quit(1)
		return
	var job: Node = script.new() as Node
	root.add_child(job)
