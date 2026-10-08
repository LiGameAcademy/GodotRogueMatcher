class_name SpawnPreview
extends Control

@onready var title: Label = $Title
@onready var hint: Label = $Hint
var _tokens: Array[SpawnToken] = []

func show_plan(tokens: Array[SpawnToken], finished: bool = false) -> void:
	_tokens.clear()
	if not finished:
		for token: SpawnToken in tokens: _tokens.append(token.copy())
	title.text = tr("本局已结束") if finished else tr("下次补棋 · %d 枚") % tokens.size()
	hint.text = "" if finished else tr("五连免补棋 · 全清除外")
	if not finished and tokens.is_empty():
		title.text = tr("等待下一批预告")
		hint.text = tr("本次补棋结算后刷新")
	elif not finished and tokens.any(func(token: SpawnToken) -> bool: return token.core_candidate):
		hint.text = tr("爆?：已有核心则转普通棋")
	tooltip_text = tr("按从左到右的顺序补棋；落点随机。直接五连且棋盘未全清时保留这批预告。\n颜色权重调整只影响尚未生成的预告。爆? 表示爆破手候选：出生时场上已有爆破手则改为图中普通颜色。")
	queue_redraw()

func _draw() -> void:
	for index: int in range(_tokens.size()):
		var token: SpawnToken = _tokens[index]
		var center: Vector2 = Vector2(18 + index * 36, 37)
		draw_style_box(get_theme_stylebox("normal", "Button"), Rect2(center - Vector2(16, 16), Vector2(32, 32)))
		var color: Color = ChessPiece.color_for(token.color)
		if token.color == ChessPiece.ShapeType.CIRCLE:
			draw_circle(center, 9.0, color)
		else:
			var points: PackedVector2Array = PackedVector2Array()
			var vertices: int = [0, 4, 3, 5, 10][token.color]
			for vertex: int in range(vertices):
				var angle: float = TAU * vertex / vertices - PI / 2.0
				if token.color == ChessPiece.ShapeType.SQUARE: angle += PI / 4.0
				var radius: float = 4.4 if token.color == ChessPiece.ShapeType.STAR and vertex % 2 == 1 else 11.0
				points.append(center + Vector2(cos(angle), sin(angle)) * radius)
			draw_colored_polygon(points, color)
		if token.core_candidate:
			draw_string(get_theme_default_font(), center + Vector2(-11, 4), tr("爆?"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
