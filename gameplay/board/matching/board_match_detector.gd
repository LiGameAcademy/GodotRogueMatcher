class_name BoardMatchDetector
extends RefCounted

const LINE_DIRECTIONS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i(1, 1), Vector2i(1, -1)]
const MAXIMUM_TEMPLATES: int = 8

## Collect every enabled hit before merging or filtering by the landing entity.
## Production defaults to lines; prototype BoardRules supplies detached construction-time templates.
static func find_matches(state: BoardState, minimum_count: int, templates: Array[MatchShapeTemplate] = []) -> Array[BoardMatchGroup]:
	var error: String = validation_error(templates)
	if not error.is_empty():
		push_error("invalid match template: " + error)
		return []
	var hits: Array[BoardMatchHit] = _lines(state, minimum_count)
	for template: MatchShapeTemplate in templates:
		for variant: MatchShapeTemplate in template.variants():
			for y: int in range(state.rows):
				for x: int in range(state.columns):
					var hit: BoardMatchHit = _template_hit(state, variant, Vector2i(x, y))
					if hit != null: hits.append(hit)
	var groups: Array[BoardMatchGroup] = []
	var seen: Dictionary[String, bool] = {}
	for hit: BoardMatchHit in hits:
		var key: String = String(hit.shape_id) + ":" + str(hit.piece_ids)
		if seen.has(key): continue
		seen[key] = true
		_merge(groups, hit)
	groups.sort_custom(func(a: BoardMatchGroup, b: BoardMatchGroup) -> bool: return a.piece_ids[0] < b.piece_ids[0])
	return groups

static func validation_error(templates: Array[MatchShapeTemplate]) -> String:
	if templates.size() > MAXIMUM_TEMPLATES: return "too many match templates"
	for template: MatchShapeTemplate in templates:
		if template == null: return "template missing"
		var error: String = template.validation_error()
		if not error.is_empty(): return error
	return ""

static func find_matches_at(state: BoardState, minimum_count: int, coordinate: Vector2i, templates: Array[MatchShapeTemplate] = []) -> Array[BoardMatchGroup]:
	var groups: Array[BoardMatchGroup] = []
	var id: int = state.get_piece_id(coordinate)
	if id == 0: return groups
	for group: BoardMatchGroup in find_matches(state, minimum_count, templates):
		if group.piece_ids.has(id): groups.append(group)
	return groups

static func _lines(state: BoardState, minimum_count: int) -> Array[BoardMatchHit]:
	var hits: Array[BoardMatchHit] = []
	for piece: PieceState in state.get_snapshot():
		for direction: Vector2i in LINE_DIRECTIONS:
			var previous: PieceState = state.get_piece_at(piece.coordinate - direction)
			if previous != null and previous.match_color == piece.match_color: continue
			var ids: Array[int] = []
			var coordinate: Vector2i = piece.coordinate
			var current: PieceState = state.get_piece_at(coordinate)
			while current != null and current.match_color == piece.match_color:
				ids.append(current.piece_id)
				coordinate += direction
				current = state.get_piece_at(coordinate)
			if ids.size() >= minimum_count:
				var hit: BoardMatchHit = _hit(state, ids, &"line", piece.coordinate)
				hit.direction = direction
				hits.append(hit)
	return hits

static func _template_hit(state: BoardState, template: MatchShapeTemplate, origin: Vector2i) -> BoardMatchHit:
	var ids: Array[int] = []
	var color: int = -1
	for offset: Vector2i in template.offsets:
		var piece: PieceState = state.get_piece_at(origin + offset)
		if piece == null or (color != -1 and piece.match_color != color): return null
		color = piece.match_color
		ids.append(piece.piece_id)
	return _hit(state, ids, template.shape_id, origin)

static func _hit(state: BoardState, ids: Array[int], shape: StringName, origin: Vector2i) -> BoardMatchHit:
	var hit: BoardMatchHit = BoardMatchHit.new()
	hit.shape_id = shape
	hit.origin = origin
	hit.piece_ids = ids.duplicate()
	hit.piece_ids.sort()
	for id: int in hit.piece_ids: hit.coordinates.append(state.get_piece(id).coordinate)
	return hit

static func _merge(groups: Array[BoardMatchGroup], hit: BoardMatchHit) -> void:
	var merged: BoardMatchGroup = BoardMatchGroup.new()
	merged.piece_ids = hit.piece_ids.duplicate()
	merged.hits = [hit]
	for index: int in range(groups.size() - 1, -1, -1):
		var intersects: bool = false
		for id: int in groups[index].piece_ids:
			if merged.piece_ids.has(id):
				intersects = true
				break
		if not intersects: continue
		for id: int in groups[index].piece_ids:
			if not merged.piece_ids.has(id): merged.piece_ids.append(id)
		merged.hits.append_array(groups[index].hits)
		groups.remove_at(index)
	merged.piece_ids.sort()
	groups.append(merged)
