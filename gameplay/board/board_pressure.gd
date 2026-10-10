class_name BoardPressure
extends RefCounted

## 四邻空格连通代理；不读取得分、随机数或UI，不控制生死。
static func evaluate(columns: int, rows: int, occupied: Array[Vector2i], alpha: float) -> Dictionary:
	if columns <= 0 or rows <= 0 or not is_finite(alpha) or alpha < 0.0 or alpha > 1.0: return {}
	var cells: Dictionary[Vector2i, bool] = {}
	for coordinate: Vector2i in occupied:
		if coordinate.x < 0 or coordinate.y < 0 or coordinate.x >= columns or coordinate.y >= rows: return {}
		cells[coordinate] = true
	var remaining: Dictionary[Vector2i, bool] = {}
	for x: int in range(columns):
		for y: int in range(rows):
			var coordinate: Vector2i = Vector2i(x, y)
			if not cells.has(coordinate): remaining[coordinate] = true
	var empty: int = remaining.size()
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
	var fragmentation: float = 1.0 - float(largest) / empty if empty > 0 else 1.0
	var value: float = 100.0 * clampf(alpha * cells.size() / (columns * rows) + (1.0 - alpha) * fragmentation, 0.0, 1.0)
	return {"n": cells.size(), "empty": empty, "L": largest, "P": value, "alpha": alpha}
