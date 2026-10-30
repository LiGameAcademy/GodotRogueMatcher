class_name RemovalSparks
extends Node2D

## Host-only adapter. The parent scene injects Board; the plugin knows no game types.
## A bounded pool consumes removal notifications without joining presentation barriers.

signal burst_played(world_position: Vector2)

const PARTICLE_SCENE: PackedScene = preload("res://addons/godot_particle_graph/visual_particles_2d.tscn")

@export var source_board: Board
@export var graph: ParticleBehaviorGraph = preload("res://gameplay/presentation/removal_sparks/hit_sparks.tres")
@export_range(1, 64) var capacity: int = 16

var _available: Array[VisualParticles2D] = []
var _active: Array[VisualParticles2D] = []
var _low_effects: bool = false

func _ready() -> void:
	for index: int in range(capacity):
		var particle: VisualParticles2D = PARTICLE_SCENE.instantiate() as VisualParticles2D
		particle.name = "Burst%d" % index
		particle.graph = graph
		particle.finished.connect(_on_finished.bind(particle))
		add_child(particle)
		_available.append(particle)
	if source_board != null:
		source_board.view.piece_removing.connect(_on_piece_removing)
		source_board.view.low_effects_changed.connect(set_low_effects)
		source_board.view.visuals_cleared.connect(clear)
		source_board.run_reset.connect(clear)
		source_board.director.playback_failed.connect(_on_playback_failed)
		source_board.director.step_skip_requested.connect(_on_step_skipped)
		set_low_effects(source_board.view.low_effects)

func set_low_effects(enabled: bool) -> void:
	_low_effects = enabled
	if enabled:
		clear()

func clear() -> void:
	for particle: VisualParticles2D in _active:
		particle.stop()
		_available.append(particle)
	_active.clear()

func active_count() -> int:
	return _active.size()

func _on_piece_removing(piece: ChessPiece) -> void:
	if _low_effects or _available.is_empty():
		return
	if source_board != null and source_board.director.skip_score_requested:
		return
	var particle: VisualParticles2D = _available.pop_back()
	particle.speed_scale = source_board.view.presentation_speed
	if not particle.play_at(piece.global_position):
		_available.append(particle)
		push_warning(particle.get_last_error())
		return
	_active.append(particle)
	burst_played.emit(piece.global_position)

func _on_finished(particle: VisualParticles2D) -> void:
	if _active.has(particle):
		_active.erase(particle)
		_available.append(particle)

func _on_playback_failed(_reason: String) -> void:
	clear()

func _on_step_skipped(_step: PresentationStep, _epoch: int, _token: int) -> void:
	clear()
