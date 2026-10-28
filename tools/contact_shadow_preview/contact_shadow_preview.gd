extends Node

## Fixed real-game comparison; shadow toggles never write authoritative run state.
const OUTPUT: String = "res://.godot/issue130-contact-shadow/captures"
var _enabled: bool = true
@onready var _game: Node2D = $Game
@onready var _board: Board = $Game/Board

func _ready() -> void:
	get_window().title = "技能连珠 · 接触阴影验收（#130，S对比）"
	while not _board.can_selected: await get_tree().process_frame
	_board.run.retire()
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 130)
	for y: int in range(0, 9, 2):
		for x: int in range(9):
			run.state.rules.place_piece(Vector2i(x, y), (x + y * 2) % 5)
	run.start_turn()
	_board.run = run
	_board.rules = run.state.rules
	_game.set("board_rules", run.state.rules)
	GameManager.reset_game(run)
	_board.view.rebuild(run.state.rules.state.get_snapshot())
	_game.call("_set_background_motion", false, false)
	_game.call("_refresh_hud")
	print("CONTACT_SHADOW_PREVIEW_READY")
	if "--capture-shadow" in OS.get_cmdline_user_args(): await _capture_suite()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and key.physical_keycode == KEY_S:
			_enabled = not _enabled
			_apply_shadow()
			get_viewport().set_input_as_handled()

func _apply_shadow() -> void:
	var preset: GameTheme = _game.get("game_theme") as GameTheme
	var appearance: BoardAppearance = preset.board.duplicate() as BoardAppearance
	if not _enabled: appearance.piece_shadow.a = 0.0
	for state: PieceState in _board.rules.state.get_snapshot():
		_board.view.get_piece(state.piece_id).apply_game_theme(appearance)

func _capture_suite() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var before: String = RunSnapshot.digest(RunSnapshot.capture(_board.run))
	for preset: GameTheme in GameThemes.ALL:
		_game.call("_set_theme", preset.theme_id, false)
		for reduced: bool in [false, true]:
			_game.call("_set_low_effects", reduced, false)
			for enabled: bool in [false, true]:
				_enabled = enabled
				_apply_shadow()
				await RenderingServer.frame_post_draw
				var label: String = "%s_low%d_shadow%d.png" % [preset.theme_id, int(reduced), int(enabled)]
				var error: Error = get_viewport().get_texture().get_image().save_png(OUTPUT.path_join(label))
				if error != OK: push_error(error_string(error))
	var unchanged: bool = before == RunSnapshot.digest(RunSnapshot.capture(_board.run))
	print("CONTACT_SHADOW_RULES_UNCHANGED ", unchanged)
	get_tree().quit(0 if unchanged else 1)
