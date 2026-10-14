class_name CardTransfer
extends CanvasLayer

## Only presents a successfully acquired card. Receives both screen rectangles explicitly.
@onready var card: SkillCard = $SkillCard
@export var duration: float = 0.32
var _flight: Tween

func _exit_tree() -> void:
	cancel()

func play(skill: SkillDefinition, target: SkillTarget, source: Rect2, destination: Rect2, low_effects: bool) -> void:
	cancel()
	if low_effects or source.size.x <= 0.0 or destination.size.x <= 0.0: return
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

func cancel() -> void:
	if _flight != null: _flight.kill()
	if is_node_ready():
		card.finish_reveal()
		card.hide()
