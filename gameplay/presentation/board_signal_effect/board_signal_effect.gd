class_name BoardSignalEffect
extends ColorRect

## Screen read is restricted to the board rectangle, below score floats and all HUD layers.
var phase: float = 0.0
var response: float = 0.0
var _shader: ShaderMaterial
var _config: BoardSignalConfig
var _enabled: bool = true
var _low_effects: bool = false

func _ready() -> void:
	_shader = material.duplicate() as ShaderMaterial
	material = _shader
	_sync_activity()

func _process(delta: float) -> void:
	phase = fmod(phase + delta * _config.sweep_speed, 1.0)
	response = move_toward(response, 0.0, delta * _config.response_strength / _config.response_seconds)
	_shader.set_shader_parameter("phase", phase)
	_shader.set_shader_parameter("response", response)

func apply_game_theme(preset: GameTheme) -> void:
	_config = preset.board_signal
	_shader.set_shader_parameter("signal_color", preset.board.path_color)
	_shader.set_shader_parameter("scan_strength", _config.scan_strength)
	_shader.set_shader_parameter("rim_strength", _config.rim_strength)
	_shader.set_shader_parameter("sweep_strength", _config.sweep_strength)
	reset_visual()
	_sync_activity()

func set_bounds(bounds: Rect2) -> void:
	position = bounds.position
	size = bounds.size

func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	_sync_activity()

func set_low_effects(enabled: bool) -> void:
	_low_effects = enabled
	_sync_activity()

func respond() -> void:
	if not visible: return
	response = _config.response_strength
	_shader.set_shader_parameter("response", response)

func reset_visual() -> void:
	phase = 0.0
	response = 0.0
	_shader.set_shader_parameter("phase", phase)
	_shader.set_shader_parameter("response", response)

func _sync_activity() -> void:
	visible = _enabled and not _low_effects and _config != null
	set_process(visible)
	if not visible and _shader != null:
		response = 0.0
		_shader.set_shader_parameter("response", response)
