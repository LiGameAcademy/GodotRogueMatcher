extends Node

signal fixture_ready(mode: String)

const MAIN: PackedScene = preload("res://main.tscn")
var main: Node2D
var board: Board
var loading: bool = false
var current_mode: String = "fixture_shape_unlock_u"
@onready var status: Label = $Tools/Panel/Rows/Status
@onready var instructions: Label = $Tools/Panel/Rows/Instructions
@onready var modes: HBoxContainer = $Tools/Panel/Rows/Modes

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	modes.get_node("U").pressed.connect(load_fixture.bind("fixture_shape_unlock_u"))
	modes.get_node("Rotated").pressed.connect(load_fixture.bind("fixture_shape_unlock_u_rotated"))
	modes.get_node("Empty").pressed.connect(load_fixture.bind("fixture_shape_unlock_u_empty"))
	modes.get_node("Move").pressed.connect(load_fixture.bind("fixture_shape_u_move"))
	load_fixture("fixture_shape_unlock_u")

func _process(_delta: float) -> void:
	if loading or not is_instance_valid(board) or board.run == null: return
	var run: RunController = board.run
	status.text = "分数 %d · 棋子 %d · 恢复批次 %d\n%s" % [run.state.ledger.total, run.state.rules.state.get_piece_count(), run.state.rules.shape_unlocks.recovery_batch_id, "可操作" if board.can_selected else "选卡或播放中"]

## Recreate the real game scene to cancel old callbacks, popups and playback together.
func load_fixture(mode: String) -> void:
	if loading or mode not in RunController.U_INITIALIZATIONS: return
	loading = true
	current_mode = mode
	UIManager.close_popup()
	get_tree().paused = false
	CoreSystem.audio_manager.stop_all()
	if is_instance_valid(main):
		main.queue_free()
		await get_tree().process_frame
	main = MAIN.instantiate() as Node2D
	var game: Node2D = main.get_node("Game") as Node2D
	game.set("show_start_menu", false)
	game.set("enable_debug_fixtures", false)
	game.set("use_external_restart", true)
	game.connect("restart_requested", func() -> void: load_fixture(current_mode))
	game.set("persist_preferences", false)
	game.set("record_runs", false)
	game.set("collect_telemetry", false)
	board = game.get_node("Board") as Board
	board.game_mode = GameModes.CLASSIC
	add_child(main)
	await board.initialized
	board.run.retire()
	var active: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 118, null, RunController.U_PROFILE)
	active.initialize(mode)
	active.recorder = RunRecorder.new()
	active.recorder.begin(active, "fixture", true, "development", "user://u_playground_records")
	board.run = active
	board.rules = active.state.rules
	game.set("board_rules", board.rules)
	GameManager.reset_game(active)
	board.view.rebuild(board.rules.state.get_snapshot())
	board.can_selected = false
	instructions.text = "选“测试：解锁U”→确认，观察七枚红棋消除、+84分。\nU=X.X/X.X/XXX，旋转仍是同一解锁身份。"
	if mode == "fixture_shape_unlock_u_empty": instructions.text = "仅有七枚红棋。解锁后应+84分，空盘只恢复一批3枚。"
	if mode == "fixture_shape_u_move": instructions.text = "已启用U。将第4行第3列红棋移到第3行第3列。\n预期七枚消除、+84分，只留右下绿棋，下一批不消耗。"
	board.resume_run(active)
	loading = false
	fixture_ready.emit(mode)
	print("U_PLAYGROUND_READY ", mode)
	if OS.get_cmdline_user_args().has("--u-screenshot"):
		await get_tree().create_timer(1.0, true).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://u_playground.png")
