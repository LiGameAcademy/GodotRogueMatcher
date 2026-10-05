class_name TelemetryClock
extends RefCounted

var category: String = "busy"
var times: Dictionary[String, int] = {"pause": 0, "choice": 0, "busy": 0, "input": 0, "inactive": 0}
var _clock: Callable
var _origin: int
var _start: int = 0
var _elapsed: int = 0

func _init(clock: Callable = Callable()) -> void:
	_clock = clock if clock.is_valid() else Time.get_ticks_msec
	_origin = int(_clock.call())

func elapsed() -> int:
	_elapsed = maxi(_elapsed, int(_clock.call()) - _origin)
	return _elapsed

func time_source() -> Callable:
	return _clock

func change(next: String) -> Dictionary:
	var end: int = elapsed()
	var result: Dictionary = {"category": category, "start_ms": _start, "end_ms": end, "duration_ms": end - _start}
	times[category] += end - _start
	_start = end
	category = next
	return result
