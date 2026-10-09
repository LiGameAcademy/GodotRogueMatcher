extends Node

var results: Dictionary = {}

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var normal: Array[Dictionary] = []
	for seed_value: int in range(5):
		var strategy: RandomLegalBot = RandomLegalBot.new()
		strategy.config = strategy.config.duplicate() as BotConfig
		strategy.config.move_limit = 30
		var recorder: RunRecorder = BotRunner.new().play(seed_value + 7000, 101000, strategy, false, false)
		normal.append_array(_batches(recorder.records))
	var dense: Array[Dictionary] = []
	for sample: int in range(20):
		var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
		run.initialize("fixture_f6")
		run.recorder = RunRecorder.new()
		run.recorder.begin(run, "fixture", false)
		var command: MovePieceCommand = MovePieceCommand.new(run.state.run_id, 1, 0)
		command.piece_id = run.state.rules.state.get_piece_id(Vector2i(5, 5))
		command.target = Vector2i(5, 4)
		run.execute_command(command)
		while run.state.phase != RunState.Phase.INPUT: run.advance()
		dense.append_array(_batches(run.recorder.records))
	results = {"engine": Engine.get_version_info().string, "cpu": OS.get_processor_name(), "os": OS.get_name(), "normal": _measure(normal), "chain_fixture": _measure(dense), "scope": "frozen recorder facts projection + replay serialization + sink flush; excludes rules, UI, initialization, terminal summaries"}
	var file: FileAccess = FileAccess.open("res://.godot/collection_benchmark.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	file.close()
	print(JSON.stringify(results))
	get_tree().quit()

func _batches(records: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var pending: Array[Dictionary] = []
	for row: Dictionary in records:
		pending.append(row)
		if row.kind == "RuleResult" and row.get("stage") == "spawn":
			result.append({"header": records[0], "rows": pending.duplicate()})
			pending.clear()
	return result

func _measure(samples: Array[Dictionary]) -> Dictionary:
	var costs: Array[int] = []
	var calls: Array[int] = []
	var serialization: Array[int] = []
	var writes: Array[int] = []
	for sample: Dictionary in samples:
		var sink: LocalJsonlSink = LocalJsonlSink.new("benchmark-" + str(Time.get_ticks_usec()), "user://collection_benchmark")
		var projector: TelemetryProjector = TelemetryProjector.new(sink, "benchmark")
		projector.observe_record(sample.header)
		projector.flush_pending()
		var initial_serialize: int = sink.serialize_usec
		var initial_write: int = sink.write_usec
		var file: FileAccess = FileAccess.open("user://collection_benchmark/replay-" + str(Time.get_ticks_usec()) + ".jsonl", FileAccess.WRITE)
		var buffer: PackedByteArray = PackedByteArray()
		var encoded_usec: int = 0
		var start: int = Time.get_ticks_usec()
		for row: Dictionary in sample.rows:
			if row.kind == "Header": continue
			var call_start: int = Time.get_ticks_usec()
			projector.observe_record(row)
			var encoding: int = Time.get_ticks_usec()
			buffer.append_array((JSON.stringify(row, "", true) + "\n").to_utf8_buffer())
			encoded_usec += Time.get_ticks_usec() - encoding
			calls.append(Time.get_ticks_usec() - call_start)
		projector.flush_pending()
		var io_start: int = Time.get_ticks_usec()
		file.store_buffer(buffer)
		file.flush()
		var replay_io: int = Time.get_ticks_usec() - io_start
		costs.append(Time.get_ticks_usec() - start)
		sink.close()
		file.close()
		serialization.append(sink.serialize_usec - initial_serialize + encoded_usec)
		writes.append(sink.write_usec - initial_write + replay_io)
	return {"samples": costs.size(), "main_action_total_usec": _percentiles(costs), "main_per_record_usec": _percentiles(calls), "serialization_usec": _percentiles(serialization), "io_usec": _percentiles(writes)}

func _percentiles(values: Array[int]) -> Dictionary:
	values.sort()
	if values.is_empty(): return {}
	return {"p50": values[int(ceil(values.size() * 0.5)) - 1], "p95": values[int(ceil(values.size() * 0.95)) - 1], "p99": values[int(ceil(values.size() * 0.99)) - 1], "max": values.back()}
