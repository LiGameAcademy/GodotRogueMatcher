extends Node

## Uses the real Game without persistent preferences, telemetry or fixture overlays.
const OUTPUT: String = "res://.godot/issue130-piece-motion/captures"
@onready var _game: Node2D = $Game

func _ready() -> void:
	get_window().title = "技能连珠 · 棋子形变验收（#130）"
	var board: Board = _game.get_node("Board") as Board
	while not board.can_selected: await get_tree().process_frame
	print("PIECE_MOTION_PREVIEW_READY")
	if "--capture-piece" in OS.get_cmdline_user_args():
		await _capture_poses(board)

func _capture_poses(board: Board) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	board.can_selected = false
	var snapshot: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	var piece: ChessPiece = board.view.get_piece(board.rules.state.get_snapshot()[0].piece_id)
	var animation: Tween = piece.spawn_animation(0.3)
	animation.pause()
	animation.custom_step(0.15)
	await _capture("birth")
	animation.custom_step(0.2)
	animation = piece.land()
	animation.pause()
	await _capture("landing")
	animation.custom_step(0.1)
	await _capture("rest")
	var unchanged: bool = snapshot == RunSnapshot.digest(RunSnapshot.capture(board.run))
	print("PIECE_MOTION_CAPTURE_RULES_UNCHANGED ", unchanged)
	get_tree().quit(0 if unchanged else 1)

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var error: Error = get_viewport().get_texture().get_image().save_png(OUTPUT.path_join(label + ".png"))
	if error != OK: push_error(error_string(error))
