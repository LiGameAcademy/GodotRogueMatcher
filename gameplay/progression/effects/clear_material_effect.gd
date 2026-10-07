class_name ClearMaterialEffect
extends ChoiceEffect

enum Selector { COLOR, LINE }
@export var selector: Selector = Selector.COLOR

func requires_color_choice() -> bool:
	return selector == Selector.COLOR

func rejection(context: ChoiceEffectContext) -> String:
	return "没有可清理的普通棋子" if context.material.is_empty() else ""

func freeze(context: ChoiceEffectContext, random: RandomNumberGenerator) -> SkillTarget:
	var target: SkillTarget = SkillTarget.new()
	if requires_color_choice():
		for color: int in range(context.color_weights.size()):
			var ids: PackedInt64Array = PackedInt64Array()
			var fuses: int = 0
			for piece: PieceState in context.material:
				if piece.match_color != color: continue
				ids.append(piece.piece_id)
				if context.fuse_ids.has(piece.piece_id): fuses += 1
			target.color_groups.append(ids)
			target.fuse_counts.append(fuses)
		return target
	# 在非空颜色/行列中抽选，避免选择到空目标；同一组不因棋子数量重复加权。
	var groups: Array[int] = []
	if selector == Selector.LINE: target.line_axis = random.randi_range(0, 1)
	for piece: PieceState in context.material:
		var group: int = _group(piece, target.line_axis)
		if not groups.has(group): groups.append(group)
	groups.sort()
	var chosen: int = groups[random.randi_range(0, groups.size() - 1)]
	if selector == Selector.COLOR: target.color = chosen
	else: target.line_index = chosen
	for piece: PieceState in context.material:
		if _group(piece, target.line_axis) == chosen: target.piece_ids.append(piece.piece_id)
	return target

## 取玩家明确选定颜色的冻结实体；不修改候选或抽取随机数。
func choose_color(frozen: SkillTarget, color: int) -> SkillTarget:
	if color < 0 or color >= frozen.color_groups.size() or frozen.color_groups[color].is_empty(): return null
	var target: SkillTarget = SkillTarget.new()
	target.color = color
	for id: int in frozen.color_groups[color]: target.piece_ids.append(id)
	return target

func build(context: ChoiceEffectContext, target: SkillTarget) -> ChoiceEffectRequest:
	var request: ChoiceEffectRequest = ChoiceEffectRequest.new()
	request.kind = ChoiceEffectRequest.Kind.CLEAR
	if (selector == Selector.COLOR and (target.color < 0 or target.color >= context.color_weights.size())) or (selector == Selector.LINE and target.line_axis not in [0, 1]):
		request.error = "清理目标配置无效"
		return request
	var expected: Array[int] = []
	var chosen: int = target.color if selector == Selector.COLOR else target.line_index
	for piece: PieceState in context.material:
		if _group(piece, target.line_axis) == chosen: expected.append(piece.piece_id)
	if expected.is_empty() or expected != target.piece_ids:
		request.error = "原定清理目标已经失效"
	request.piece_ids = expected
	return request

func _group(piece: PieceState, axis: int) -> int:
	if selector == Selector.COLOR: return piece.match_color
	return piece.coordinate.y if axis == 0 else piece.coordinate.x
