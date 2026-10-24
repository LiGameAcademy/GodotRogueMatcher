class_name UTemplateDemo
extends RefCounted

const TEMPLATE: MatchShapeTemplate = preload("res://gameplay/board/matching/u_template.tres")

## Named fixtures exercise the same real unlock and movement commands as production.
static func populate(run: RunController, mode: String) -> void:
	var rotated: bool = mode == "fixture_shape_unlock_u_rotated"
	var moving: bool = mode == "fixture_shape_u_move"
	for source: Vector2i in TEMPLATE.offsets:
		var coordinate: Vector2i = Vector2i(2 - source.y, source.x) if rotated else source
		if moving and coordinate == Vector2i(2, 2): continue
		run.state.rules.place_piece(coordinate, 0)
	if mode != "fixture_shape_unlock_u_empty": run.state.rules.place_piece(Vector2i(8, 8), 1)
	if moving:
		run.state.rules.place_piece(Vector2i(2, 3), 0)
		run.state.rules.shape_unlocks.unlock(TEMPLATE, 0)
		run.state.pending_rewards = 0
	else:
		run.state.pending_rewards = 2 if mode == "fixture_shape_unlock_u_two_rewards" else 1
