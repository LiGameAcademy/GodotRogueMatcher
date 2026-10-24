class_name RingTemplateDemo
extends RefCounted

const TEMPLATE: MatchShapeTemplate = preload("res://gameplay/board/matching/ring_template.tres")

static func populate(run: RunController, mode: String) -> void:
	var moving: bool = mode == "fixture_shape_ring_move"
	for coordinate: Vector2i in TEMPLATE.offsets:
		if moving and coordinate == Vector2i(2, 2): continue
		run.state.rules.place_piece(coordinate, 0)
	if mode == "fixture_shape_unlock_ring_center": run.state.rules.place_piece(Vector2i(1, 1), 0)
	if mode != "fixture_shape_unlock_ring_empty": run.state.rules.place_piece(Vector2i(8, 8), 1)
	if moving:
		run.state.rules.place_piece(Vector2i(2, 3), 0)
		run.state.rules.shape_unlocks.unlock(TEMPLATE, 0)
		run.state.pending_rewards = 0
	else:
		run.state.pending_rewards = 2 if mode == "fixture_shape_unlock_ring_two_rewards" else 1
