class_name ReleaseMenu
extends Control

signal play_requested(new_run: bool)
signal tutorial_completed

@onready var home: CenterContainer = %Home
@onready var play_button: Button = %Play
@onready var new_button: Button = %New
@onready var learn_button: Button = %Learn
@onready var version_label: Label = %Version
@onready var tutorial: Tutorial = %Tutorial
@onready var hint: Label = %Hint
var _low_effects: bool = false

func _ready() -> void:
	play_button.pressed.connect(_play.bind(false))
	new_button.pressed.connect(_play.bind(true))
	learn_button.pressed.connect(_learn)
	tutorial.finished.connect(_tutorial_finished)
	version_label.text = "v%s · Web 预览试玩" % str(ProjectSettings.get_setting("application/config/version", "development"))

func open(has_game: bool, tutorial_seen: bool, low_effects: bool, game_over: bool = false) -> void:
	_low_effects = low_effects
	tutorial.cancel()
	home.show()
	show()
	play_button.visible = not game_over
	play_button.text = "继续本局" if has_game else "开始试玩"
	new_button.visible = has_game or game_over
	learn_button.text = "重看操作练习" if tutorial_seen else "先试一下 · 操作练习"
	hint.text = "棋盘已满 · 可以开始新一局。" if game_over else ("本局已暂停，返回后从原处继续。" if has_game else "第一次来？用四步练习认识五连、补棋、技能和爆破。")
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
		tutorial_completed.emit()
		learn_button.text = "重看操作练习"
		hint.text = "练习完成！去正式棋盘试试自己的构筑。"
	if play_button.visible: play_button.grab_focus()
	else: new_button.grab_focus()
