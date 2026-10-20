extends GameplayEffect
class_name EffectDyePiece

## 仅供旧配置局部验证；显式传入本局与中心，不访问场景或当前全局局。
@export var target_color: int = -1
@export var dye_range: String = "adjacent"
@export var dye_count: int = 1

func _init(color: int = -1, range_type: String = "adjacent", count: int = 1) -> void:
	effect_id = "dye_piece"
	target_color = color
	dye_range = range_type
	dye_count = count

func apply(context: Dictionary = {}) -> bool:
	var run_value: Variant = context.get("run")
	var coordinate_value: Variant = context.get("coordinate")
	if not run_value is RunController or not coordinate_value is Vector2i: return false
	if dye_range not in ["adjacent", "neighbor"]: return false
	var run: RunController = run_value as RunController
	var coordinate: Vector2i = coordinate_value
	var targets: Array[PieceState] = []
	for piece: PieceState in run.state.rules.state.get_snapshot():
		var offset: Vector2i = (piece.coordinate - coordinate).abs()
		var in_range: bool = offset.x + offset.y == 1 if dye_range == "adjacent" else offset.x <= 1 and offset.y <= 1 and offset != Vector2i.ZERO
		if in_range and piece.content_id.is_empty(): targets.append(piece)
	var changed: int = 0
	for index: int in range(mini(dye_count, targets.size())):
		var selected: int = run.state.random.randi_range(0, targets.size() - 1)
		var piece: PieceState = targets[selected]
		targets.remove_at(selected)
		var color: int = target_color if target_color >= 0 else run.state.random.randi_range(0, 4)
		if run.state.rules.set_piece_color(piece.piece_id, color): changed += 1
	return changed > 0

func get_description() -> String:
	return "染色 %d 个棋子%s" % [dye_count, "为颜色 %d" % target_color if target_color >= 0 else "为随机颜色"]
