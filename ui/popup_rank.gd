extends UIPopup

@onready var btn_confirm: TextureButton = %btn_confirm
@onready var rank_container: VBoxContainer = %RankContainer

#signal btn_confirm_pressed

func _ready() -> void:
	btn_confirm.pressed.connect(_on_btn_confirm_pressed)

func update_rank_board() -> void:
	for i in range(0, RankBoard.rank_board.size()):
		var rank = RankBoard.rank_board[i]
		var w_rank = rank_container.get_child(i)
		w_rank.update_rank(rank.name, rank.score)

func _on_btn_confirm_pressed() -> void:
	ui_manager.close_current_interface()
