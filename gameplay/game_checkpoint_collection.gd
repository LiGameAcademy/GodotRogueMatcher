extends RefCounted

## Parent-owned checkpoint/collection wiring. All scene collaborators are passed explicitly.
## Keeps telemetry failures separate from verified rule adoption and supports unobserved recording.
const SEGMENT: Script = preload("res://services/run_checkpoint/snapshot_segment.gd")

static func configure(flow: GameCheckpointFlow, collection: RunCollection, snapshot: bool, record_file: bool) -> void:
	flow.use_snapshot = snapshot
	flow.trace_provider = collection.snapshot_trace if snapshot else collection.checkpoint_trace
	flow.trace_confirmer = collection.confirm_snapshot_trace
	flow.resume_plan_provider = collection.plan_resume.bind(record_file)

static func resume(board: Board, collection: RunCollection, flow: GameCheckpointFlow, context: String, record_file: bool, collect: bool) -> void:
	var active: RunController = board.run
	if collect:
		board.observation.attach(collection.resume(context, active, flow.last_resume_context, record_file), false)
		board.telemetry_factory = collection.factory
	elif flow.use_snapshot:
		var plan: Dictionary = flow.last_resume_context.get("prepared", {})
		var id: String = String(plan.get("session_id", "resume-" + str(Time.get_ticks_usec())))
		var started: Dictionary = SEGMENT.begin(active, id)
		if started.ok and record_file:
			active.recorder.open_resume_file(String(plan.get("record_directory", "user://run_records")), id, active.recorder.metadata.resume)