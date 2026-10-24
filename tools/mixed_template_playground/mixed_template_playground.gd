extends Node

signal fixture_ready(mode: String)

const MAIN: PackedScene = preload("res://main.tscn")
var main: Node2D
var board: Board
var loading: bool = false
var current_mode: String = "fixture_mixed_lt"
@onready var status: Label = $Tools/Panel/Rows/Status
@onready var instructions: Label = $Tools/Panel/Rows/Instructions
@onready var cases: OptionButton = $Tools/Panel/Rows/Cases
@onready var baseline: CheckButton = $Tools/Panel/Rows/Baseline

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for label: String in ["L/T 共享", "＋/× 重叠", "＋与× 独立", "全模板＋直线"]: cases.add_item(label)
	cases.item_selected.connect(func(_index: int) -> void: _reset())
	baseline.toggled.connect(func(_enabled: bool) -> void: _reset())
	($Tools/Panel/Rows/Reset as Button).pressed.connect(_reset)
	load_fixture(current_mode)

func _reset() -> void:
	load_fixture("fixture_mixed_" + MixedTemplateDemo.CASES[cases.selected] + ("_baseline" if baseline.button_pressed else ""))

func _process(_delta: float) -> void:
	if loading or not is_instance_valid(board) or board.run == null: return
	var run: RunController = board.run
	status.text = "分数 %d · 棋子 %d · 恢复批次 %d\n%s" % [run.state.ledger.total, run.state.rules.state.get_piece_count(), run.state.rules.shape_unlocks.recovery_batch_id, "可操作" if board.can_selected else "选卡或播放中"]

## Recreate the real game scene to cancel old callbacks, popups and playback together.
func load_fixture(mode: String) -> void:
	if loading or mode not in MixedTemplateDemo.MODES: return
	loading = true
	current_mode = mode
	cases.disabled = true
	baseline.disabled = true
	($Tools/Panel/Rows/Reset as Button).disabled = true
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
	var active: RunController = MixedTemplateDemo.new_run(mode)
	active.recorder = RunRecorder.new()
	active.recorder.metadata = {"case": MixedTemplateDemo.case_id(mode), "configuration": "line_baseline" if mode.ends_with("_baseline") else "technical_mixed", "screening_result": null}
	active.recorder.begin(active, "fixture", true, "development", "user://mixed_playground_records")
	board.run = active
	board.rules = active.state.rules
	game.set("board_rules", board.rules)
	GameManager.reset_game(active)
	board.view.rebuild(board.rules.state.get_snapshot())
	board.can_selected = false
	var from: Vector2i = MixedTemplateDemo.source(mode) + Vector2i.ONE
	var to: Vector2i = MixedTemplateDemo.target(mode) + Vector2i.ONE
	instructions.text = "开局配置题，非真实取得。\n先记录预测消除集合及是否补棋，再将第%d行%d列红棋移到第%d行%d列。\n若出现经典奖励，选“留白”完成后观察。\n切换基线或重置会新开同种子盘面。" % [from.y, from.x, to.y, to.x]
	board.resume_run(active)
	cases.select(MixedTemplateDemo.CASES.find(MixedTemplateDemo.case_id(mode)))
	baseline.set_pressed_no_signal(mode.ends_with("_baseline"))
	cases.disabled = false
	baseline.disabled = false
	($Tools/Panel/Rows/Reset as Button).disabled = false
	loading = false
	fixture_ready.emit(mode)
	print("MIXED_PLAYGROUND_READY ", mode)
	if OS.get_cmdline_user_args().has("--mixed-screenshot"):
		await get_tree().create_timer(1.0, true).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://mixed_playground.png")
