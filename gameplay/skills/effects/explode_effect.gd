class_name ExplodeEffect
extends Resource

## 只查询当前目标，不改占格、不计分；离场来源使用快照。
func build_request(state: BoardState, source: PieceState, radius: int) -> BlastRequest:
	var result: BlastRequest = BlastRequest.new()
	result.source = source.copy()
	result.radius = radius
	for piece: PieceState in state.get_snapshot():
		var delta: Vector2i = piece.coordinate - source.coordinate
		if absi(delta.x) <= radius and absi(delta.y) <= radius:
			result.target_ids.append(piece.piece_id)
	return result
