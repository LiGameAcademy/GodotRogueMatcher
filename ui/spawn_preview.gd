class_name SpawnPreview
extends Control

@onready var title: Label = $Title
@onready var hint: Label = $Hint
var _tokens: Array[SpawnToken] = []
var _game_theme: GameTheme
var _consumed_slots: Array[int] = []
var _flight_origins: Dictionary[int, Transform2D] = {}
var _flight_slots: Dictionary[int, int] = {}
var _plan_revision: int = 0
var _flight_revision: int = -1
const SLOT_COUNT: int = 6

func apply_game_theme(preset: GameTheme) -> void:
	_game_theme = preset
	queue_redraw()

func show_plan(tokens: Array[SpawnToken], finished: bool = false) -> void:
	_plan_revision += 1
	_tokens.clear()
	_consumed_slots.clear()
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

## Freezes visible slot origins before playback or HUD refresh; no random draws.
func prepare_flight(results: Array[SpawnResult]) -> void:
	_flight_origins.clear()
	_flight_slots.clear()
	_flight_revision = _plan_revision
	if not is_visible_in_tree(): return
	for slot: int in range(mini(SLOT_COUNT, mini(results.size(), _tokens.size()))):
		var result: SpawnResult = results[slot]
		if result.source not in [&"normal", &"empty_recovery"]: continue
		if _tokens[slot].color != result.piece.match_color: continue
		var local: Transform2D = Transform2D(0.0, Vector2.ONE * 0.5, 0.0, Vector2(18 + slot * 36, 32))
		_flight_origins[result.piece.piece_id] = get_global_transform_with_canvas() * local
		_flight_slots[result.piece.piece_id] = slot

## Consumes only frozen display identity; the run has already committed this birth.
func take_origin(piece: PieceState, slot: int) -> Variant:
	if not _flight_origins.has(piece.piece_id) or _flight_slots[piece.piece_id] != slot: return null
	var origin: Transform2D = _flight_origins[piece.piece_id]
	_flight_origins.erase(piece.piece_id)
	_flight_slots.erase(piece.piece_id)
	if _flight_revision == _plan_revision:
		_consumed_slots.append(slot)
		queue_redraw()
	return origin

func _draw() -> void:
	for index: int in range(SLOT_COUNT):
		var slot: Rect2 = Rect2(Vector2(2 + index * 36, 16), Vector2(32, 32))
		draw_style_box(get_theme_stylebox("normal", "Button"), slot)
	for index: int in range(_tokens.size()):
		if _consumed_slots.has(index): continue
		var token: SpawnToken = _tokens[index]
		var center: Vector2 = Vector2(18 + index * 36, 32)
		NutVisual.draw_on(self, token.color, Rect2(center - Vector2(16, 16), Vector2(32, 32)))
		if token.core_candidate:
			var marker: Color = _game_theme.board.marker_color if _game_theme != null else Color.WHITE
			draw_string(get_theme_default_font(), center + Vector2(6, -7), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, marker)
