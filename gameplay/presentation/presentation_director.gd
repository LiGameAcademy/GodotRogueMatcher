class_name PresentationDirector
extends Node

signal step_requested(step: PresentationStep, epoch: int, token: int)
signal step_skip_requested(step: PresentationStep, epoch: int, token: int)
signal busy_changed(busy: bool)
signal playback_failed(reason: String)

@export var config: PresentationConfig = preload("res://gameplay/presentation/presentation_config.tres")
var error: String = ""
var _queue: Array[PresentationStep] = []
var _epoch: int = 0
var _next_token: int = 0
var _waiting_token: int = 0
var _busy: bool = false
var _current: PresentationStep
var _run_epoch: int = 0
var _skip_requested: bool = false
var skip_score_requested: bool = false
var recovery_snapshot: Array[PieceState] = []
var last_failure: String = ""
@onready var _step_guard: Timer = $StepGuard

func _notification(what: int) -> void:
	if what == NOTIFICATION_UNPAUSED: _dispatch.call_deferred()

func _exit_tree() -> void:
	cancel()

## 调用者先冻结数据，父协调器通过信号派发给具体视图。
func enqueue(steps: Array[PresentationStep], snapshot: Array[PieceState] = [], align: bool = false) -> void:
	if steps.is_empty() or not error.is_empty(): return
	if not _busy: clear_skip_request()
	_queue.append_array(steps)
	if align:
		var ending: PresentationStep = PresentationStep.new()
		ending.kind = PresentationStep.Kind.ALIGN
		ending.policy = PresentationStep.Policy.FIXED_REQUIRED
		for piece: PieceState in snapshot: ending.pieces.append(piece.copy())
		recovery_snapshot = ending.pieces
		_queue.append(ending)
	_set_busy(true)
	_dispatch()

func complete_step(epoch: int, token: int, success: bool = true) -> void:
	if epoch != _epoch or token != _waiting_token or token == 0: return
	_step_guard.stop()
	_waiting_token = 0
	if not success:
		_fail("presentation_action_failed")
		return
	if _current.kind == PresentationStep.Kind.ALIGN: _skip_requested = false
	_current = null
	_dispatch.call_deferred()

func cancel() -> void:
	if is_instance_valid(_step_guard): _step_guard.stop()
	_epoch += 1
	_run_epoch += 1
	_waiting_token = 0
	_queue.clear()
	error = ""
	last_failure = ""
	_current = null
	recovery_snapshot.clear()
	clear_skip_request()
	_set_busy(false)

func is_busy() -> bool:
	return _busy

func has_queued_steps() -> bool:
	return not _queue.is_empty()

## 取消与完成不同：旧等待不能开放新局输入。
func wait_until_idle() -> bool:
	var epoch: int = _run_epoch
	while _busy:
		await busy_changed
		if epoch != _run_epoch: return false
	return epoch == _run_epoch and error.is_empty()

func is_current(epoch: int, token: int) -> bool:
	return epoch == _epoch and token == _waiting_token and token != 0

## 请求只持续到本批终态；必播段继续等待真实完成。
func request_skip() -> bool:
	if not _busy or not error.is_empty() or get_tree().paused: return false
	_skip_requested = true
	skip_score_requested = true
	if _current != null and _current.policy == PresentationStep.Policy.SKIPPABLE:
		_skip_current()
	return true

func clear_skip_request() -> void:
	_skip_requested = false
	skip_score_requested = false

## 父协调器验证并恢复显示后确认；故障不重新派发规则阶段。
func confirm_recovery() -> void:
	if error.is_empty(): return
	_step_guard.stop()
	_epoch += 1
	_waiting_token = 0
	_current = null
	error = ""
	clear_skip_request()
	_set_busy(false)

func _dispatch() -> void:
	if not is_inside_tree() or get_tree().paused or _waiting_token != 0 or not error.is_empty(): return
	if _queue.is_empty():
		_set_busy(false)
		return
	_next_token += 1
	_waiting_token = _next_token
	_current = _queue.pop_front()
	var step: PresentationStep = _current
	var epoch: int = _epoch
	var token: int = _waiting_token
	_step_guard.start(maxf(config.step_timeout_seconds, step.duration * 4.0 + 0.5))
	if _skip_requested and _current.policy == PresentationStep.Policy.SKIPPABLE:
		_skip_current()
	else:
		step_requested.emit(step, epoch, token)

func _skip_current() -> void:
	_epoch += 1
	_next_token += 1
	_waiting_token = _next_token
	var step: PresentationStep = _current
	var epoch: int = _epoch
	var token: int = _waiting_token
	step_skip_requested.emit(step, epoch, token)

func _on_step_timeout() -> void:
	if _waiting_token == 0: return
	_waiting_token = 0
	_fail("presentation_timeout")

func _fail(reason: String) -> void:
	error = reason
	last_failure = reason
	_queue.clear()
	playback_failed.emit(reason)
	# 恢复通知可能同步启动下一批，旧故障不能再次关闭新批屏障。
	if not error.is_empty(): _set_busy(false)

func _set_busy(value: bool) -> void:
	if _busy == value: return
	_busy = value
	busy_changed.emit(value)
