extends Node

var collection: RunCollection
var _frames: int = 0
var _mode: String = "hold"
var _root: String = ""

func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2:
		get_tree().quit(1)
		return
	_mode = args[0]
	_root = args[1]
	collection = load("res://services/telemetry/run_collection.tscn").instantiate() as RunCollection
	add_child(collection)
	var factory: TelemetryFactory = TelemetryFactory.new()
	factory.directory = _root.path_join("telemetry")
	factory.record_directory = _root.path_join("run_records")
	collection.configure("automated_integration", factory)
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	run.initialize("fixture_f6")
	run.recorder = RunRecorder.new()
	factory.attach(run.recorder, run.state.run_id)
	run.recorder.begin(run, "fixture", true, "probe", factory.record_directory)
	collection.bind(run)
	var command: MovePieceCommand = MovePieceCommand.new(run.state.run_id, 1, 0)
	command.piece_id = run.state.rules.state.get_piece_id(Vector2i(5, 5))
	command.target = Vector2i(5, 4)
	if not run.execute_command(command).accepted:
		get_tree().quit(2)
		return
	while run.state.phase != RunState.Phase.INPUT: run.advance()
	collection.location("pause")
	collection.flush()
	var file: FileAccess = FileAccess.open(_root.path_join("ready.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"pid": OS.get_process_id(), "run_id": run.state.run_id, "recovered": collection.session.recovered}))
	file.close()

func _process(_delta: float) -> void:
	if _mode == "recover":
		_frames += 1
		if _frames > 2:
			collection.close("probe_complete")
			get_tree().quit()
