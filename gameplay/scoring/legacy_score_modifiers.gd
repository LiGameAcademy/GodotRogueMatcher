class_name LegacyScoreModifiers
extends RefCounted

## 原型道具兼容规则，读取权威快照；后续Ability迁移时移交具体效果。
static func calculate(state: BoardState, group: BoardMatchGroup) -> float:
	var multiplier: float = 1.0
	var bonus: float = 0.0
	var targets: Array[PieceState] = []
	var has_red: bool = false
	for piece_id: int in group.piece_ids:
		var piece: PieceState = state.get_piece(piece_id)
		targets.append(piece)
		if piece.content_id.is_empty() and piece.match_color == 0:
			has_red = true
	for item: PieceState in state.get_snapshot():
		match item.content_id:
			&"prism_tower":
				if group.piece_ids.has(item.piece_id):
					multiplier *= 2.0
			&"amplifier":
				for target: PieceState in targets:
					var offset: Vector2i = target.coordinate - item.coordinate
					if absi(offset.x) <= 1 and absi(offset.y) <= 1:
						bonus += 1.0
						break
			&"ether_totem":
				if has_red:
					multiplier *= 1.5
			&"energy_core":
				bonus += 0.5
	return multiplier + bonus
