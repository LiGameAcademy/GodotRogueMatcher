class_name SkillPool
extends CanvasLayer

signal view_changed(open: bool)
@onready var panel: Control = $Panel
@onready var entries: GridContainer = %Entries
@onready var close_button: Button = %Close
const CARD: PackedScene = preload("res://ui/skill_card.tscn")
@onready var tag_filter: OptionButton = %TagFilter
@onready var rarity_filter: OptionButton = %RarityFilter
@onready var level_filter: OptionButton = %LevelFilter
@onready var order_select: OptionButton = %Order
@onready var count_label: Label = %Count
@onready var empty_label: Label = %Empty
@onready var scroll: ScrollContainer = %Scroll
var _tags: Array[StringName] = [&""]
var _run: RunController
var _previous_pause: bool = false
var _previous_focus: Control
var _open: bool = false

func _ready() -> void:
	close_button.pressed.connect(close)
	for control: OptionButton in [tag_filter, rarity_filter, level_filter, order_select]:
		control.item_selected.connect(func(_index: int) -> void: _refresh())
	%Reset.pressed.connect(_reset_filters)
	scroll.resized.connect(_resize_grid)

func _exit_tree() -> void:
	if _open: get_tree().paused = _previous_pause

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _open and is_node_ready():
		_fill_filters()
		_refresh()

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
	_fill_filters()
	_reset_filters()
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

func _fill_filters() -> void:
	var selected_tag: StringName = _tags[tag_filter.selected] if tag_filter.selected >= 0 else &""
	var selected_rarity: int = rarity_filter.get_selected_id()
	var selected_level: int = level_filter.get_selected_id()
	var selected_order: int = maxi(0, order_select.selected)
	_tags = [&""]
	for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
		for tag: StringName in skill.tags:
			if not _tags.has(tag): _tags.append(tag)
	tag_filter.clear()
	tag_filter.add_item(tr("全部 Tag"))
	for index: int in range(1, _tags.size()):
		tag_filter.add_item(tr(SkillChoiceText.TAG_LABELS.get(_tags[index], String(_tags[index]))))
	tag_filter.select(maxi(0, _tags.find(selected_tag)))
	rarity_filter.clear()
	rarity_filter.add_item(tr("全部稀有度"))
	rarity_filter.set_item_id(0, -1)
	for index: int in range(SkillRarity.NAMES.size()): rarity_filter.add_item(tr(SkillRarity.NAMES[index]), index)
	rarity_filter.select(maxi(0, rarity_filter.get_item_index(selected_rarity)))
	var levels: Array[int] = [0]
	for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
		var value: int = SkillPoolQuery.level(_run, skill)
		if not levels.has(value): levels.append(value)
	levels.sort()
	level_filter.clear()
	level_filter.add_item(tr("全部等级"))
	level_filter.set_item_id(0, -1)
	for value: int in levels: level_filter.add_item(tr("当前等级 %d") % value, value)
	level_filter.select(maxi(0, level_filter.get_item_index(selected_level)))
	order_select.clear()
	for label: String in ["默认：稀有度 → 等级 → 名称", "稀有度降序", "当前等级降序", "名称升序"]: order_select.add_item(tr(label))
	order_select.select(selected_order)

func _reset_filters() -> void:
	for control: OptionButton in [tag_filter, rarity_filter, level_filter, order_select]: control.select(0)
	_refresh()

func _resize_grid() -> void:
	entries.columns = maxi(1, int((scroll.size.x - 16.0) / 308.0))

func _refresh() -> void:
	for child: Node in entries.get_children():
		entries.remove_child(child)
		child.queue_free()
	var skills: Array[SkillDefinition] = SkillPoolQuery.select(_run, _tags[tag_filter.selected], rarity_filter.get_selected_id(), level_filter.get_selected_id(), order_select.selected as SkillPoolQuery.Order)
	for skill: SkillDefinition in skills:
		var card: SkillCard = CARD.instantiate() as SkillCard
		entries.add_child(card)
		card.configure_catalog(skill, _run)
	count_label.text = tr("显示 %d / %d 项技能") % [skills.size(), SkillOfferGenerator.CATALOG.size()]
	empty_label.visible = skills.is_empty()
	scroll.scroll_vertical = 0
	_resize_grid()
