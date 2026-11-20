extends GPUParticles2D

## Native-material particle fixture. Owns its mutable material and texture;
## inputs come from the parent verification scene, never from game state.

@export var emission_speed: float = 400.0
@export var drag: float = 0.0
@export var downward_acceleration: float = 0.0
@export var emission_spread: float = 0.0
@export var fade_enabled: bool = false
@export var fade_rgb_constant: bool = false

func _ready() -> void:
	var image: Image = Image.create(2, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	texture = ImageTexture.create_from_image(image)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	process_material = build_material()

## Generate only built-in Godot resources; no custom particle shader is used.
func build_material() -> ParticleProcessMaterial:
	var result: ParticleProcessMaterial = ParticleProcessMaterial.new()
	result.particle_flag_disable_z = true
	result.particle_flag_align_y = true
	result.direction = Vector3.RIGHT
	result.spread = emission_spread
	result.initial_velocity_min = emission_speed
	result.initial_velocity_max = emission_speed
	result.gravity = Vector3(0.0, downward_acceleration, 0.0)
	result.damping_min = drag
	result.damping_max = drag
	result.scale_min = 1.0
	result.scale_max = 1.0
	# Godot 4.7.2 samples speed / (max - min), without subtracting min.
	# Encode the authored 100..400 interval in curve knots, not native min.
	result.scale_over_velocity_min = 0.0
	result.scale_over_velocity_max = 400.0
	var axes: CurveXYZTexture = CurveXYZTexture.new()
	axes.width = 1024
	axes.curve_x = _linear_curve(1.0, 1.0)
	axes.curve_y = _speed_length_curve()
	axes.curve_z = _linear_curve(1.0, 1.0)
	result.scale_over_velocity_curve = axes
	if fade_enabled:
		var gradient: Gradient = Gradient.new()
		var ending: Color = Color(1.0, 1.0, 1.0, 0.0) if fade_rgb_constant else Color(1.0, 0.35, 0.05, 0.0)
		gradient.colors = PackedColorArray([Color.WHITE, ending])
		var ramp: GradientTexture1D = GradientTexture1D.new()
		ramp.gradient = gradient
		result.color_ramp = ramp
	return result

func _speed_length_curve() -> Curve:
	var curve: Curve = _linear_curve(1.0, 3.0)
	curve.add_point(Vector2(0.25, 1.0), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	return curve

func _linear_curve(start: float, finish: float) -> Curve:
	var curve: Curve = Curve.new()
	curve.max_value = 4.0
	curve.add_point(Vector2(0.0, start), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	curve.add_point(Vector2(1.0, finish), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	return curve
