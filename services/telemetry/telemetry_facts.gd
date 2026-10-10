class_name TelemetryFacts
extends RefCounted

const CONFIG: TelemetryConfig = preload("res://services/telemetry/telemetry_config.tres")

## 纯快照观察；不持有真实棋盘或随机对象，不改变候选权重。
static func pressure(state: Dictionary, columns: int, rows: int) -> Dictionary:
	var occupied: Array[Vector2i] = []
	for piece: Dictionary in state.get("pieces", []): occupied.append(Vector2i(int(piece.coordinate[0]), int(piece.coordinate[1])))
	var result: Dictionary = BoardPressure.evaluate(columns, rows, occupied, CONFIG.occupancy_weight)
	result["version"] = CONFIG.pressure_version
	return result

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
	var cumulative: int = 0
	for stage_index: int in range(index + 1): cumulative += int(table.targets[stage_index])
	return {"enabled": true, "stage_id": index + 1, "u": value.used_actions, "q": next_count, "base_q": base, "T": table.targets[index], "target_total": cumulative, "score_total": state.total, "action_score": value.action_score, "carry": value.carry_in, "missing": maxi(0, cumulative - int(state.total)), "awaiting_reward": value.awaiting_reward}

static func ending(status: String) -> String:
	return {"completed": "gameplay_terminal", "abandoned": "user_stop", "censored": "tool_censored", "rule_error": "error"}.get(status, "error")
