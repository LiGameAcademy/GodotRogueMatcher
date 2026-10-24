class_name NutVisual
extends Node2D

## 只读纹理与统一五官坐标；棋盘、预告共同使用同一绘制入口。
const BODIES: Array[Texture2D] = [
	preload("res://assets/textures/pieces/peanut_body.png"),
	preload("res://assets/textures/pieces/cashew_body.png"),
	preload("res://assets/textures/pieces/almond_body.png"),
	preload("res://assets/textures/pieces/walnut_body.png"),
	preload("res://assets/textures/pieces/pistachio_body.png"),
]
const EYES: Texture2D = preload("res://assets/textures/faces/eyes_idle.png")
const CLOSED_EYES: Texture2D = preload("res://assets/textures/faces/eyes_blink_closed.png")
const MOUTH: Texture2D = preload("res://assets/textures/faces/mouth_smile.png")
const EYE_ANCHOR: Vector2 = Vector2(0.34, 0.57)
const MOUTH_ANCHOR: Vector2 = Vector2(0.34, 0.68)
@export var idle_config: NutIdleConfig = preload("res://gameplay/board/piece/nut_idle_config.tres")
@onready var blink_timer: Timer = $BlinkTimer
var eyes_closed: bool = false
var _idle_enabled: bool = false
var _identity: int = -1
var _cosmetic_random: RandomNumberGenerator = RandomNumberGenerator.new()
@export var nut_type: int = 0:
	set(value):
		nut_type = posmod(value, BODIES.size())
		queue_redraw()

func _ready() -> void:
	blink_timer.timeout.connect(_on_blink_timeout)

func _draw() -> void:
	draw_on(self, nut_type, Rect2(-32, -32, 64, 64), eyes_closed)

## 显式传入显示实例ID，仅用于本节点的装饰随机，不读玩法随机流。
func configure_idle(identity: int, enabled: bool) -> void:
	if identity == _identity and enabled == _idle_enabled: return
	if identity != _identity:
		_identity = identity
		_cosmetic_random.seed = identity * 104729 + 17
	_idle_enabled = enabled
	blink_timer.stop()
	eyes_closed = false
	queue_redraw()
	if enabled: _start_wait(idle_config.first_blink_range)

func _on_blink_timeout() -> void:
	if not _idle_enabled: return
	eyes_closed = not eyes_closed
	queue_redraw()
	if eyes_closed: blink_timer.start(idle_config.closed_seconds)
	else: _start_wait(idle_config.blink_interval_range)

func _start_wait(interval: Vector2) -> void:
	blink_timer.start(_cosmetic_random.randf_range(interval.x, interval.y))

static func draw_on(canvas: CanvasItem, index: int, bounds: Rect2, closed: bool = false) -> void:
	canvas.draw_texture_rect(BODIES[posmod(index, BODIES.size())], bounds, false)
	_draw_face(canvas, CLOSED_EYES if closed else EYES, bounds, EYE_ANCHOR, 0.36, 0.56 if closed else 0.52)
	_draw_face(canvas, MOUTH, bounds, MOUTH_ANCHOR, 0.23, 0.547)

static func _draw_face(canvas: CanvasItem, texture: Texture2D, bounds: Rect2, anchor: Vector2, width_ratio: float, pivot_y: float) -> void:
	var width: float = bounds.size.x * width_ratio
	var face_size: Vector2 = Vector2(width, width * texture.get_height() / texture.get_width())
	canvas.draw_texture_rect(texture, Rect2(bounds.position + bounds.size * anchor - face_size * Vector2(0.5, pivot_y), face_size), false)
