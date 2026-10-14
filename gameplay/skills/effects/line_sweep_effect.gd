class_name LineSweepEffect
extends SkillEffect

## Query the live axis from a frozen removal source. Ordinary pieces include fuses;
## other specials survive. The resolver alone commits removal, score and descendants.
func build_request(state: BoardState, source: PieceState, radius: int = 0) -> BlastRequest:
	var request: BlastRequest = BlastRequest.new()
	request.source = source.copy()
	request.radius = maxi(0, radius)
	var axis: int = LineClearState.axis_of(source.content_id)
	if axis < 0: return request
	for piece: PieceState in state.get_snapshot():
		if not piece.content_id.is_empty(): continue
		var distance: int = absi(piece.coordinate.y - source.coordinate.y) if axis == LineClearState.AXIS_ROW else absi(piece.coordinate.x - source.coordinate.x)
		var aligned: bool = distance <= request.radius
		if aligned: request.target_ids.append(piece.piece_id)
	request.target_ids.sort()
	return request
