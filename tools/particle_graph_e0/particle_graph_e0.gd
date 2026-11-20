extends Node2D

## E0 visual experiment inside the real host project. It observes rendered pixels
## and the existing BoardView signal without installing a plugin or changing rules.

const SPARK: Script = preload("res://tools/particle_graph_e0/spark_probe.gd")
const SPARK_SCENE: PackedScene = preload("res://tools/particle_graph_e0/spark_probe.tscn")
const SPEEDS: Array[float] = [100.0, 250.0, 400.0, 400.0]
const SAMPLE_FRAMES: Array[int] = [12, 48, 84]

var _output: String = "res://.godot/particle_graph_e0"
var _probes: Array[SPARK] = []
var _samples: Array[Dictionary] = []
var _failures: Array[String] = []
var _event_count: int = 0
var _event_origin: Vector2 = Vector2.ZERO
var _start_usec: int = 0
var _event_phase: bool = false

@onready var _rows: Node2D = $ProbeRows
@onready var _board: BoardView = $BoardView

func _ready() -> void:
	get_window().title = "Particle Graph E0 - native Compatibility probe"
	get_window().size = Vector2i(1280, 720)
	RenderingServer.set_default_clear_color(Color.BLACK)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--e0-output="):
			_output = argument.trim_prefix("--e0-output=")
	if DisplayServer.get_name() == "headless":
		push_error("E0 requires a real rendering window, not headless rendering.")
		get_tree().quit(2)
		return
	var error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
	if error != OK:
		push_error(error_string(error))
		get_tree().quit(2)
		return
	_create_probes()
	await get_tree().process_frame
	_check_resource_roundtrip()
	_check_resource_isolation()
	_start_usec = Time.get_ticks_usec()
	for probe: SPARK in _probes:
		probe.restart()
	var frame: int = 0
	for target_frame: int in SAMPLE_FRAMES:
		while frame < target_frame:
			await get_tree().process_frame
			frame += 1
		await _capture("frame_%03d" % target_frame, frame)
	await _verify_removal_event()
	_write_results()
	print("PARTICLE_GRAPH_E0_FINISHED failures=", _failures)
	get_tree().quit(0 if _failures.is_empty() else 1)

