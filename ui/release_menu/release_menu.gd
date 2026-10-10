class_name ReleaseMenu
extends Control

signal play_requested(new_run: bool)
signal mode_requested(mode_id: StringName)
signal skill_pool_requested
signal tutorial_completed
signal language_requested(preference: String)

@onready var mode_button: OptionButton = %Mode
@onready var mode_hint: Label = %ModeHint
var _active_mode: StringName = &"stage_challenge"
@onready var home: CenterContainer = %Home
@onready var play_button: Button = %Play
@onready var new_button: Button = %New
@onready var learn_button: Button = %Learn
@onready var version_label: Label = %Version
@onready var tutorial: Tutorial = %Tutorial
@onready var hint: Label = %Hint
@onready var language: OptionButton = %Language
@onready var collection_controls: CollectionControls = %CollectionControls
@onready var notice: Label = %Notice
var _low_effects: bool = false
var _has_game: bool = false
var _tutorial_seen: bool = false
var _game_over: bool = false
var _practice_done: bool = false
const LOCALES: Array[String] = ["auto", "en_US", "zh_CN"]

func _ready() -> void:
	%SkillPoolButton.pressed.connect(skill_pool_requested.emit)
	play_button.pressed.connect(_play.bind(false))
	new_button.pressed.connect(_play.bind(true))
	learn_button.pressed.connect(_learn)
	tutorial.finished.connect(_tutorial_finished)
	language.item_selected.connect(func(index: int) -> void: language_requested.emit(LOCALES[index]))
	mode_button.item_selected.connect(func(_index: int) -> void: _refresh_text())
	_refresh_text()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready(): _refresh_text()

func set_language_preference(preference: String) -> void:
	var index: int = LOCALES.find(preference)
	language.select(maxi(0, index))

func show_language_error() -> void:
	hint.text = tr("语言设置保存失败；当前选择仍可使用。")

func _refresh_text() -> void:
	version_label.text = tr("v%s · Web 预览试玩") % str(ProjectSettings.get_setting("application/config/version", "development"))
	if not OS.has_feature("web"):
		version_label.text = tr("v%s · 桌面试玩") % str(ProjectSettings.get_setting("application/config/version", "development"))
		notice.text = tr("试玩记录保存在本机，不上传。\n从下方打开目录或导出记录；Excel 分析在离线工具中完成。")
	language.set_item_text(0, tr("语言：跟随系统"))
	play_button.text = tr("继续本局") if _has_game else tr("开始试玩")
	learn_button.text = tr("重看操作练习") if _tutorial_seen else tr("先试一下 · 操作练习")
	hint.text = tr("本局已结束 · 可以开始新一局。") if _game_over else (tr("本局已暂停，返回后从原处继续。") if _has_game else tr("第一次来？用四步练习认识五连、补棋、技能和爆破。"))
	for index: int in range(GameModes.ALL.size()): mode_button.set_item_text(index, tr(GameModes.ALL[index].title))
	var selected: GameModeDefinition = GameModes.ALL[mode_button.selected]
	mode_hint.text = tr(selected.description)
	if selected.mode_id != _active_mode:
		play_button.text = tr("开始所选模式 · 新局")
		mode_hint.text += "\n" + tr("切换模式将开始新局，重置本局棋盘与构筑。")
	if _practice_done: hint.text = tr("练习完成！去正式棋盘试试自己的构筑。")

func open(has_game: bool, tutorial_seen: bool, low_effects: bool, game_over: bool = false, mode_id: StringName = &"stage_challenge") -> void:
	_active_mode = mode_id
	for index: int in range(GameModes.ALL.size()):
		if GameModes.ALL[index].mode_id == mode_id: mode_button.select(index)
	_low_effects = low_effects
	_has_game = has_game
	_tutorial_seen = tutorial_seen
	_game_over = game_over
	_practice_done = false
	tutorial.cancel()
	home.show()
	show()
	play_button.visible = not game_over
	new_button.visible = has_game or game_over
	_refresh_text()
	if tutorial_seen and play_button.visible: play_button.grab_focus()
	else: learn_button.grab_focus()

func close() -> void:
	tutorial.cancel()
	hide()

func _play(new_run: bool) -> void:
	close()
	var selected: StringName = GameModes.ALL[mode_button.selected].mode_id
	mode_requested.emit(selected)
	play_requested.emit(new_run or selected != _active_mode)

func _learn() -> void:
	home.hide()
	tutorial.start(_low_effects)

func _tutorial_finished(completed: bool) -> void:
	home.show()
	if completed:
		_tutorial_seen = true
		_practice_done = true
		tutorial_completed.emit()
		learn_button.text = tr("重看操作练习")
		hint.text = tr("练习完成！去正式棋盘试试自己的构筑。")
	if play_button.visible: play_button.grab_focus()
	else: new_button.grab_focus()
