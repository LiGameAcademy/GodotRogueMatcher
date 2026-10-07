class_name RecordViewData
extends RefCounted

## 只解码表现需要的数据；不恢复或修改游戏规则。
static func coordinate(value: Variant) -> Vector2i:
	if not value is Array or value.size() != 2: return Vector2i(-1, -1)
	for component: Variant in value:
		if not CommandCodec.valid_integer(component) or component.to_int() < 0 or component.to_int() >= 64: return Vector2i(-1, -1)
	return Vector2i(value[0].to_int(), value[1].to_int())

static func piece(data: Dictionary) -> PieceState:
	if not CommandCodec.valid_integer(data.get("id")) or not CommandCodec.valid_integer(data.get("color")): return null
	if not data.get("content_id") is String or not data.get("ghost") is bool: return null
	var cell: Vector2i = coordinate(data.get("coordinate"))
	if cell.x < 0 or data.id.to_int() <= 0 or data.color.to_int() < 0 or data.color.to_int() > 4: return null
	var result: PieceState = PieceState.new()
	result.piece_id = data.id.to_int()
	result.coordinate = cell
	result.match_color = data.color.to_int()
	result.content_id = StringName(data.content_id)
	result.is_ghost = data.ghost
	return result

static func snapshot(state: Dictionary, dimensions: Vector2i) -> Array[PieceState]:
	var result: Array[PieceState] = []
	var ids: Dictionary[int, bool] = {}
	var cells: Dictionary[Vector2i, bool] = {}
	if not state.get("pieces") is Array: return result
	for value: Variant in state.pieces:
		if not value is Dictionary: return []
		var current: PieceState = piece(value)
		if current == null or current.coordinate.x >= dimensions.x or current.coordinate.y >= dimensions.y or ids.has(current.piece_id) or cells.has(current.coordinate): return []
		ids[current.piece_id] = true
		cells[current.coordinate] = true
		result.append(current)
	return result

static func valid_state(value: Variant, dimensions: Vector2i) -> bool:
	if not value is Dictionary or not value.get("pieces") is Array: return false
	if snapshot(value, dimensions).size() != value.pieces.size(): return false
	for key: String in ["total", "moves", "consumed"]:
		if not CommandCodec.valid_integer(value.get(key)): return false
	if not value.get("instances", []) is Array: return false
	for instance: Variant in value.get("instances", []):
		if not instance is Dictionary or not CommandCodec.valid_integer(instance.get("id")): return false
	return true

static func valid_pieces(value: Variant, dimensions: Vector2i) -> bool:
	if not value is Array: return false
	for data: Variant in value:
		if not data is Dictionary: return false
		var current: PieceState = piece(data)
		if current == null or current.coordinate.x >= dimensions.x or current.coordinate.y >= dimensions.y: return false
	return true

static func valid_events(value: Variant, dimensions: Vector2i) -> bool:
	if not value is Array: return false
	for event: Variant in value:
		if not event is Dictionary or not event.get("cause") is String or not valid_pieces(event.get("removed"), dimensions): return false
		if event.cause == "explosion":
			var center: Vector2i = coordinate(event.get("center"))
			if center.x < 0 or center.x >= dimensions.x or center.y >= dimensions.y: return false
			if not CommandCodec.valid_integer(event.get("radius")) or event.radius.to_int() < 0 or event.radius.to_int() > 64: return false
	return true

static func valid_record(row: Dictionary, dimensions: Vector2i) -> bool:
	match row.get("kind"):
		"Offer":
			if not row.get("offer") is Dictionary or not row.offer.get("choices") is Array: return false
			for id: Variant in row.offer.choices:
				if not id is String: return false
		"SkillAcquired":
			if not valid_pieces(row.get("created"), dimensions) or not valid_pieces(row.get("removed"), dimensions): return false
		"RuleResult":
			if not valid_state(row.get("after"), dimensions): return false
			if row.has("before") and not valid_state(row.before, dimensions): return false
			if not valid_pieces(row.get("removed", []), dimensions): return false
			if not valid_events(row.get("events", []), dimensions) or not row.get("births", []) is Array: return false
			for birth: Variant in row.get("births", []):
				if not birth is Dictionary or not birth.get("piece") is Dictionary: return false
				if not valid_pieces([birth.piece], dimensions) or not valid_events(birth.get("events"), dimensions): return false
			if not row.get("move", {}) is Dictionary: return false
			var movement: Dictionary = row.get("move", {})
			if not movement.is_empty():
				if not CommandCodec.valid_integer(movement.get("piece_id")) or not movement.get("path") is Array: return false
				if movement.path.is_empty() or movement.path.size() > 4096: return false
				for cell: Variant in movement.path:
					var point: Vector2i = coordinate(cell)
					if point.x < 0 or point.x >= dimensions.x or point.y >= dimensions.y: return false
		"Footer":
			if not valid_state(row.get("final"), dimensions) or not row.get("status") is String or not row.get("reason") is String: return false
	return true
