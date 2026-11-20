extends GutTest

## Runtime resource/override tests; graphical behavior is checked by the smoke scene.

const PARTICLES: PackedScene = preload("res://addons/godot_particle_graph/visual_particles_2d.tscn")
const GAME: PackedScene = preload("res://gameplay/game.tscn")
const OUTPUT: String = "res://.godot/particle_graph_thin"

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false

func after_each() -> void:
	get_tree().paused = false
	UIManager.close_popup()
	await wait_process_frames(2)

func test_shared_graph_overrides_and_nested_resources_are_independent() -> void:
	var graph: ParticleBehaviorGraph = ParticleBehaviorGraph.new()
	var light: VisualParticles2D = _particle(graph)
	var heavy: VisualParticles2D = _particle(graph)
	heavy.override_amount = true
	heavy.amount_value = 24
	heavy.override_speed_range = true
	heavy.speed_range_value = Vector2(150, 600)
	heavy.override_length_max = true
	heavy.length_max_value = 18.0
	assert_true(heavy.rebuild())
	assert_eq(light.amount, 12)
	assert_eq(heavy.amount, 24)
	assert_eq(graph.amount, 12)
	assert_eq(graph.speed_range, Vector2(100, 400))
	assert_eq(graph.length_max, 12.0)
	var light_material: ParticleProcessMaterial = light.process_material as ParticleProcessMaterial
	var heavy_material: ParticleProcessMaterial = heavy.process_material as ParticleProcessMaterial
	assert_ne(light_material, heavy_material)
	assert_eq(heavy_material.scale_over_velocity_max, 600.0)
	var light_axes: CurveXYZTexture = light_material.scale_over_velocity_curve as CurveXYZTexture
	var heavy_axes: CurveXYZTexture = heavy_material.scale_over_velocity_curve as CurveXYZTexture
	heavy_axes.curve_y.set_point_value(2, 5.0)
	assert_eq(light_axes.curve_y.get_point_position(2).y, 3.0)
	var heavy_ramp: GradientTexture1D = heavy_material.color_ramp as GradientTexture1D
	heavy_ramp.gradient.set_color(0, Color.BLUE)
	assert_eq(graph.color_gradient.get_color(0), Color.WHITE)
	graph.amount = 18
	await wait_process_frames(2)
	assert_eq(light.amount, 18)
	assert_eq(heavy.amount, 24)

func test_nested_gradient_changes_rebuild_and_replacement_disconnects_old_gradient() -> void:
	var graph: ParticleBehaviorGraph = ParticleBehaviorGraph.new()
	var particle: VisualParticles2D = _particle(graph)
	var original: Gradient = graph.color_gradient
	original.set_color(0, Color.RED)
	await wait_process_frames(2)
	var material: ParticleProcessMaterial = particle.process_material as ParticleProcessMaterial
	assert_eq((material.color_ramp as GradientTexture1D).gradient.get_color(0), Color.RED)
	var replacement: Gradient = Gradient.new()
	graph.color_gradient = replacement
	await wait_process_frames(2)
	watch_signals(graph)
	original.set_color(0, Color.BLUE)
	assert_signal_not_emitted(graph, "changed")
	replacement.set_color(0, Color.GREEN)
	await wait_process_frames(2)
	assert_signal_emitted(graph, "changed")
	material = particle.process_material as ParticleProcessMaterial
	assert_eq((material.color_ramp as GradientTexture1D).gradient.get_color(0), Color.GREEN)
	assert_eq(original.get_color(0), Color.BLUE)

func test_invalid_parameters_stop_playback_and_report_a_specific_error() -> void:
	var particle: VisualParticles2D = _particle(ParticleBehaviorGraph.new())
	particle.override_speed_range = true
	particle.speed_range_value = Vector2(200, 200)
	assert_false(particle.play())
	assert_string_contains(particle.get_last_error(), "Reference speed range")
	assert_null(particle.process_material)
	assert_false(particle.emitting)
	particle.speed_range_value = Vector2(150, 600)
	assert_true(particle.play())
	assert_eq(particle.get_last_error(), "")
	assert_false(particle.play_at(Vector2(NAN, 0)))
	particle.stop()

