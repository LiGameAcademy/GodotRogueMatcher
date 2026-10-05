class_name PieceState
extends RefCounted

## 单枚棋子的运行数据；快照不包含显示节点或共享配置。
var piece_id: int = 0
var coordinate: Vector2i = Vector2i.ZERO
var match_color: int = 0
var content_id: StringName = &""
var is_ghost: bool = false

func copy() -> PieceState:
	var result: PieceState = PieceState.new()
	result.piece_id = piece_id
	result.coordinate = coordinate
	result.match_color = match_color
	result.content_id = content_id
	result.is_ghost = is_ghost
	return result
