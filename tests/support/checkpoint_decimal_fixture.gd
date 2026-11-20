extends RefCounted

## Re-records the historical seven moves with today's rules at the original pending offer.
const PATH: String = "res://tests/fixtures/checkpoint_decimal_roundtrip.json"

static func archived_records() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	records.assign(JSON.parse_string(FileAccess.get_file_as_string(PATH)))
	return records

static func current_records() -> Array[Dictionary]:
	var archived: Array[Dictionary] = archived_records()
	var header: Dictionary = archived[0]
	var board: BoardState = BoardState.new(int(header.config.columns), int(header.config.rows))
	var rules: BoardRules = BoardRules.new(board, int(header.config.match_count))
	var run: RunController = RunController.new(rules, int(header.seed))
	run.state.run_id = header.run_id
	run.initialize()
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "checkpoint_test", false)
	for record: Dictionary in archived:
		if record.kind != "CommandAttempt": continue
		var move: RunCommand = CommandCodec.decode(record.command)
		if move == null or not run.execute_command(move).accepted:
			push_error("Historical move rejected at sequence %s" % record.seq)
			return []
		var step: RunStepResult = run.advance()
		while step.kind in [&"end_turn", &"spawn"]:
			step = run.advance()
		if step.kind not in [&"input", &"offer"]:
			push_error("Unexpected turn boundary %s at sequence %s" % [step.kind, record.seq])
			return []
	return run.recorder.records