func test_reference_link_can_be_fixed_without_mutating_the_graph() -> void:
	var graph: ParticleBehaviorGraph = ParticleBehaviorGraph.new()
	graph.reference_follows_speed = false
	var particle: VisualParticles2D = _particle(graph)
	particle.override_speed_range = true
	particle.speed_range_value = Vector2(150, 600)
	assert_true(particle.rebuild())
	var material: ParticleProcessMaterial = particle.process_material as ParticleProcessMaterial
	assert_eq(material.initial_velocity_max, 600.0)
	assert_eq(material.scale_over_velocity_max, 400.0)
	assert_eq(graph.speed_range, Vector2(100, 400))

func test_graph_and_scene_roundtrip_exclude_generated_materials() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var graph_path: String = OUTPUT.path_join("shared_graph.tres")
	var graph: ParticleBehaviorGraph = ParticleBehaviorGraph.new()
	assert_eq(ResourceSaver.save(graph, graph_path), OK)
	var stored: ParticleBehaviorGraph = ResourceLoader.load(graph_path, "", ResourceLoader.CACHE_MODE_IGNORE) as ParticleBehaviorGraph
	var root: Node2D = Node2D.new()
	root.name = "SavedParticles"
	add_child_autofree(root)
	for index: int in range(2):
		var particle: VisualParticles2D = PARTICLES.instantiate() as VisualParticles2D
		particle.name = "Light" if index == 0 else "Heavy"
		particle.graph = stored
		particle.override_amount = index == 1
		particle.amount_value = 24
		particle.override_speed_range = index == 1
		particle.speed_range_value = Vector2(150, 600)
		particle.override_length_max = index == 1
		particle.length_max_value = 18.0
		root.add_child(particle)
		particle.owner = root
	var scene: PackedScene = PackedScene.new()
	assert_eq(scene.pack(root), OK)
	var path: String = OUTPUT.path_join("saved_particles.tscn")
	assert_eq(ResourceSaver.save(scene, path), OK)
	var text: String = FileAccess.get_file_as_string(path)
	assert_false(text.contains("process_material"))
	assert_false(text.contains("ParticleProcessMaterial"))
	var reloaded: PackedScene = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var instance: Node2D = reloaded.instantiate() as Node2D
	add_child_autofree(instance)
	assert_eq((instance.get_node("Light") as VisualParticles2D).amount, 12)
	assert_eq((instance.get_node("Heavy") as VisualParticles2D).amount, 24)

func test_game_adapter_consumes_real_feedback_and_preserves_policy() -> void:
	var game: Node2D = GAME.instantiate() as Node2D
	game.set("persist_preferences", false)
	game.set("record_runs", false)
	game.set("collect_telemetry", false)
	game.set("show_start_menu", false)
	add_child_autofree(game)
	var board: Board = game.get_node("Board") as Board
	await board.initialized
	var sparks: RemovalSparks = game.get_node("RemovalSparks") as RemovalSparks
	watch_signals(sparks)
	assert_eq(sparks.source_board, board)
	assert_true(board.load_explosion_demo())
	board.selected_piece = board.get_cell(Vector2i(5, 5)).piece
	assert_true(await board.move_selected_piece(board.get_cell(Vector2i(5, 4)), 0.01))
	assert_signal_emitted(sparks, "burst_played")
	var expected: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	assert_eq(GameManager.score, 70)
	assert_false(board.view.is_presenting())
	board.view.set_low_effects(true)
	assert_eq(sparks.active_count(), 0)
	var count: int = get_signal_emit_count(sparks, "burst_played")
	var display_piece: ChessPiece = board.view.get_piece(board.rules.state.get_snapshot()[0].piece_id)
	board.view.piece_removing.emit(display_piece)
	assert_eq(get_signal_emit_count(sparks, "burst_played"), count)
	board.view.set_low_effects(false)
	board.view.piece_removing.emit(display_piece)
	assert_gt(sparks.active_count(), 0)
	board.director.skip_score_requested = true
	count = get_signal_emit_count(sparks, "burst_played")
	board.view.piece_removing.emit(display_piece)
	assert_eq(get_signal_emit_count(sparks, "burst_played"), count)
	board.director.skip_score_requested = false
	board.view.cancel_animations()
	assert_eq(sparks.active_count(), 0)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), expected)

func _particle(graph: ParticleBehaviorGraph) -> VisualParticles2D:
	var particle: VisualParticles2D = PARTICLES.instantiate() as VisualParticles2D
	particle.graph = graph
	add_child_autofree(particle)
	return particle
