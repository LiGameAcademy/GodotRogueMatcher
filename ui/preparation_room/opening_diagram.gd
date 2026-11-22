extends Control

## Each pair depicts a local board position before and after the role's action.
const POSITIONS: Dictionary = {
	&"standard": ["GG.GG", "..G..", ".....", "....."],
	&"row_sweep": ["RRSGG", "..R..", ".....", "....."],
	&"dyer": ["GGGGG", "..R..", ".....", "..G.."],
	&"bomber": [".RBR.", ".GGG.", ".....", "....."],
}
var _opening: StringName = &"standard"

func preview(opening: StringName) -> void:
	_opening = opening
	queue_redraw()

func _draw() -> void:
	var rows: Array = POSITIONS[_opening]
	var cell: float = minf(20.0, size.x / 12.0)
	for panel: int in range(2):
		for row: int in range(2):
			for col: int in range(5):
				var origin: Vector2 = Vector2((col + 7 * panel) * cell, row * cell)
				draw_rect(Rect2(origin, Vector2.ONE * (cell - 1)), Color("#343f43"))
				var token: String = rows[panel * 2 + row][col]
				if token == ".": continue
				var center: Vector2 = origin + Vector2.ONE * cell * 0.47
				var color: Color = Color("#a4d879") if token == "G" else Color("#e69b78")
				draw_circle(center, cell * 0.35, color, true, -1, true)
				if token == "S" or token == "B":
					draw_line(center - Vector2.RIGHT * 4, center + Vector2.RIGHT * 4, Color.BLACK, 2)
					if token == "B": draw_line(center - Vector2.DOWN * 4, center + Vector2.DOWN * 4, Color.BLACK, 2)
	var tip: Vector2 = Vector2(6.6, 1.0) * cell
	draw_line(Vector2(5.3, 1.0) * cell, tip, Color.WHITE, 2)
	draw_line(tip, tip + Vector2(-4, -4), Color.WHITE, 2)
	draw_line(tip, tip + Vector2(-4, 4), Color.WHITE, 2)
