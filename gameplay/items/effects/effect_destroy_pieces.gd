extends GameplayEffect
class_name EffectDestroyPieces

## 旧配置局部验证入口；不驱动表现、匹配或奖励续行。
@export var destroy_range: String = "3x3"
@export var destroy_items: bool = false

func _init(range_type: String = "3x3", items: bool = false) -> void:
	effect_id = "destroy_pieces"
	destroy_range = range_type
	destroy_items = items

func apply(context: Dictionary = {}) -> bool:
	var run_value: Variant = context.get("run")
	var coordinate_value: Variant = context.get("coordinate")
	if not run_value is RunController or not coordinate_value is Vector2i: return false
	if destroy_range not in ["adjacent", "neighbor", "3x3"]: return false
	var run: RunController = run_value as RunController
	var coordinate: Vector2i = coordinate_value
	var changed: int = 0
	for piece: PieceState in run.state.rules.state.get_snapshot():
		var offset: Vector2i = (piece.coordinate - coordinate).abs()
		var in_range: bool = offset.x + offset.y == 1 if destroy_range == "adjacent" else offset.x <= 1 and offset.y <= 1 and (destroy_range == "3x3" or offset != Vector2i.ZERO)
		if not in_range or (not destroy_items and not piece.content_id.is_empty()): continue
		run.state.rules.remove_piece(piece.piece_id)
		run.state.explosion.instances.erase(piece.piece_id)
		run.state.line_clear.instances.erase(piece.piece_id)
		changed += 1
	return changed > 0

func get_description() -> String:
	return "摧毁 " + destroy_range + " 区域的棋子"
