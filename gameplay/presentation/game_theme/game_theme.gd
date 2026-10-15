class_name GameTheme
extends Resource

## Full visual preset. Never passed into rule state, scoring or recording configuration.
@export var theme_id: StringName
@export var title: String
@export var ui_theme: Theme
@export var board: BoardAppearance
@export var feedback: BoardJuiceConfig
@export var score_floats: ScoreFloatConfig
@export var progress: GoalProgressConfig
@export var background_flow: BackgroundFlowConfig
@export var background: Color = Color("0b0f13")

func validation_error() -> String:
	if theme_id.is_empty() or ui_theme == null or board == null or feedback == null or score_floats == null or progress == null or background_flow == null:
		return "visual theme is incomplete"
	if board.piece_colors.size() != 5: return "visual theme requires five piece colors"
	return ""
