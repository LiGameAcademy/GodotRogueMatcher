class_name GameBackground
extends ColorRect

## Decorative only: explicit theme/score inputs, independent shader instance and clock.
var phase: float = 0.0
var response: float = 0.0
var _shader: ShaderMaterial
var _config: BackgroundFlowConfig
var _motion_enabled: bool = true
var _low_effects: bool = false

func _ready() -> void:
	_shader = material.duplicate() as ShaderMaterial
	material = _shader
	resized.connect(_resize_shader)
	set_process(false)

func _process(delta: float) -> void:
	phase = fmod(phase + delta * _config.speed, TAU * 10.0)
	response = move_toward(response, 0.0, delta * _config.score_response / _config.response_seconds)
	_shader.set_shader_parameter("phase", phase)
	_shader.set_shader_parameter("response", response)

func apply_game_theme(preset: GameTheme) -> void:
	_config = preset.background_flow
	color = preset.background
	_shader.set_shader_parameter("base_color", preset.background)
	_shader.set_shader_parameter("flow_color", preset.ui_theme.get_color("accent", "Game"))
	_shader.set_shader_parameter("second_color", preset.ui_theme.get_color("rarity_3", "Game"))
	_shader.set_shader_parameter("strength", _config.contrast)
	response = 0.0
	_shader.set_shader_parameter("response", response)
	_resize_shader()
	_sync_activity()

func set_motion_enabled(enabled: bool) -> void:
	_motion_enabled = enabled
	_sync_activity()

func set_low_effects(enabled: bool) -> void:
	_low_effects = enabled
	_sync_activity()

func respond_to_score(amount: int) -> void:
	if not is_processing() or amount <= 0: return
	# Bounded accumulation prevents long chains from turning into full-screen flashes.
	response = minf(_config.score_response, response + _config.score_response * minf(1.0, amount / _config.reference_score))
	_shader.set_shader_parameter("response", response)

func reset_visual() -> void:
	phase = 0.0
	response = 0.0
	_shader.set_shader_parameter("phase", phase)
	_shader.set_shader_parameter("response", response)

func _sync_activity() -> void:
	var active: bool = _motion_enabled and not _low_effects and _config != null
	material = _shader if active else null
	set_process(active)
	if not active:
		response = 0.0
		_shader.set_shader_parameter("response", 0.0)

func _resize_shader() -> void:
	_shader.set_shader_parameter("aspect", size.x / maxf(1.0, size.y))
