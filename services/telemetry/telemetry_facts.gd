class_name TelemetryFacts
extends RefCounted

const CONFIG: TelemetryConfig = preload("res://services/telemetry/telemetry_config.tres")

## 纯快照观察；不持有真实棋盘或随机对象，不改变候选权重。
static func pressure(state: Dictionary, columns: int, rows: int) -> Dictionary:
	var occupied: Dictionary[Vector2i, bool] = {}
	for piece: Dictionary in state.get("pieces", []):
		occupied[Vector2i(int(piece.coordinate[0]), int(piece.coordinate[1]))] = true
	var empty: Dictionary[Vector2i, bool] = {}
	for x: int in range(columns):
		for y: int in range(rows):
			var coordinate: Vector2i = Vector2i(x, y)
			if not occupied.has(coordinate): empty[coordinate] = true
	var remaining: Dictionary[Vector2i, bool] = empty.duplicate()
	var largest: int = 0
	while not remaining.is_empty():
		var queue: Array[Vector2i] = [remaining.keys()[0]]
		remaining.erase(queue[0])
		var cursor: int = 0
		while cursor < queue.size():
			var current: Vector2i = queue[cursor]
			cursor += 1
			for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var neighbor: Vector2i = current + direction
				if remaining.erase(neighbor): queue.append(neighbor)
		largest = maxi(largest, queue.size())
	var fragmentation: float = 1.0 - float(largest) / empty.size() if not empty.is_empty() else 1.0
	var capacity: int = columns * rows
	var value: float = 100.0 * (CONFIG.occupancy_weight * occupied.size() / capacity + (1.0 - CONFIG.occupancy_weight) * fragmentation)
	return {"n": occupied.size(), "empty": empty.size(), "L": largest, "P": value, "alpha": CONFIG.occupancy_weight, "version": CONFIG.pressure_version}

static func stage(state: Dictionary, config: Dictionary) -> Dictionary:
	var value: Dictionary = state.get("challenge", {})
	var modifiers: Dictionary = state.get("spawning", {}).get("refill_batches", {})
	var delta: int = (1 if int(modifiers.get("1", "0")) > 0 else 0) - (1 if int(modifiers.get("-1", "0")) > 0 else 0)
	if not value.get("enabled", false): return {"enabled": false, "u": null, "T": null, "q": clampi(int(config.get("spawning", {}).get("refill_count", "3")) + delta, 1, 6)}
	var index: int = int(value.index)
	var table: Dictionary = config.challenge
	if index < 0 or index >= table.get("targets", []).size(): return {"enabled": true, "invalid": true}
	var base: int = int(table.base_refill) if value.awaiting_reward else mini(int(table.maximum_refill), int(table.base_refill) + int(float(value.used_actions) / int(table.pressure_intervals[index])))
	var next_count: int = clampi(base + delta, 1, 6)
	return {"enabled": true, "stage_id": index + 1, "u": value.used_actions, "q": next_count, "base_q": base, "T": table.targets[index], "action_score": value.action_score, "carry": value.carry_in, "missing": maxi(0, int(table.targets[index]) - int(value.action_score) - int(value.carry_in)), "awaiting_reward": value.awaiting_reward}

static func ending(status: String) -> String:
	return {"completed": "gameplay_terminal", "abandoned": "user_stop", "censored": "tool_censored", "rule_error": "error"}.get(status, "error")
