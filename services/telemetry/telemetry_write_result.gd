class_name TelemetryWriteResult
extends RefCounted

enum Status { ACCEPTED, PERSISTED, FAILED }
var status: Status
var reason: String

func _init(value: Status = Status.ACCEPTED, message: String = "") -> void:
	status = value
	reason = message

func succeeded() -> bool:
	return status != Status.FAILED
