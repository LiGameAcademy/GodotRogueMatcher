extends CanvasLayer

## Optional local FPS and worst frame display. It never changes simulation or saves.

const SAMPLE_SECONDS: float = 0.5

var _previous_usec: int = 0
var _elapsed: float = 0.0
var _worst_ms: float = 0.0

@onready var _readout: Label = $Readout

func _ready() -> void:
	set_process(false)

func _input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo or key.physical_keycode != KEY_F2: return
	visible = not visible
	_previous_usec = Time.get_ticks_usec()
	_elapsed = 0.0
	_worst_ms = 0.0
	_readout.text = "%d FPS" % Engine.get_frames_per_second()
	set_process(visible)
	get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	var now_usec: int = Time.get_ticks_usec()
	var frame_ms: float = float(now_usec - _previous_usec) / 1000.0
	_previous_usec = now_usec
	_elapsed += frame_ms / 1000.0
	_worst_ms = maxf(_worst_ms, frame_ms)
	if _elapsed < SAMPLE_SECONDS: return
	_readout.text = "%d FPS  |  Max %.1f ms" % [Engine.get_frames_per_second(), _worst_ms]
	_elapsed = 0.0
	_worst_ms = 0.0
