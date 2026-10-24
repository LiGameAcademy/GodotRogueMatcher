extends Node

signal fixture_ready(mode: String)

const MAIN: PackedScene = preload("res://main.tscn")
var main: Node2D
var board: Board
var session: RunController
var loading: bool = false
var current_key: String = "baseline"
var current_task: String = "free"
var settings: ScreeningConfig
var started_ms: int = 0
var stopped: bool = false
var stopped_elapsed_ms: int = 0
var stop_reason: String = ""
var record_error: String = ""
var summary_path: String = ""
@onready var status: Label = $Tools/Panel/Rows/Status
@onready var instructions: Label = $Tools/Panel/Rows/Instructions
@onready var configurations: OptionButton = $Tools/Panel/Rows/Configurations
@onready var tasks: OptionButton = $Tools/Panel/Rows/Tasks

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for key: String in ScreeningDeck.CONFIGS: configurations.add_item(ScreeningDeck.config(key).title)
	for label: String in ["自由试玩", "固定题1", "固定题2", "固定题3", "固定题4"]: tasks.add_item(label)
	configurations.item_selected.connect(func(_index: int) -> void: _reset())
	tasks.item_selected.connect(func(_index: int) -> void: _reset())
	($Tools/Panel/Rows/Reset as Button).pressed.connect(_reset)
	load_fixture(current_key, current_task)

func _reset() -> void:
	load_fixture(ScreeningDeck.CONFIGS[configurations.selected], ScreeningDeck.TASKS[tasks.selected])

func _process(_delta: float) -> void:
	if loading or not is_instance_valid(board) or board.run == null: return
	var reason: String = ScreeningWindow.reason(board.run, settings, current_task != "free", elapsed_ms(), board.can_selected)
	if not stopped and not reason.is_empty(): _finish(reason)
	status.text = "%s · 行动 %d · %.0f秒\n%s\n%s" % [settings.title, board.run.state.valid_moves + board.run.state.activations, elapsed_ms() / 1000.0, ("已结束：" + stop_reason) if stopped else "试玩中（结算与选卡计时）", record_error if not record_error.is_empty() else summary_path.get_file()]

func elapsed_ms() -> int:
	return stopped_elapsed_ms if stopped else maxi(0, Time.get_ticks_msec() - started_ms)

## Checked before admitting an action and before releasing buffered input.
func _permit(active: RunController) -> bool:
	if stopped or active != session or active != board.run: return false
	var reason: String = ScreeningWindow.reason(active, settings, current_task != "free", elapsed_ms(), true)
	if not reason.is_empty(): _finish(reason)
	return not stopped

func _finish(reason: String) -> void:
	if stopped or session == null or session.recorder == null: return
	stopped_elapsed_ms = elapsed_ms()
	stopped = true
	stop_reason = reason
	if is_instance_valid(board) and board.run == session:
		board.can_selected = false
		board.cancel_buffered_input("screening_window_closed")
	var active: RunController = session
	var status_value: String = "censored" if reason in ["fixed_complete", "action_limit", "time_limit"] else "abandoned"
	if reason == "natural_end": status_value = "completed"
	if reason == "rule_error": status_value = "rule_error"
	active.recorder.finish(active, status_value, "screening_" + reason)
	summary_path = active.recorder.path.get_basename() + "-screening.json"
	var summary: Dictionary = {"run_id": active.state.run_id, "config_id": settings.config_id, "task": current_task, "record": active.recorder.path, "reason": reason, "actions": active.state.valid_moves + active.state.activations, "elapsed_ms": elapsed_ms(), "participant": null, "predictions": null, "selection_decision": null, "record_error": active.recorder.error}
	var file: FileAccess = FileAccess.open(summary_path, FileAccess.WRITE)
	if file == null: record_error = "观察记录保存失败：" + error_string(FileAccess.get_open_error())
	else:
		file.store_string(JSON.stringify(summary, "  "))
		file.flush()
		var write_error: Error = file.get_error()
		file.close()
		if write_error != OK: record_error = "观察记录写入失败：" + error_string(write_error)
	if not active.recorder.error.is_empty(): record_error = active.recorder.error
	active.retire()

func _exit_tree() -> void:
	_finish("closed")

## Recreate the real game scene to cancel old callbacks, popups and playback together.
func load_fixture(key: String, task: String) -> void:
	if loading or key not in ScreeningDeck.CONFIGS or task not in ScreeningDeck.TASKS: return
	_finish("restarted")
	session = null
	loading = true
	current_key = key
	current_task = task
	settings = ScreeningDeck.config(key)
	stopped = false
	stopped_elapsed_ms = 0
	stop_reason = ""
	record_error = ""
	summary_path = ""
	configurations.disabled = true
	tasks.disabled = true
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
	game.connect("restart_requested", func() -> void: load_fixture(current_key, current_task))
	game.set("persist_preferences", false)
	game.set("record_runs", false)
	game.set("collect_telemetry", false)
	board = game.get_node("Board") as Board
	board.game_mode = GameModes.CLASSIC
	add_child(main)
	await board.initialized
	board.run.retire()
	var active: RunController = ScreeningDeck.new_run(key, task)
	active.recorder = RunRecorder.new()
	active.recorder.metadata = {"protocol": "screening-v1", "configuration": RunSnapshot.resource_fields(settings), "task": task, "participant": null, "screening_result": null, "window_clock": "wall_including_pause_and_choice"}
	active.recorder.begin(active, "screening_playground", true, "development", "user://screening_records")
	session = active
	board.run = active
	board.rules = active.state.rules
	game.set("board_rules", board.rules)
	GameManager.reset_game(active)
	board.view.rebuild(board.rules.state.get_snapshot())
	board.can_selected = false
	instructions.text = "正常出生＋生产奖励池。15个有效玩家行动或8分钟先到停止；结算和选卡完成后封存。暂停也计时。\n先登记匿名ID、顺序与说明次数；自然未触发也保留。"
	if task != "free":
		var from: Vector2i = ScreeningDeck.source(active.initialization) + Vector2i.ONE
		var to: Vector2i = ScreeningDeck.target(active.initialization) + Vector2i.ONE
		instructions.text = "先预测消除棋子和是否补棋，再将第%d行%d列红棋移到第%d行%d列。\n固定题使用定向留白奖励；完成一次行动及选卡后封存。" % [from.y, from.x, to.y, to.x]
	started_ms = Time.get_ticks_msec()
	board.input_permission = _permit
	board.resume_run(active)
	configurations.select(ScreeningDeck.CONFIGS.find(key))
	tasks.select(ScreeningDeck.TASKS.find(task))
	configurations.disabled = false
	tasks.disabled = false
	($Tools/Panel/Rows/Reset as Button).disabled = false
	loading = false
	fixture_ready.emit(active.initialization)
	print("SCREENING_PLAYGROUND_READY ", key, " ", task)
	if OS.get_cmdline_user_args().has("--screening-screenshot"):
		await get_tree().create_timer(1.0, true).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://screening_playground.png")
