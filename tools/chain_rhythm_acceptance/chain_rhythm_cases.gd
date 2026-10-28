extends RefCounted

## Fixed long-chain initial states; all consequences run through the production command path.
const L_TEMPLATE: MatchShapeTemplate = preload("res://gameplay/board/matching/l_template.tres")
const KEYS: Array[String] = ["blast_row", "row_blast", "long_chain", "shape_chain"]

static func create(key: String) -> RunController:
	if key in ["blast_row", "row_blast"]: return AestheticCases.create(key)
	var templates: Array[MatchShapeTemplate] = []
	if key == "shape_chain": templates.append(L_TEMPLATE)
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5, templates), 128)
	for x: int in range(1, 5): run.state.rules.place_piece(Vector2i(x, 4), 1)
	if key == "shape_chain":
		run.state.rules.place_piece(Vector2i(1, 2), 1)
		run.state.rules.place_piece(Vector2i(1, 3), 1)
	run.abilities.add_core(Vector2i(5, 5), 1)
	run.abilities.add_line_piece(LineClearState.AXIS_ROW, Vector2i(6, 4), 2)
	var first: PieceState = run.state.rules.place_piece(Vector2i(8, 4), 3)
	run.abilities.assign_fuse(first.piece_id)
	run.abilities.add_line_piece(LineClearState.AXIS_COLUMN, Vector2i(8, 3), 2)
	var last: PieceState = run.state.rules.place_piece(Vector2i(8, 0), 3)
	run.abilities.assign_fuse(last.piece_id)
	run.state.rules.place_piece(Vector2i(7, 0), 4)
	# Survives both sweeps, avoiding an unrelated empty-board recovery. The 111-point shape case legitimately enters reward waiting.
	run.state.rules.place_piece(Vector2i(0, 8), 4)
	run.abilities.upgrade_reward()
	run.start_turn()
	return run

static func title(key: String) -> String:
	return {"blast_row": "爆破→扫线", "row_blast": "扫线→爆破",
		"long_chain": "六段长链", "shape_chain": "直线＋L重叠→六段长链"}.get(key, key)
