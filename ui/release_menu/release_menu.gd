class_name ReleaseMenu
extends Control

signal play_requested(new_run: bool)
signal tutorial_completed
signal language_requested(preference: String)

@onready var home: CenterContainer = %Home
@onready var play_button: Button = %Play
@onready var new_button: Button = %New
@onready var learn_button: Button = %Learn
@onready var version_label: Label = %Version
@onready var tutorial: Tutorial = %Tutorial
@onready var hint: Label = %Hint
@onready var language: OptionButton = %Language
var _low_effects: bool = false
var _has_game: bool = false
var _tutorial_seen: bool = false
var _game_over: bool = false
var _practice_done: bool = false
const LOCALES: Array[String] = ["auto", "en_US", "zh_CN"]

func _ready() -> void:
	play_button.pressed.connect(_play.bind(false))
	new_button.pressed.connect(_play.bind(true))
	learn_button.pressed.connect(_learn)
	tutorial.finished.connect(_tutorial_finished)
	language.item_selected.connect(func(index: int) -> void: language_requested.emit(LOCALES[index]))
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
	language.set_item_text(0, tr("语言：跟随系统"))
	play_button.text = tr("继续本局") if _has_game else tr("开始试玩")
	learn_button.text = tr("重看操作练习") if _tutorial_seen else tr("先试一下 · 操作练习")
	hint.text = tr("棋盘已满 · 可以开始新一局。") if _game_over else (tr("本局已暂停，返回后从原处继续。") if _has_game else tr("第一次来？用四步练习认识五连、补棋、技能和爆破。"))
	if _practice_done: hint.text = tr("练习完成！去正式棋盘试试自己的构筑。")

func open(has_game: bool, tutorial_seen: bool, low_effects: bool, game_over: bool = false) -> void:
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
	play_requested.emit(new_run)

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
