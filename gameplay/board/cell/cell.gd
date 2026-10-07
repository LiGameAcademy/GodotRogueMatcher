extends Node2D
class_name Cell

## 只负责格子外观与输入通知，不存储占格或提交规则。
@onready var background: ColorRect = %Background
@onready var area_2d: Area2D = %Area2D
@export var default_bg_color: Color = Color("101a26")
@export var default_border_color: Color = Color("26384a")
@export var highlight_bg_color: Color = Color("173b40")
@export var highlight_glow_color: Color = Color("a1eee3")
@export var path_highlight_color: Color = Color("74ddcf")
@export var hover_color: Color = Color("1c2e40")
var coordinate: Vector2i = Vector2i.ZERO
var low_effects: bool = false
var is_path_highlighted: bool = false
var is_hovered: bool = false
var _selected: bool = false
var _surface: ShaderMaterial
var _flash: Tween
var piece: ChessPiece:
	get:
		return get_node_or_null("Piece") as ChessPiece

signal pressed(cell: Cell)
signal activated(cell: Cell)

func _ready() -> void:
	_surface = background.material.duplicate() as ShaderMaterial
	background.material = _surface
	area_2d.input_event.connect(_on_area_2d_input_event)
	area_2d.mouse_entered.connect(_on_mouse_entered)
	area_2d.mouse_exited.connect(_on_mouse_exited)
	_refresh_style()

func show_piece(display_piece: ChessPiece) -> void:
	display_piece.name = "Piece"
	add_child(display_piece)

func take_piece() -> ChessPiece:
	var display_piece: ChessPiece = piece
	if is_instance_valid(display_piece): remove_child(display_piece)
	return display_piece

func set_low_effects(enabled: bool) -> void:
	low_effects = enabled
	if _flash != null and _flash.is_valid(): _flash.kill()
	background.modulate = Color.WHITE
	_refresh_style()

func highlight() -> void:
	_selected = true
	_refresh_style()

func highlight_path() -> void:
	is_path_highlighted = true
	_refresh_style()

func unhighlight() -> void:
	_selected = false
	is_path_highlighted = false
	_refresh_style()

func _refresh_style() -> void:
	if _surface == null: return
	var edge: Color = default_border_color
	background.color = default_bg_color
	if is_path_highlighted:
		background.color = highlight_bg_color
		edge = path_highlight_color
	elif _selected:
		background.color = highlight_bg_color
		edge = highlight_glow_color
	elif is_hovered:
		background.color = hover_color
		edge = Color("618899")
	_surface.set_shader_parameter("edge_color", edge)

func _on_mouse_entered() -> void:
	is_hovered = true
	_refresh_style()

func _on_mouse_exited() -> void:
	is_hovered = false
	_refresh_style()

func _on_area_2d_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			_click_feedback()
			if button.double_click: activated.emit(self)
			else: pressed.emit(self)

func _click_feedback() -> void:
	if low_effects: return
	if _flash != null and _flash.is_valid(): _flash.kill()
	background.modulate = Color(1.15, 1.15, 1.15, 1.0)
	_flash = create_tween()
	_flash.tween_property(background, "modulate", Color.WHITE, 0.12)

func _to_string() -> String:
	return name + ":" + str(coordinate)
