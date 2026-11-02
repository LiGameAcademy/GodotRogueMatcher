extends SceneTree

## Defers analysis dependency parsing until Autoloads are ready, as the batch CLI does.
func _initialize() -> void:
	_start_job.call_deferred()

func _start_job() -> void:
	# A runtime load is intentional: preloading the report graph can break resource typing.
	var script: Script = load("res://tools/telemetry_analysis/analysis_job.gd") as Script
	if script == null or not script.can_instantiate():
		push_error("Cannot load telemetry analysis job")
		quit(1)
		return
	var job: Node = script.new() as Node
	root.add_child(job)
