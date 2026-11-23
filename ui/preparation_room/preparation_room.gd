extends Control

## Owns the home and character selection views. No playable run is created here.
const SESSION: String = "res://gameplay/room_session.tscn"
const ROLE: Script = preload("res://gameplay/openings/opening_role.gd")
const LOCALES: Array[String] = ["auto", "en_US", "zh_CN"]

@export var checkpoint_directory: String = "user://run_checkpoint"
var _entry: Dictionary = {}
var _selected: StringName = &"standard"
var _saved: Dictionary = {}
var _loaded: bool = false
var _window: Window
var _original_canvas: Vector2i
var _portrait: bool = false
var _departing: bool = false
var _preferences: PlayerPreferences = PlayerPreferences.new()
@onready var _cards: Dictionary[StringName, Button] = {&"standard": %Standard, &"row_sweep": %Scout, &"dyer": %Dyer, &"bomber": %Bomber}
@onready var _home: Control = %Home
@onready var _characters: Control = %Characters
@onready var _mode: OptionButton = %Mode
@onready var _slot: GameCheckpointFlow = $Slot
@onready var _confirm: ConfirmationDialog = $Confirm
@onready var _settings: PlaybackSettings = $PlaybackSettings
@onready var _tutorial: Tutorial = $Tutorial
@onready var _pool: SkillPool = $SkillPool
@onready var _collection: RunCollection = $RunCollection
@onready var _records: CollectionControls = %Records

func init_state(data: Dictionary) -> void:
	_entry = data.duplicate(true)
	checkpoint_directory = _entry.get("directory", checkpoint_directory)

func _ready() -> void:
	_window = get_window()
	_original_canvas = _window.content_scale_size
	_window.size_changed.connect(_layout.call_deferred)
	for overlay: Control in [_settings.panel, _pool.panel, _tutorial]:
		overlay.visibility_changed.connect(_layout.call_deferred)
	_layout()
	_home.hide()
	_characters.hide()
	if not _entry.is_empty():
		await GameFlow.wait_for_handoff()
	_preferences.load_values()
	%Continue.pressed.connect(_launch.bind(true))
	%New.pressed.connect(_new_game)
	for id: StringName in _cards:
		_cards[id].pressed.connect(_choose.bind(id))
	%Depart.pressed.connect(_ask_to_depart)
	%Back.pressed.connect(_show_home)
	%Practice.pressed.connect(_practice)
	%Pool.pressed.connect(_open_pool)
	%Settings.pressed.connect(_open_settings)
	%Language.item_selected.connect(_language)
	%Language.select(maxi(0, LOCALES.find(_preferences.get_language_preference())))
	_tutorial.finished.connect(_practice_finished)
	_confirm.confirmed.connect(_launch.bind(false))
	_confirm.canceled.connect(_restore_focus.call_deferred)
	_confirm.window_input.connect(_confirm_input)
	CoreSystem.scene_manager.scene_loading_failed.connect(_failed)
	_settings.fast_requested.connect(_preference.bind(&"fast"))
	_settings.low_effects_requested.connect(_preference.bind(&"low_effects"))
	_settings.background_motion_requested.connect(_preference.bind(&"background_motion"))
	_settings.board_signal_requested.connect(_preference.bind(&"board_signal"))
	_settings.theme_requested.connect(_preference.bind(&"theme_id"))
	_settings.volume_requested.connect(CoreSystem.audio_manager.set_master_volume)
	_settings.volume_committed.connect(_preference.bind(&"volume"))
	_slot.use_snapshot = true
	await _slot.inspect_slot(checkpoint_directory)
	_saved = _slot.saved_summary()
	for mode: GameModeDefinition in GameModes.ALL:
		_mode.add_item(tr(mode.title))
	var mode_id: StringName = StringName(_entry.get("mode", _slot.saved_mode))
	_mode.select(maxi(0, GameModes.ALL.find(GameModes.find(mode_id))))
	_selected = StringName(_entry.get("opening", "standard"))
	await _collection.configure_platform("web_playtest" if OS.has_feature("web") else ("desktop_playtest" if OS.has_feature("template") else "editor_playtest"))
	_records.bind_collection(_collection, get_tree().quit, true)
	_collection.status_changed.connect(_record_status)
	_loaded = true
	%Status.text = "" if _slot.last_error.is_empty() else tr("checkpoint.load_failed")
	if _entry.get("select", false) and mode_id == &"stage_challenge": _show_characters()
	else: _show_home()

