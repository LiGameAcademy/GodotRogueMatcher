class_name SkillPool
extends CanvasLayer

signal view_changed(open: bool)
@onready var panel: Control = $Panel
@onready var entries: VBoxContainer = %Entries
@onready var close_button: Button = %Close
var _run: RunController
var _previous_pause: bool = false
var _previous_focus: Control
var _open: bool = false

func _ready() -> void:
	close_button.pressed.connect(close)

func _exit_tree() -> void:
	if _open: get_tree().paused = _previous_pause

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _open and is_node_ready(): _refresh()

func _input(event: InputEvent) -> void:
	if not _open: return
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE: close()
		# 保留Tab和方向键的界面导航，只拦截局内快捷键。
		if key.physical_keycode in [KEY_ESCAPE, KEY_F1, KEY_F6, KEY_F7, KEY_F8, KEY_F9, KEY_F10]:
			get_viewport().set_input_as_handled()

func open(run: RunController) -> void:
	if _open or run == null: return
	_run = run
	_previous_pause = get_tree().paused
	_previous_focus = get_viewport().gui_get_focus_owner()
	_open = true
	get_tree().paused = true
	_refresh()
	panel.show()
	close_button.grab_focus()
	view_changed.emit(true)

func close() -> void:
	if not _open: return
	_open = false
	panel.hide()
	get_tree().paused = _previous_pause
	if is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree(): _previous_focus.grab_focus()
	_run = null
	view_changed.emit(false)

func _refresh() -> void:
	for child: Node in entries.get_children():
		entries.remove_child(child)
		child.queue_free()
	for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
		var row: VBoxContainer = VBoxContainer.new()
		var heading: Label = Label.new()
		heading.text = "%s · %s" % [tr(skill.title), tr(SkillRarity.NAMES[skill.rarity])]
		heading.add_theme_color_override("font_color", SkillRarity.COLORS[skill.rarity])
		heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(heading)
		var body: Label = Label.new()
		body.text = SkillPoolText.details(_run, skill)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_theme_font_size_override("font_size", 17)
		row.add_child(body)
		row.add_child(HSeparator.new())
		entries.add_child(row)
