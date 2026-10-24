class_name SpawnPreview
extends Control

@onready var title: Label = $Title
@onready var hint: Label = $Hint
var _tokens: Array[SpawnToken] = []
var _game_theme: GameTheme
const SLOT_COUNT: int = 6

func apply_game_theme(preset: GameTheme) -> void:
	_game_theme = preset
	queue_redraw()

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
	for index: int in range(SLOT_COUNT):
		var slot: Rect2 = Rect2(Vector2(2 + index * 36, 16), Vector2(32, 32))
		draw_style_box(get_theme_stylebox("normal", "Button"), slot)
	for index: int in range(_tokens.size()):
		var token: SpawnToken = _tokens[index]
		var center: Vector2 = Vector2(18 + index * 36, 32)
		NutVisual.draw_on(self, token.color, Rect2(center - Vector2(16, 16), Vector2(32, 32)))
		if token.core_candidate:
			var marker: Color = _game_theme.board.marker_color if _game_theme != null else Color.WHITE
			draw_string(get_theme_default_font(), center + Vector2(6, -7), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, marker)
