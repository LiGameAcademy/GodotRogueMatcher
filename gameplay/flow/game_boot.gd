extends Node

## Selects a route before creating either the playable board or the preparation room.
const PROGRESS: Script = preload("res://services/run_checkpoint/opening_progress.gd")
@export var checkpoint_directory: String = "user://run_checkpoint"
@onready var _slot: GameCheckpointFlow = $Slot

func _ready() -> void:
	CoreSystem.scene_manager.scene_loading_failed.connect(_load_failed)
	_slot.prompt.action_requested.connect(_retry)
	_route.call_deferred()

func _retry(_action: StringName) -> void:
	_slot.prompt.close()
	await _route()

func _load_failed(_path: String, _reason: String) -> void:
	_slot.prompt.open(&"flow.retry", &"invalidate_failed")

func _route() -> void:
	_slot.last_error = ""
	_slot.use_snapshot = true
	await _slot.inspect_slot(checkpoint_directory)
	var progress: PROGRESS = _slot.opening_progress
	var data: Dictionary = {"directory": checkpoint_directory}
	if not _slot.last_error.is_empty() and _slot.last_error != "legacy_checkpoint_unsupported":
		_slot.prompt.open(&"flow.retry", &"invalidate_failed")
		return
	if progress.completed or (_slot.saved_available and not progress.started) or _slot.last_error == "legacy_checkpoint_unsupported" or _slot.known_closed_slot:
		GameFlow.travel(GameFlow.Page.ROOM, data)
		return
	if not progress.started and not (await progress.begin_visit()).is_empty():
		_slot.prompt.open(&"flow.retry", &"invalidate_failed")
		return
	data.merge({"action": "continue"} if _slot.saved_available else {"action": "new", "mode": "stage_challenge", "opening": "standard"})
	GameFlow.travel(GameFlow.Page.PLAY, data)
