extends Node2D

@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var board: Board = $Board
@export var record_runs: bool = true
@export var collect_telemetry: bool = true
var board_rules: BoardRules
@export var enable_debug_fixtures: bool = true
var _fast_playback: bool = false

func _ready() -> void:
	GameManager.game_overed.connect(_on_game_over)
	if collect_telemetry: board.telemetry_factory = TelemetryFactory.new()
	board_rules = BoardRules.new(BoardState.new(board.cols, board.rows), MatchSystem.MIN_MATCH_COUNT)
	await board.start_game(board_rules, record_runs)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var playback_key: InputEventKey = event as InputEventKey
		if playback_key.pressed and not playback_key.echo and playback_key.physical_keycode == KEY_F8:
			_fast_playback = not _fast_playback
			board.set_playback_fast(_fast_playback)
	if enable_debug_fixtures and event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and key.physical_keycode == KEY_F6:
			board.load_explosion_demo()
		elif key.pressed and not key.echo and key.physical_keycode == KEY_F7:
			board.open_skill_demo()

func _on_game_over() -> void:
	board.can_selected = false
	var popup: Control = await UIManager.open_popup("popup_game_over", {"score": GameManager.score})
	if is_instance_valid(popup):
		popup.retry_requested.connect(_on_retry_requested)

func _on_retry_requested() -> void:
	UIManager.close_popup()
	board_rules = BoardRules.new(BoardState.new(board.cols, board.rows), MatchSystem.MIN_MATCH_COUNT)
	await board.retry_game(board_rules)
