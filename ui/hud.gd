class_name Hud
extends Control

## 只显示已提交数据；数字缓存和Tween不参与规则计算。
signal score_animation_changed
signal fast_requested(fast: bool)
signal pause_requested
signal low_effects_requested(enabled: bool)
signal volume_requested(volume: float)
signal volume_committed(volume: float)
signal board_area_changed

@export var score_duration: float = 0.45
@onready var score_label: Label = %ScoreLabel
@onready var gain_label: Label = %GainLabel
@onready var reward_label: Label = %RewardLabel
@onready var reward_bar: ProgressBar = %RewardBar
@onready var board_label: Label = %BoardLabel
@onready var pressure_bar: ProgressBar = %PressureBar
@onready var turn_label: Label = %TurnLabel
@onready var skills_label: RichTextLabel = %SkillsLabel
@onready var breakdown_label: RichTextLabel = %BreakdownLabel
@onready var status_label: Label = %StatusLabel
@onready var fast_button: CheckButton = %FastButton
@onready var selection_label: Label = %SelectionLabel
@onready var tools_label: Label = %ToolsLabel
@onready var pause_button: Button = %PauseButton
@onready var board_area: Control = %BoardArea
@onready var low_effects_button: CheckButton = %LowEffectsButton
@onready var volume_slider: HSlider = %VolumeSlider
var displayed_score: int = 0
var _target_score: int = 0
var _score_tween: Tween
var _epoch: int = 0
var _fast: bool = false

func _ready() -> void:
	fast_button.toggled.connect(fast_requested.emit)
	pause_button.pressed.connect(pause_requested.emit)
	low_effects_button.toggled.connect(low_effects_requested.emit)
	volume_slider.value_changed.connect(_on_volume_changed)
	volume_slider.drag_ended.connect(_on_volume_drag_ended)
	board_area.item_rect_changed.connect(_notify_board_area)

## Game负责将这一屏幕区域转换到棋盘的坐标系。
func get_board_area() -> Rect2:
	return board_area.get_global_rect().grow(-8.0)

func _notify_board_area() -> void:
	board_area_changed.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE:
			pause_requested.emit()
			get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	_cancel_score()

func show_score(target: int) -> void:
	if target == _target_score: return
	_cancel_score()
	var previous: int = _target_score
	_target_score = target
	if target <= previous:
		_set_score(float(target))
		gain_label.text = ""
		return
	gain_label.text = "+%d" % (target - previous)
	_score_tween = create_tween()
	_score_tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	_score_tween.set_speed_scale(2.0 if _fast else 1.0)
	_score_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_score_tween.tween_method(_set_score, float(displayed_score), float(target), score_duration)
	_score_tween.finished.connect(_finish_score.bind(target, _epoch))

func wait_for_score() -> bool:
	var epoch: int = _epoch
	while _score_tween != null and _score_tween.is_valid() and _score_tween.is_running():
		await score_animation_changed
		if epoch != _epoch: return false
	return true

func show_run(run: RunController) -> void:
	var state: RunState = run.state
	var goal: int = state.progression.next_milestone
	reward_label.text = "下一次技能选择：%d 分 · 还差 %d\n已选 %d 次 · 待选 %d 次" % [goal, maxi(0, goal - state.ledger.total), state.rewards.consumed_count, state.pending_rewards]
	reward_bar.min_value = state.progression.previous_milestone
	reward_bar.max_value = goal
	reward_bar.value = state.ledger.total
	turn_label.text = "回合 %d · 移动 %d" % [state.turn_count, state.valid_moves]
	show_occupancy(state.rules.state.get_snapshot().size(), state.rules.state.columns * state.rules.state.rows)
	skills_label.text = HudDetails.skills(state)
	breakdown_label.text = HudDetails.score_details(state.ledger.get_entries())
	tools_label.text = "工具与临时状态\n" + HudDetails.tools(state)

func show_occupancy(count: int, capacity: int = 81) -> void:
	board_label.text = "空位 %d / %d" % [capacity - count, capacity]
	pressure_bar.max_value = capacity
	pressure_bar.value = count
	pressure_bar.modulate = Color(1.0, 0.5, 0.4) if count >= capacity * 0.8 else Color.WHITE

func show_status(text: String) -> void:
	status_label.text = text

func show_selection(piece: PieceState, has_fuse: bool) -> void:
	if piece == null:
		selection_label.text = "未选中棋子"
		return
	var identity: String = "爆壳手 · 消除时爆炸" if piece.content_id == &"special_demolition" else "普通材料"
	if has_fuse and piece.content_id.is_empty(): identity += " · 带引信，消除时爆炸"
	selection_label.text = "%s · 格 (%d, %d)" % [identity, piece.coordinate.x + 1, piece.coordinate.y + 1]

func set_fast(fast: bool) -> void:
	_fast = fast
	fast_button.set_pressed_no_signal(fast)
	if _score_tween != null and _score_tween.is_valid(): _score_tween.set_speed_scale(2.0 if fast else 1.0)

func set_low_effects(enabled: bool) -> void:
	low_effects_button.set_pressed_no_signal(enabled)

func set_volume(volume: float) -> void:
	volume_slider.set_value_no_signal(volume)
	volume_slider.tooltip_text = "音量 %d%%（0 为静音）" % roundi(volume * 100.0)

func _on_volume_drag_ended(_changed: bool) -> void:
	volume_committed.emit(volume_slider.value)

func _on_volume_changed(volume: float) -> void:
	volume_requested.emit(volume)
	if not volume_slider.is_dragging(): volume_committed.emit(volume)

func _set_score(value: float) -> void:
	displayed_score = roundi(value)
	score_label.text = "分数  %d" % displayed_score

func _finish_score(target: int, epoch: int) -> void:
	if epoch != _epoch: return
	displayed_score = target
	score_label.text = "分数  %d" % target
	score_animation_changed.emit()

func _cancel_score() -> void:
	_epoch += 1
	if _score_tween != null and _score_tween.is_valid(): _score_tween.kill()
	_score_tween = null
	score_animation_changed.emit()
