class_name LineSweepEffect
extends SkillEffect

## Query live bands from a frozen source; specials now also leave and chain.
## The resolver alone commits removal, score and descendants.
func build_request(state: BoardState, source: PieceState, radius: int = 0, cross_radius: int = -1) -> BlastRequest:
	var request: BlastRequest = BlastRequest.new()
	request.source = source.copy()
	request.radius = maxi(0, radius)
	request.cross_radius = maxi(-1, cross_radius)
	var axis: int = LineClearState.axis_of(source.content_id)
	if axis < 0: return request
	for piece: PieceState in state.get_snapshot():
		if piece.piece_id == source.piece_id: continue
		var distance: int = absi(piece.coordinate.y - source.coordinate.y) if axis == LineClearState.AXIS_ROW else absi(piece.coordinate.x - source.coordinate.x)
		var perpendicular: int = absi(piece.coordinate.x - source.coordinate.x) if axis == LineClearState.AXIS_ROW else absi(piece.coordinate.y - source.coordinate.y)
		var aligned: bool = distance <= request.radius or (request.cross_radius >= 0 and perpendicular <= request.cross_radius)
		if aligned: request.target_ids.append(piece.piece_id)
	request.target_ids.sort()
	return request
