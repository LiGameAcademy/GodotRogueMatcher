class_name CardTransfer
extends CanvasLayer

## Only presents a successfully acquired card. Receives both screen rectangles explicitly.
signal slot_flight_finished

@onready var card: SkillCard = $SkillCard
@export var duration: float = 0.32
var _flight: Tween
@onready var _icon: TextureRect = $FlightIcon
@onready var _outline: Panel = $LandingOutline

func _exit_tree() -> void:
	cancel()

func play(skill: SkillDefinition, target: SkillTarget, source: Rect2, destination: Rect2, low_effects: bool, slot: TextureRect = null) -> void:
	cancel()
	if is_instance_valid(slot):
		if low_effects or not source.has_area() or not destination.has_area():
			slot.texture = SkillMechanicIcons.texture_for(skill.skill_id)
		else:
			_play_icon(skill, source, destination, slot)
		return
	if low_effects or not source.has_area() or not destination.has_area(): return
	card.configure(skill, target)
	card.finish_reveal()
	card.position = source.position
	card.size = source.size
	card.pivot_offset = source.size * 0.5
	card.set_presentation_only()
	card.show()
	var end_scale: float = clampf(destination.size.x / source.size.x, 0.12, 0.30)
	var end_position: Vector2 = destination.get_center() - source.size * 0.5
	_flight = create_tween().set_parallel(true)
	_flight.tween_property(card, "position", end_position, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_flight.tween_property(card, "scale", Vector2.ONE * end_scale, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_flight.tween_property(card, "modulate:a", 0.0, duration * 0.35).set_delay(duration * 0.65)
	_flight.chain().tween_callback(card.hide)

## The card collapses into its skill icon and lands at the visible inventory slot.
func _play_icon(skill: SkillDefinition, source: Rect2, destination: Rect2, slot: TextureRect) -> void:
	_icon.texture = SkillMechanicIcons.texture_for(skill.skill_id)
	_icon.size = Vector2.ONE * minf(source.size.y, 76.0)
	_icon.position = source.get_center() - _icon.size * 0.5
	_icon.show()
	var end_size: Vector2 = Vector2.ONE * clampf(minf(destination.size.x, destination.size.y) - 6.0, 1.0, 38.0)
	_flight = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_flight.tween_property(_icon, "position", destination.get_center() - end_size * 0.5, duration)
	_flight.tween_property(_icon, "size", end_size, duration)
	_outline.position = destination.position
	_outline.size = destination.size
	_outline.modulate.a = 1.0
	_flight.chain().tween_callback(_land_icon.bind(slot))
	_flight.chain().tween_property(_outline, "modulate:a", 0.0, 0.42).set_delay(0.28)
	_flight.chain().tween_callback(_outline.hide)

## Returns immediately for desktop cards, reduced effects or an already landed icon.
func wait_for_slot() -> void:
	if _icon.visible: await slot_flight_finished

func _land_icon(slot: TextureRect) -> void:
	if is_instance_valid(slot): slot.texture = _icon.texture
	_outline.show()
	_finish_slot_flight()

func _finish_slot_flight() -> void:
	if not _icon.visible: return
	_icon.hide()
	slot_flight_finished.emit()

func cancel() -> void:
	if _flight != null: _flight.kill()
	if is_node_ready():
		_outline.hide()
		card.finish_reveal()
		card.hide()
		_finish_slot_flight()
