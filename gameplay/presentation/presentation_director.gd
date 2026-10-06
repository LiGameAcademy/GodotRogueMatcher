class_name PresentationDirector
extends Node

signal step_requested(step: PresentationStep, epoch: int, token: int)
signal busy_changed(busy: bool)
signal playback_failed(reason: String)

@export var config: PresentationConfig = preload("res://gameplay/presentation/presentation_config.tres")
var error: String = ""
var _queue: Array[PresentationStep] = []
var _epoch: int = 0
var _next_token: int = 0
var _waiting_token: int = 0
var _busy: bool = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_UNPAUSED: _dispatch.call_deferred()

func _exit_tree() -> void:
	cancel()

## 调用者先冻结数据，父协调器通过信号派发给具体视图。
func enqueue(steps: Array[PresentationStep]) -> void:
	if steps.is_empty() or not error.is_empty(): return
	_queue.append_array(steps)
	_set_busy(true)
	_dispatch()

func complete_step(epoch: int, token: int, success: bool = true) -> void:
	if epoch != _epoch or token != _waiting_token or token == 0: return
	_waiting_token = 0
	if not success:
		error = "presentation_action_failed"
		_queue.clear()
		_set_busy(false)
		playback_failed.emit(error)
		return
	_dispatch.call_deferred()

func cancel() -> void:
	_epoch += 1
	_waiting_token = 0
	_queue.clear()
	error = ""
	_set_busy(false)

func is_busy() -> bool:
	return _busy

## 取消与完成不同：旧等待不能开放新局输入。
func wait_until_idle() -> bool:
	var epoch: int = _epoch
	while _busy:
		await busy_changed
		if epoch != _epoch: return false
	return epoch == _epoch and error.is_empty()

func _dispatch() -> void:
	if not is_inside_tree() or get_tree().paused or _waiting_token != 0 or not error.is_empty(): return
	if _queue.is_empty():
		_set_busy(false)
		return
	_next_token += 1
	_waiting_token = _next_token
	var step: PresentationStep = _queue.pop_front()
	step_requested.emit(step, _epoch, _waiting_token)

func _set_busy(value: bool) -> void:
	if _busy == value: return
	_busy = value
	busy_changed.emit(value)
