extends Node

signal fixture_ready(mode: String)

const MAIN: PackedScene = preload("res://main.tscn")
var main: Node2D
var board: Board
var loading: bool = false
var current_mode: String = "fixture_shape_unlock_ring"
@onready var status: Label = $Tools/Panel/Rows/Status
@onready var instructions: Label = $Tools/Panel/Rows/Instructions
@onready var modes: HBoxContainer = $Tools/Panel/Rows/Modes

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	modes.get_node("Ring").pressed.connect(load_fixture.bind("fixture_shape_unlock_ring"))
	modes.get_node("Center").pressed.connect(load_fixture.bind("fixture_shape_unlock_ring_center"))
	modes.get_node("Empty").pressed.connect(load_fixture.bind("fixture_shape_unlock_ring_empty"))
	modes.get_node("Move").pressed.connect(load_fixture.bind("fixture_shape_ring_move"))
	load_fixture("fixture_shape_unlock_ring")

func _process(_delta: float) -> void:
	if loading or not is_instance_valid(board) or board.run == null: return
	var run: RunController = board.run
	status.text = "分数 %d · 棋子 %d · 恢复批次 %d\n%s" % [run.state.ledger.total, run.state.rules.state.get_piece_count(), run.state.rules.shape_unlocks.recovery_batch_id, "可操作" if board.can_selected else "选卡或播放中"]

## Recreate the real game scene to cancel old callbacks, popups and playback together.
func load_fixture(mode: String) -> void:
	if loading or mode not in RunController.RING_INITIALIZATIONS: return
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
	var active: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 118, null, RunController.RING_PROFILE)
	active.initialize(mode)
	active.recorder = RunRecorder.new()
	active.recorder.begin(active, "fixture", true, "development", "user://ring_playground_records")
	board.run = active
	board.rules = active.state.rules
	game.set("board_rules", board.rules)
	GameManager.reset_game(active)
	board.view.rebuild(board.rules.state.get_snapshot())
	board.can_selected = false
	instructions.text = "选“测试：解锁空心环”→确认，观察八枚红棋消除、+104分。\n环=XXX/X.X/XXX；中心不要求为空。"
	if mode == "fixture_shape_unlock_ring_empty": instructions.text = "仅有八枚红棋。解锁后应+104分，空盘只恢复一批3枚。"
	if mode == "fixture_shape_ring_move": instructions.text = "已启用空心环。将第4行第3列红棋移到第3行第3列。\n预期八枚消除、+104分，只留右下绿棋，下一批不消耗。"
	instructions.text += "
104分会再获经典奖励：选解锁U并确认，再观察最终结果。"
	board.resume_run(active)
	loading = false
	fixture_ready.emit(mode)
	print("RING_PLAYGROUND_READY ", mode)
	if OS.get_cmdline_user_args().has("--ring-screenshot"):
		await get_tree().create_timer(1.0, true).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://ring_playground.png")
