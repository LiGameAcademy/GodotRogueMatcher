extends Node2D

## Fresh-process graphical check: reopen the saved graph/scene, then exercise
## the real Game removal event. Artifacts contain results, not rule mutations.

const OUTPUT: String = "res://.godot/particle_graph_thin"

var _failures: Array[String] = []
var _restored: Node2D
var _light: VisualParticles2D
var _heavy: VisualParticles2D
var _burst_events: int = 0
var _capture_queued: bool = false
var _game_phase: bool = false
var _frames: int = 0
var _summary: Dictionary = {}

@onready var _game: Node2D = $Game
@onready var _hud_layer: CanvasLayer = $Game/UILayer

func _ready() -> void:
	get_window().title = "Particle Graph - graph resource and override roundtrip"
	get_window().size = Vector2i(1280, 720)
	RenderingServer.set_default_clear_color(Color.BLACK)
	# CanvasLayer visibility does not inherit the hidden Game CanvasItem.
	_hud_layer.hide()
	if DisplayServer.get_name() == "headless":
		push_error("Use a real rendering window for this verification.")
		get_tree().quit(2)
		return
	if not _reopen_scene():
		_finish()
		return
	await get_tree().process_frame
	_light.play_at(Vector2(350, 290), Vector2.UP)
	_heavy.play_at(Vector2(880, 290), Vector2.UP)
	for frame: int in range(12):
		await get_tree().process_frame
	await _capture("reopened_overrides")
	await _exercise_game()
	_finish()

func _process(_delta: float) -> void:
	_frames += 1
	if _frames > 1800:
		_failures.append("verification_timeout")
		_finish()

func _draw() -> void:
	if _game_phase:
		return
	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(35, 45), "Fresh process: one shared graph, independent overrides", HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
	draw_string(font, Vector2(210, 390), "Light: 12 / 100..400 / max 12 px", HORIZONTAL_ALIGNMENT_LEFT, -1, 19)
	draw_string(font, Vector2(720, 390), "Heavy: 24 / 150..600 / max 18 px", HORIZONTAL_ALIGNMENT_LEFT, -1, 19)
	draw_string(font, Vector2(35, 470), "No graph editor. Materials are rebuilt from the saved graph and node properties.", HORIZONTAL_ALIGNMENT_LEFT, -1, 18)

func _reopen_scene() -> bool:
	var path: String = OUTPUT.path_join("saved_particles.tscn")
	var scene: PackedScene = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if scene == null:
		_failures.append("saved_scene_missing_run_tests_first")
		return false
	_restored = scene.instantiate() as Node2D
	add_child(_restored)
	_light = _restored.get_node("Light") as VisualParticles2D
	_heavy = _restored.get_node("Heavy") as VisualParticles2D
	var light_material: ParticleProcessMaterial = _light.process_material as ParticleProcessMaterial
	var heavy_material: ParticleProcessMaterial = _heavy.process_material as ParticleProcessMaterial
	if _light.graph != _heavy.graph or _light.amount != 12 or _heavy.amount != 24:
		_failures.append("saved_overrides_not_restored")
	if light_material == null or heavy_material == null or light_material == heavy_material:
		_failures.append("generated_materials_not_independent")
	_summary["reopened"] = {
		"shared_graph": _light.graph == _heavy.graph,
		"light_amount": _light.amount,
		"heavy_amount": _heavy.amount,
		"light_speed": _light.graph.speed_range,
		"heavy_speed_override": _heavy.speed_range_value,
		"heavy_length_override": _heavy.length_max_value
	}
	return _failures.is_empty()

func _exercise_game() -> void:
	_restored.hide()
	_game_phase = true
	_game.show()
	_hud_layer.show()
	queue_redraw()
	var board: Board = _game.get_node("Board") as Board
	while not board.can_selected:
		await get_tree().process_frame
	var sparks: RemovalSparks = _game.get_node("RemovalSparks") as RemovalSparks
	sparks.burst_played.connect(_on_burst_played)
	if not board.load_explosion_demo():
		_failures.append("host_fixture_failed")
		return
	board.selected_piece = board.get_cell(Vector2i(5, 5)).piece
	if not await board.move_selected_piece(board.get_cell(Vector2i(5, 4)), 0.01):
		_failures.append("host_action_failed")
	var digest: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	if GameManager.score != 70 or _burst_events == 0 or board.view.is_presenting():
		_failures.append("host_feedback_or_rule_result_failed")
	await _capture("game_after_action")
	board.view.set_low_effects(true)
	if sparks.active_count() != 0:
		_failures.append("low_effects_did_not_clear")
	if RunSnapshot.digest(RunSnapshot.capture(board.run)) != digest:
		_failures.append("cosmetic_policy_changed_rule_state")
	_summary["host"] = {"burst_events": _burst_events, "score": GameManager.score, "rule_digest": digest}
	await _capture("low_effects_cleared")

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var error: Error = get_viewport().get_texture().get_image().save_png(OUTPUT.path_join(label + ".png"))
	if error != OK:
		_failures.append("capture_failed:" + label)

func _finish() -> void:
	_summary["engine"] = Engine.get_version_info()
	_summary["renderer_configured"] = ProjectSettings.get_setting("rendering/renderer/rendering_method")
	_summary["failures"] = _failures
	var file: FileAccess = FileAccess.open(OUTPUT.path_join("smoke.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_summary, "\t") + "\n")
	else:
		_failures.append("report_write_failed")
	print("PARTICLE_GRAPH_THIN_FINISHED failures=", _failures)
	get_tree().quit(0 if _failures.is_empty() else 1)

func _on_burst_played(_position: Vector2) -> void:
	_burst_events += 1
	if not _capture_queued:
		_capture_queued = true
		_capture_game_burst()

func _capture_game_burst() -> void:
	for frame: int in range(3):
		await get_tree().process_frame
	await _capture("game_burst")