func _exit_tree() -> void:
	if is_instance_valid(_window) and _portrait:
		_window.set_deferred("content_scale_size", _original_canvas)

## Give the preparation room a portrait canvas while it owns the window.
func _layout() -> void:
	if not is_inside_tree() or not is_instance_valid(_window): return
	var pixels: Vector2i = _window.size
	var portrait: bool = pixels.x > 0 and pixels.y > pixels.x and not (_settings.panel.visible or _pool.panel.visible or _tutorial.visible)
	var canvas: Vector2i = Vector2i(320, roundi(320.0 * pixels.y / pixels.x)) if portrait else _original_canvas
	if _window.content_scale_size != canvas: _window.content_scale_size = canvas
	if portrait == _portrait: return
	_portrait = portrait
	%Panel.custom_minimum_size.x = 300 if portrait else 720
	for side: String in ["margin_left", "margin_right"]:
		%Margin.add_theme_constant_override(side, 8 if portrait else 34)
	for group: BoxContainer in [%Launch, %Tools, %Body]:
		group.vertical = portrait
	%Launch.move_child(%New, 0 if portrait else 1)
	%Title.add_theme_font_size_override("font_size", 23 if portrait else 36)
	%SelectTitle.add_theme_font_size_override("font_size", 21 if portrait else 32)
	%Role.add_theme_font_size_override("font_size", 21 if portrait else 28)
	%Portrait.visible = not portrait
	%Requirement.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if portrait else TextServer.AUTOWRAP_OFF
	%Title.autowrap_mode = %Requirement.autowrap_mode
	%SelectTitle.autowrap_mode = %Requirement.autowrap_mode
	%Continue.autowrap_mode = %Requirement.autowrap_mode
	%Skill.autowrap_mode = %Requirement.autowrap_mode
	for action: Button in [%Back, %Depart, _records.folder, _records.export_button, _records.quit_button]:
		action.autowrap_mode = %Requirement.autowrap_mode
		if action in [_records.folder, _records.export_button, _records.quit_button]:
			action.add_theme_font_size_override("font_size", 13 if portrait else 16)
			action.custom_minimum_size.y = 44.0 if portrait else 0.0
			action.size_flags_horizontal = Control.SIZE_EXPAND_FILL if portrait else Control.SIZE_FILL
	for button: Button in _cards.values():
		button.custom_minimum_size = Vector2(124, 54) if portrait else Vector2(126, 96)
		button.add_theme_constant_override("icon_max_width", 32 if portrait else 42)
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER if portrait else VERTICAL_ALIGNMENT_TOP
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT if portrait else HORIZONTAL_ALIGNMENT_CENTER
		button.autowrap_mode = %Requirement.autowrap_mode
		var lock_icon: TextureRect = button.get_node("LockIcon")
		lock_icon.anchor_left = 0.0 if portrait else 1.0
		lock_icon.anchor_right = lock_icon.anchor_left
		lock_icon.offset_left = 6.0 if portrait else -32.0
		lock_icon.offset_right = 22.0 if portrait else -8.0
		lock_icon.offset_top = 4.0 if portrait else 8.0
		lock_icon.offset_bottom = 20.0 if portrait else 32.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _loaded:
		for index: int in range(GameModes.ALL.size()): _mode.set_item_text(index, tr(GameModes.ALL[index].title))
		_refresh()

func _show_home() -> void:
	_characters.hide()
	_home.show()
	_refresh()
	_restore_focus()

func _show_characters() -> void:
	_home.hide()
	_characters.show()
	_choose(_selected)
	_restore_focus()

func _confirm_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.is_action_pressed("ui_cancel"):
		_confirm.set_input_as_handled()
		_confirm.hide()
		_restore_focus.call_deferred()

func _restore_focus() -> void:
	if _characters.visible:
		_cards[_selected].grab_focus()
	elif _slot.saved_available: %Continue.grab_focus()
	else: %New.grab_focus()

func _new_game() -> void:
	if _departing: return
	if GameModes.ALL[_mode.selected].mode_id == &"stage_challenge": _show_characters()
	else: _ask_to_depart()

func _choose(opening: StringName) -> void:
	_selected = opening if _cards.has(opening) else &"standard"
	for id: StringName in _cards: _cards[id].set_pressed_no_signal(id == _selected)
	_refresh()
	_restore_focus()

