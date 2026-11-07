extends RefCounted

## Wires sibling presentation ports explicitly; never reads or changes run rules.

static func configure(board: Board, hud: Hud, feedback: GameFeedback) -> void:
	board.view.spawn_flight_host = hud.spawn_flights
	board.spawn_preview_prepare = hud.spawn_preview.prepare_flight
	board.spawn_origin_provider = hud.spawn_preview.take_origin
	board.selection_changed.connect(_on_selection.bind(feedback))
	board.input_ready.connect(hud.show_input_ready)
	board.operation_feedback.connect(hud.show_board_feedback)

static func _on_selection(piece: PieceState, _has_fuse: bool, feedback: GameFeedback) -> void:
	if piece != null: feedback.play(&"select")
