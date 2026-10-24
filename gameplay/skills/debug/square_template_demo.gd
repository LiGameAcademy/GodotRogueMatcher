class_name SquareTemplateDemo
extends RefCounted

const TEMPLATE: MatchShapeTemplate = preload("res://gameplay/board/matching/square_template.tres")

static func populate(run: RunController, mode: String) -> void:
	var moving: bool = mode == "fixture_shape_square_move"
	for coordinate: Vector2i in TEMPLATE.offsets:
		if moving and coordinate == Vector2i(2, 2): continue
		run.state.rules.place_piece(coordinate, 1 if mode == "fixture_shape_unlock_square_center" and coordinate == Vector2i(1, 1) else 0)

	if mode != "fixture_shape_unlock_square_empty": run.state.rules.place_piece(Vector2i(8, 8), 1)
	if moving:
		run.state.rules.place_piece(Vector2i(2, 3), 0)
		run.state.rules.shape_unlocks.unlock(TEMPLATE, 0)
		run.state.pending_rewards = 0
	else:
		run.state.pending_rewards = 2 if mode == "fixture_shape_unlock_square_two_rewards" else 1
