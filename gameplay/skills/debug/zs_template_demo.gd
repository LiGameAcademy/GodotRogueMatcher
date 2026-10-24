class_name ZsTemplateDemo
extends RefCounted

const TEMPLATE: MatchShapeTemplate = preload("res://gameplay/board/matching/zs_template.tres")

## Named fixture initialization is replayable; never mutate a live production run.
static func populate(run: RunController, mode: String) -> void:
	var mirror: bool = mode == "fixture_shape_unlock_zs_mirror"
	var moving: bool = mode == "fixture_shape_zs_move"
	for source: Vector2i in TEMPLATE.offsets:
		var coordinate: Vector2i = Vector2i(2 - source.x, source.y) if mirror else source
		if moving and coordinate == Vector2i(2, 2): continue
		run.state.rules.place_piece(coordinate, 0)
	if mode != "fixture_shape_unlock_zs_empty": run.state.rules.place_piece(Vector2i(8, 8), 1)
	if moving:
		run.state.rules.place_piece(Vector2i(2, 3), 0)
		run.state.rules.shape_unlocks.unlock(TEMPLATE, 0)
		run.state.pending_rewards = 0
	else:
		run.state.pending_rewards = 2 if mode == "fixture_shape_unlock_zs_two_rewards" else 1
