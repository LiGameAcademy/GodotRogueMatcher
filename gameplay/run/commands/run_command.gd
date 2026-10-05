class_name RunCommand
extends RefCounted

var run_id: String
var command_id: int
var expected_action_id: int
var source: String = "human"
var buffered: bool = false
var buffered_wait_ms: int = 0

func _init(id: String = "", request: int = 0, action: int = 0) -> void:
	run_id = id
	command_id = request
	expected_action_id = action
