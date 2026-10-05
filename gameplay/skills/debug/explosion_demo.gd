class_name ExplosionDemo
extends RefCounted

## T02的移动版：把[5,5]核心移动到[5,4]，预期70分并触发两代爆炸。
static func populate(run: RunController) -> void:
	for x: int in range(1, 5):
		run.state.rules.place_piece(Vector2i(x, 4), 1)
	run.abilities.add_core(Vector2i(5, 5))
	var fuse: PieceState = run.state.rules.place_piece(Vector2i(6, 4), 0)
	run.abilities.assign_fuse(fuse.piece_id)
	run.state.rules.place_piece(Vector2i(6, 3), 2)
	run.state.rules.place_piece(Vector2i(7, 4), 3)
	run.state.rules.place_piece(Vector2i(7, 3), 4)
	run.abilities.upgrade_reward()
