class_name BoardObservation
extends RefCounted

var telemetry: TelemetryProjector
var buffered_input: String = ""
var _busy: bool = true
var _choice: bool = false
var _paused: bool = false
var _focused: bool = true
var _ui: String = ""

func ui_location(value: String) -> void:
	_ui = value
	_refresh()

func attach(projector: TelemetryProjector) -> void:
	telemetry = projector
	buffered_input = ""
	_busy = true
	_choice = false
	_paused = false
	_ui = ""

func busy(value: bool) -> void:
	_busy = value
	_refresh()

func paused(value: bool) -> void:
	_paused = value
	_refresh()

func focused(value: bool) -> void:
	_focused = value
	_refresh()

func present_offer(offer: SkillOffer) -> void:
	_choice = true
	_refresh()
	if telemetry == null: return
	var order: Array[String] = []
	for skill: SkillDefinition in offer.choices: order.append(String(skill.skill_id))
	telemetry.offer_presented(offer.offer_id, order)

func selecting_skill() -> void:
	_choice = false
	_refresh()

func input(type: String, buffered: bool = false) -> String:
	return telemetry.begin_input(type, buffered) if telemetry != null else ""

func resolve(id: String, disposition: String, reason: String = "", command_id: Variant = null, wait_ms: int = 0) -> void:
	if telemetry != null: telemetry.resolve_input(id, disposition, reason, command_id, wait_ms)

func cancel_buffer(reason: String) -> void:
	resolve(buffered_input, "overwritten" if reason == "overwritten" else "cancelled", reason)
	buffered_input = ""

func _refresh() -> void:
	if telemetry == null: return
	var category: String = "inactive" if not _focused else "pause" if _paused else "choice" if _choice else "busy" if _busy else "input"
	telemetry.set_interval(category)
	telemetry.ui_location(_ui if not _ui.is_empty() else "skill_choice" if _choice else "pause" if _paused else "presentation" if _busy else "board_input")