func _refresh() -> void:
	%Practice.text = tr("重看操作练习" if _preferences.tutorial_seen else "先试一下 · 操作练习")
	%Continue.visible = _slot.saved_available
	if _slot.saved_available:
		var saved: GameModeDefinition = GameModes.find(_slot.saved_mode)
		var details: PackedStringArray = [tr(saved.title) if saved != null else tr("继续本局")]
		if _saved.get("stage", 0) > 0: details.append(tr("room.stage") % _saved.stage)
		if _saved.has("opening"): details.append(tr("role." + str(_saved.opening)))
		%Continue.text = tr("room.resume") % " · ".join(details)
	for role: ROLE in RunController.ROLES.ALL:
		var button: Button = _cards[role.id]
		button.icon = role.portrait
		button.text = tr("role." + str(role.id))
		var locked: bool = not _slot.opening_progress.available(role.id)
		button.get_node("LockIcon").visible = locked
		if locked: button.text += "\n" + tr("role.lock")
	var selected: ROLE = RunController.ROLES.find(_selected)
	var owned: bool = _slot.opening_progress.available(_selected)
	%Diagram.preview(_selected)
	%Portrait.display(selected)
	%Role.text = tr("role." + str(_selected))
	%Skill.text = selected.starting_skill_text()
	%Description.text = tr("role.demo." + str(_selected))
	%Requirement.text = tr("role.best") % _slot.opening_progress.best if owned else tr("role.target") % [_slot.opening_progress.best, selected.threshold, selected.threshold - _slot.opening_progress.best]
	var next: ROLE = _slot.opening_progress.next_locked()
	if owned and next != null:
		%Requirement.text = tr("role.next") % tr("role." + str(next.id)) + " · " + tr("role.target") % [_slot.opening_progress.best, next.threshold, next.threshold - _slot.opening_progress.best]
	if not owned and _selected == &"row_sweep": %Requirement.text += " · " + tr("role.first_stage")
	%Depart.disabled = _departing or not owned
	%Depart.text = tr("room.depart") % %Role.text if owned else tr("role.lock")

func _ask_to_depart() -> void:
	if _departing: return
	if _saved.is_empty(): _launch(false)
	else:
		var saved: GameModeDefinition = GameModes.find(_slot.saved_mode)
		_confirm.dialog_text = tr("room.replace") % (tr(saved.title) if saved != null else tr("继续本局"))
		_confirm.popup_centered()

func _launch(resume: bool) -> void:
	if _departing or not _loaded: return
	var mode: StringName = GameModes.ALL[_mode.selected].mode_id
	var opening: StringName = _selected if mode == &"stage_challenge" else &"standard"
	if not resume and not _slot.opening_progress.available(opening): return
	_departing = true
	var data: Dictionary = {"action": "continue" if resume else "new", "directory": checkpoint_directory}
	if not resume: data.merge({"mode": mode, "opening": opening, "replace": _saved.get("run_id", "")})
	if not GameFlow.travel(GameFlow.Page.PLAY, data): _failed(SESSION, "busy")

func _failed(path: String, _reason: String) -> void:
	if path != SESSION: return
	_departing = false
	%Status.text = tr("room.scene_failed")
	_refresh()
	_restore_focus()

func _practice() -> void:
	_home.hide()
	_tutorial.start(_preferences.low_effects)

func _practice_finished(completed: bool) -> void:
	if completed: _preference(true, &"tutorial_seen")
	_show_home()

func _open_pool() -> void:
	# The catalogue uses an empty build to show base levels and prerequisites.
	var baseline: BoardRules = BoardRules.new(BoardState.new(9, 9), MatchSystem.MIN_MATCH_COUNT)
	_pool.open(RunController.new(baseline, 0, GameModes.ALL[_mode.selected].stage_config))

func _open_settings() -> void:
	_settings.set_fast(_preferences.fast)
	_settings.set_low_effects(_preferences.low_effects)
	_settings.set_volume(_preferences.volume)
	_settings.set_background_motion(_preferences.background_motion)
	_settings.set_board_signal(_preferences.board_signal)
	_settings.set_theme_id(_preferences.theme_id)
	_settings.open(false, false)

func _preference(value: Variant, key: StringName) -> void:
	_preferences.set(key, value)
	if key == &"low_effects": _settings.set_low_effects(_preferences.low_effects)
	if not _preferences.save_values(): %Status.text = tr("hud.status.settings_failed")

func _language(index: int) -> void:
	if _preferences.set_language_preference(LOCALES[index], true) != OK: %Status.text = tr("语言设置保存失败；当前选择仍可使用。")

func _record_status(message: String) -> void:
	_records.show_status(message, _collection.enabled, true)
