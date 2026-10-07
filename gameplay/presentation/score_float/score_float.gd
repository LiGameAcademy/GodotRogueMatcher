class_name ScoreFloat
extends Node2D

@export var config: ScoreFloatConfig = preload("res://gameplay/presentation/score_float/score_float_config.tres")
@onready var panel: PanelContainer = $Panel
@onready var title_label: Label = %Title
@onready var score_label: Label = %Score
@onready var formula_label: Label = %Formula
@onready var extra_label: Label = %Extra
var display_size: Vector2 = Vector2.ZERO
var reserved_rect: Rect2
var _lifetime: Tween
var _motion: Tween
var _low_effects: bool = false
var _speed: float = 1.0

## 只消费已结算条目，主分与额外分之和严格等于final_score。
func configure(entry: ScoreEntry, cause: StringName, generation: int) -> void:
	var main_score: int = entry.final_score - entry.extra_score
	var color: Color = config.normal_color
	var grade: String = ""
	if entry.final_score >= config.huge_score:
		color = config.huge_color
		grade = " · 高能得分"
	elif entry.final_score >= config.high_score:
		color = config.high_color
		grade = " · 大得分"
	var source: String = "五连消除"
	if cause == &"explosion": source = "爆破" if generation <= 1 else "连锁 · 第%d波" % generation
	elif cause == &"bonus": source = "连锁奖励" if entry.reason == &"chain_reward" else "技能奖励"
	elif entry.match_count > 5: source = "%d连消除" % entry.match_count
	title_label.text = source + grade
	title_label.modulate = color
	score_label.text = "得分 +%d" % main_score
	score_label.modulate = color
	score_label.visible = main_score > 0
	formula_label.text = "%d × %.2f → %d" % [entry.base_score, entry.multiplier, main_score]
	formula_label.visible = main_score > 0
	extra_label.text = "额外 +%d" % entry.extra_score
	extra_label.modulate = color if main_score == 0 and not grade.is_empty() else config.extra_color
	extra_label.visible = entry.extra_score > 0
	var style: StyleBoxFlat = panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	style.border_color = Color(color, 0.7)
	panel.add_theme_stylebox_override("panel", style)
	display_size = Vector2(config.card_width, 0.0).max(panel.get_combined_minimum_size())
	panel.size = display_size
	modulate.a = 0.0

func play(origin: Vector2, low_effects: bool, speed: float) -> void:
	position = origin
	reserved_rect = Rect2(origin - Vector2(0, config.rise_distance), display_size + Vector2(0, config.rise_distance))
	_low_effects = low_effects
	_speed = maxf(speed, 0.01)
	_lifetime = create_tween().set_speed_scale(_speed)
	_lifetime.tween_interval(config.reveal_delay)
	_lifetime.tween_callback(_reveal)
	_lifetime.tween_interval(config.hold_seconds)
	_lifetime.tween_property(self, "modulate:a", 0.0, config.fade_seconds)
	_lifetime.finished.connect(queue_free)

func set_low_effects(enabled: bool) -> void:
	_low_effects = enabled
	if enabled:
		if _motion != null and _motion.is_valid(): _motion.kill()
		scale = Vector2.ONE

func set_speed(value: float) -> void:
	_speed = maxf(value, 0.01)
	if _lifetime != null and _lifetime.is_valid(): _lifetime.set_speed_scale(_speed)
	if _motion != null and _motion.is_valid(): _motion.set_speed_scale(_speed)

func _reveal() -> void:
	modulate.a = 1.0
	if _low_effects: return
	scale = Vector2(0.96, 0.96)
	_motion = create_tween().set_parallel().set_speed_scale(_speed)
	_motion.tween_property(self, "position:y", position.y - config.rise_distance, config.hold_seconds + config.fade_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_motion.tween_property(self, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
