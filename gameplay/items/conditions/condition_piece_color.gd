extends GameplayCondition
class_name ConditionPieceColor

## 棋子颜色条件

## 目标颜色（-1 表示任意颜色）
@export var target_color: int = -1

func _init(color: int = -1) -> void:
	condition_id = "piece_color"
	target_color = color

func check(context: Dictionary = {}) -> bool:
	if target_color < 0:
		return true  # 任意颜色都满足
	
	var matched_cells: Array = context.get("matched_cells", [])
	if matched_cells.is_empty():
		return false
	
	# 检查是否有指定颜色的棋子
	for cell in matched_cells:
		if cell is Cell:
			var cell_obj = cell as Cell
			if cell_obj.piece and cell_obj.piece.display_mode == ChessPiece.DisplayMode.SHAPE:
				if cell_obj.piece.piece_type == target_color:
					return true
	
	return false

func get_description() -> String:
	if target_color < 0:
		return "任意颜色"
	return "颜色 " + str(target_color)

