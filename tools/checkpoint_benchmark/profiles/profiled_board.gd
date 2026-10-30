extends Board

## Test-only timings around the unchanged production methods via super.
var profile: Dictionary = {}

func _activate_run(candidate: RunController, restoring: bool) -> void:
	var started: int = Time.get_ticks_usec()
	super._activate_run(candidate, restoring)
	profile["activate_usec"] = Time.get_ticks_usec() - started

func adopt_checkpoint(candidate: RunController) -> bool:
	var started: int = Time.get_ticks_usec()
	var result: bool = super.adopt_checkpoint(candidate)
	profile["adopt_usec"] = Time.get_ticks_usec() - started
	return result