func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(30, 42), "E0 / native ParticleProcessMaterial / Compatibility", HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
	if _event_phase:
		draw_string(font, Vector2(30, 95), "Real BoardView.piece_removing signal -> native spark burst", HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
		return
	var labels: Array[String] = ["100 px/s", "250 px/s", "400 px/s", "400, drag 300"]
	for index: int in range(labels.size()):
		draw_string(font, Vector2(30, 145 + index * 80), labels[index], HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	draw_string(font, Vector2(30, 465), "250 + fade", HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	draw_string(font, Vector2(30, 545), "250 reloaded", HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	draw_string(font, Vector2(930, 85), "100 + gravity", HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	draw_string(font, Vector2(30, 640), "White rows: expected lengths 4 / 8 / 12 px; constant width 2 px.", HORIZONTAL_ALIGNMENT_LEFT, -1, 18)

func _create_probes() -> void:
	for index: int in range(SPEEDS.size()):
		var probe: SPARK = _add_probe(Vector2(200, 140 + index * 80), SPEEDS[index])
		if index == 3:
			var material: ParticleProcessMaterial = probe.process_material as ParticleProcessMaterial
			material.damping_min = 300.0
			material.damping_max = 300.0
	var fading: SPARK = _add_probe(Vector2(200, 460), 250.0)
	fading.fade_enabled = true
	fading.fade_rgb_constant = true
	fading.process_material = fading.build_material()
	var gravity_probe: SPARK = _add_probe(Vector2(980, 140), 100.0)
	gravity_probe.downward_acceleration = 160.0
	gravity_probe.process_material = gravity_probe.build_material()

func _add_probe(origin: Vector2, speed: float) -> SPARK:
	var probe: SPARK = SPARK_SCENE.instantiate() as SPARK
	probe.position = origin
	probe.emission_speed = speed
	_rows.add_child(probe)
	_probes.append(probe)
	return probe

func _check_resource_roundtrip() -> void:
	var path: String = _output.path_join("native_material.tres")
	var error: Error = ResourceSaver.save(_probes[1].process_material, path)
	if error != OK:
		_failures.append("material_save_failed")
		return
	var loaded: ParticleProcessMaterial = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ParticleProcessMaterial
	if loaded == null or not loaded.scale_over_velocity_curve is CurveXYZTexture:
		_failures.append("material_reload_failed")
		return
	var probe: SPARK = _add_probe(Vector2(200, 540), 250.0)
	probe.process_material = loaded

func _check_resource_isolation() -> void:
	var original: ParticleProcessMaterial = _probes[2].process_material as ParticleProcessMaterial
	var copied: ParticleProcessMaterial = original.duplicate(true) as ParticleProcessMaterial
	var copied_axes: CurveXYZTexture = copied.scale_over_velocity_curve as CurveXYZTexture
	var original_axes: CurveXYZTexture = original.scale_over_velocity_curve as CurveXYZTexture
	copied_axes.curve_y.set_point_value(copied_axes.curve_y.point_count - 1, 4.0)
	if not is_equal_approx(original_axes.curve_y.get_point_position(original_axes.curve_y.point_count - 1).y, 3.0):
		_failures.append("nested_curve_isolation_failed")
	if _probes[0].process_material == _probes[1].process_material:
		_failures.append("instances_share_mutable_material")

func _capture(label: String, frame: int) -> void:
	await RenderingServer.frame_post_draw
	var path: String = _output.path_join(label + ".png")
	var error: Error = get_viewport().get_texture().get_image().save_png(path)
	if error != OK:
		_failures.append("capture_failed:" + label)
	_samples.append({"label": label, "frame": frame, "elapsed_seconds": (Time.get_ticks_usec() - _start_usec) / 1000000.0})

func _verify_removal_event() -> void:
	_event_phase = true
	_rows.hide()
	_board.show()
	_board.configure(1, 1, Vector2(48, 48), Vector2.ZERO)
	var source: PieceState = PieceState.new()
	source.piece_id = 991
	source.coordinate = Vector2i.ZERO
	source.match_color = 0
	_board.rebuild([source])
	_board.piece_removing.connect(_on_piece_removing)
	queue_redraw()
	await get_tree().process_frame
	_board.remove_piece(source, false)
	if _event_count != 1 or not _event_origin.is_equal_approx(_board.global_position):
		_failures.append("removal_event_origin_failed")
	if source.piece_id != 991 or source.coordinate != Vector2i.ZERO or source.match_color != 0:
		_failures.append("presentation_changed_source_snapshot")
	for frame: int in range(12):
		await get_tree().process_frame
	await _capture("removal_event", -1)

func _write_results() -> void:
	var report: Dictionary = {
		"engine": Engine.get_version_info(),
		"configured_renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"display_driver": DisplayServer.get_name(),
		"samples": _samples,
		"removal_signal_count": _event_count,
		"removal_origin": {"x": _event_origin.x, "y": _event_origin.y},
		"failures": _failures,
		"shader_path": "native ParticleProcessMaterial only"
	}
	var file: FileAccess = FileAccess.open(_output.path_join("run.json"), FileAccess.WRITE)
	if file == null:
		_failures.append("report_write_failed")
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")

func _on_piece_removing(piece: ChessPiece) -> void:
	_event_count += 1
	_event_origin = piece.global_position
	var burst: SPARK = SPARK_SCENE.instantiate() as SPARK
	burst.position = to_local(_event_origin)
	burst.amount = 12
	burst.lifetime = 0.8
	burst.emission_speed = 400.0
	burst.emission_spread = 180.0
	burst.downward_acceleration = 160.0
	burst.fade_enabled = true
	add_child(burst)
	burst.restart()
