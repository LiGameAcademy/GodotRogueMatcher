class_name ExplodeEffect
extends SkillEffect

## Query current targets only; no occupancy or score writes. Removal sources use snapshots.
func build_request(state: BoardState, source: PieceState, radius: int) -> BlastRequest:
	var result: BlastRequest = BlastRequest.new()
	result.source = source.copy()
	result.radius = radius
	for piece: PieceState in state.get_snapshot():
		var delta: Vector2i = piece.coordinate - source.coordinate
		if absi(delta.x) <= radius and absi(delta.y) <= radius:
			result.target_ids.append(piece.piece_id)
	return result
