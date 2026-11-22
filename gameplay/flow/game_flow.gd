extends Node

## Application navigation owns one value state and at most one outstanding scene handoff.
enum Page { BOOT, PLAY, RESULT, ROOM }
const ROOM: String = "res://ui/preparation_room/preparation_room.tscn"
const GAME: String = "res://gameplay/room_session.tscn"
var machine: CoreStateMachine = CoreStateMachine.new(Page.BOOT, [Page.BOOT, Page.PLAY, Page.RESULT, Page.ROOM], _allowed)
var _pending: int = -1

func _ready() -> void:
	# Keep the platform's keyboard bindings and add the two menu buttons.
	for action: StringName in [&"ui_accept", &"ui_cancel"]:
		var button: InputEventJoypadButton = InputEventJoypadButton.new()
		button.device = -1
		button.button_index = JOY_BUTTON_A if action == &"ui_accept" else JOY_BUTTON_B
		if not InputMap.action_has_event(action, button):
			InputMap.action_add_event(action, button)
	CoreSystem.scene_manager.scene_changed.connect(_arrived)
	CoreSystem.scene_manager.scene_loading_finished.connect(_finished)

func travel(target: Page, data: Dictionary) -> bool:
	if _pending != -1 or not _allowed(machine.current, target): return false
	_pending = target
	CoreSystem.scene_manager.change_scene_async(ROOM if target == Page.ROOM else GAME, data)
	return true

## A deferred scene can enter the tree on either side of the handoff notification.
func wait_for_handoff() -> void:
	if _pending != -1:
		await CoreSystem.scene_manager.scene_loading_finished

func show_result() -> bool:
	return machine.try_transition(Page.RESULT)

func continue_challenge() -> void:
	machine.try_transition(Page.PLAY)

func _arrived(_old: Node, scene: Node) -> void:
	if _pending != -1 and scene.scene_file_path == (ROOM if _pending == Page.ROOM else GAME):
		machine.try_transition(_pending)

func _finished() -> void:
	_pending = -1

func _allowed(from: int, to: int) -> bool:
	match from:
		Page.BOOT: return to in [Page.PLAY, Page.ROOM]
		Page.ROOM: return to == Page.PLAY
		Page.PLAY: return to in [Page.RESULT, Page.ROOM]
		Page.RESULT: return to in [Page.ROOM, Page.PLAY]
	return false
