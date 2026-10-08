class_name ScoreFloat
extends Node2D

@export var config: ScoreFloatConfig = preload("res://gameplay/presentation/score_float/score_float_config.tres")
@onready var numbers: Control = $Numbers
@onready var score_label: Label = %Score
@onready var extra_label: Label = %Extra
var display_size: Vector2 = Vector2.ZERO
var reserved_rect: Rect2
var _lifetime: Tween
var _motion: Tween
var _pop: Tween
var _low_effects: bool = false
var _speed: float = 1.0
var _peak_scale: float = 1.0
var _hold_seconds: float = 0.0

## 仅保留实际到账数字，主分与额外分分色；放大包络参与避让。
func configure(entry: ScoreEntry) -> void:
	var main_score: int = entry.final_score - entry.extra_score
	var color: Color = config.normal_color
	var font_size: int = config.normal_font_size
	_peak_scale = 1.0
	_hold_seconds = config.hold_seconds
	if entry.final_score >= config.huge_score:
		color = config.huge_color
		font_size = config.huge_font_size
		_peak_scale = config.huge_peak_scale
	elif entry.final_score >= config.high_score:
		color = config.high_color
		font_size = config.high_font_size
		_peak_scale = config.high_peak_scale
	if _peak_scale > 1.0: _hold_seconds = config.high_hold_seconds
	score_label.text = "+%d" % main_score
	score_label.modulate = color
	score_label.visible = main_score > 0
	score_label.add_theme_font_size_override("font_size", font_size)
	extra_label.text = "+%d" % entry.extra_score
	extra_label.modulate = color if main_score == 0 and _peak_scale > 1.0 else config.extra_color
	extra_label.visible = entry.extra_score > 0
	extra_label.add_theme_font_size_override("font_size", config.extra_font_size if main_score > 0 else font_size)
	score_label.size = score_label.get_minimum_size()
	extra_label.size = extra_label.get_minimum_size()
	extra_label.position = Vector2(score_label.size.x + 5.0, score_label.size.y * 0.25) if main_score > 0 else Vector2.ZERO
	var content_size: Vector2 = score_label.size if main_score > 0 else Vector2.ZERO
	if entry.extra_score > 0: content_size = content_size.max(extra_label.position + extra_label.size)
	numbers.size = content_size
	numbers.pivot_offset = content_size * 0.5
	display_size = content_size * _peak_scale
	numbers.position = (display_size - content_size) * 0.5
	modulate.a = 0.0

func play(origin: Vector2, low_effects: bool, speed: float) -> void:
	position = origin
	reserved_rect = Rect2(origin - Vector2(0, config.rise_distance), display_size + Vector2(0, config.rise_distance))
	_low_effects = low_effects
	_speed = maxf(speed, 0.01)
	_lifetime = create_tween().set_speed_scale(_speed)
	_lifetime.tween_interval(config.reveal_delay)
	_lifetime.tween_callback(_reveal)
	_lifetime.tween_interval(_hold_seconds)
	_lifetime.tween_property(self, "modulate:a", 0.0, config.fade_seconds).set_trans(Tween.TRANS_SINE)
	_lifetime.finished.connect(queue_free)

func set_low_effects(enabled: bool) -> void:
	_low_effects = enabled
	if enabled:
		if _motion != null and _motion.is_valid(): _motion.kill()
		if _pop != null and _pop.is_valid(): _pop.kill()
		numbers.scale = Vector2.ONE

func set_speed(value: float) -> void:
	_speed = maxf(value, 0.01)
	for animation: Tween in [_lifetime, _motion, _pop]:
		if animation != null and animation.is_valid(): animation.set_speed_scale(_speed)

func _reveal() -> void:
	modulate.a = 1.0
	if _low_effects: return
	numbers.scale = Vector2.ONE * (0.5 if _peak_scale > 1.0 else 0.85)
	_motion = create_tween().set_speed_scale(_speed)
	_motion.tween_property(self, "position:y", position.y - config.rise_distance, _hold_seconds + config.fade_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_pop = create_tween().set_speed_scale(_speed)
	_pop.tween_property(numbers, "scale", Vector2.ONE * _peak_scale, config.pop_seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_pop.tween_property(numbers, "scale", Vector2.ONE, config.settle_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
