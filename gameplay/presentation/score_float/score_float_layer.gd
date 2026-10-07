class_name ScoreFloatLayer
extends Node2D

const FLOAT: PackedScene = preload("res://gameplay/presentation/score_float/score_float.tscn")
@export var config: ScoreFloatConfig = preload("res://gameplay/presentation/score_float/score_float_config.tres")
var _seen_events: Dictionary[int, bool] = {}
var _action_anchors: Dictionary[int, Vector2] = {}

## 冻结结果给出坐标；无离场的奖励沿用同一行动最近的消除位置。
func show_results(results: Array[MatchResult], spacing: Vector2, bounds: Rect2, low_effects: bool, speed: float) -> void:
	for result: MatchResult in results:
		var entry: ScoreEntry = result.score_entry
		if entry == null or entry.final_score <= 0 or _seen_events.has(entry.event_id): continue
		_seen_events[entry.event_id] = true
		var anchor: Vector2 = bounds.get_center()
		if not result.removed.is_empty() or result.cause == &"explosion":
			anchor = Vector2(result.center) * spacing
			_action_anchors[entry.root_action_id] = anchor
		else:
			anchor = _action_anchors.get(entry.root_action_id, anchor)
		while get_child_count() >= maxi(1, config.maximum_visible):
			var oldest: Node = get_child(0)
			remove_child(oldest)
			oldest.queue_free()
		var card: ScoreFloat = FLOAT.instantiate() as ScoreFloat
		card.config = config
		add_child(card)
		card.configure(entry, result.cause, result.generation)
		card.play(_find_origin(anchor, card.display_size, bounds), low_effects, speed)

func clear(reset_history: bool = false) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	if reset_history:
		_seen_events.clear()
		_action_anchors.clear()

func set_low_effects(enabled: bool) -> void:
	for child: Node in get_children(): (child as ScoreFloat).set_low_effects(enabled)

func set_speed(value: float) -> void:
	for child: Node in get_children(): (child as ScoreFloat).set_speed(value)

func _find_origin(anchor: Vector2, size: Vector2, bounds: Rect2) -> Vector2:
	# 预留整个上漂区域；连续连锁可换列，满屏时淘汰最早的装饰。
	var safe: Rect2 = bounds.grow(-6.0)
	var preferred: Vector2 = anchor - Vector2(size.x * 0.5, size.y + 12.0)
	while true:
		for column: int in [0, -1, 1]:
			for attempt: int in range(maxi(1, config.maximum_visible) * 2):
				var offset: float = ceilf(attempt / 2.0) * (size.y + config.rise_distance + 8.0) * (-1.0 if attempt % 2 else 1.0)
				var origin: Vector2 = Vector2(clampf(preferred.x + column * (size.x + 8.0), safe.position.x, maxf(safe.position.x, safe.end.x - size.x)), clampf(preferred.y + offset, safe.position.y + config.rise_distance, maxf(safe.position.y + config.rise_distance, safe.end.y - size.y)))
				var sweep: Rect2 = Rect2(origin - Vector2(0, config.rise_distance), size + Vector2(0, config.rise_distance))
				if not _overlaps(sweep): return origin
		var oldest: Node = get_child(0)
		remove_child(oldest)
		oldest.queue_free()
	return preferred

func _overlaps(area: Rect2) -> bool:
	for child: Node in get_children():
		var other: ScoreFloat = child as ScoreFloat
		if other.reserved_rect.has_area() and other.reserved_rect.grow(4.0).intersects(area): return true
	return false
