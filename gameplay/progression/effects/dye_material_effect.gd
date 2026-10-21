class_name DyeMaterialEffect
extends ChoiceEffect

func _init() -> void:
	target_policy = TargetPolicy.DYNAMIC

## Only configured ordered composites may finish when earlier leaves leave no dye pair.
@export var allow_empty_targets: bool = false

func rejection(context: ChoiceEffectContext) -> String:
	return "" if allow_empty_targets or _has_pair(context) else "需要至少两种普通棋子颜色"

func empty_targets_allowed(context: ChoiceEffectContext) -> bool:
	return allow_empty_targets and not _has_pair(context)

func _has_pair(context: ChoiceEffectContext) -> bool:
	var colors: Array[int] = []
	for piece: PieceState in context.material:
		if not colors.has(piece.match_color): colors.append(piece.match_color)
	return colors.size() >= 2

func freeze(context: ChoiceEffectContext, random: RandomNumberGenerator) -> SkillTarget:
	var target: SkillTarget = SkillTarget.new()
	var colors: Array[int] = []
	for piece: PieceState in context.material:
		if not colors.has(piece.match_color): colors.append(piece.match_color)
	colors.sort()
	if colors.size() < 2: return target
	target.color = colors[random.randi_range(0, colors.size() - 1)]
	var ids: Array[int] = []
	for piece: PieceState in context.material:
		if piece.match_color != target.color: ids.append(piece.piece_id)
	ids.sort()
	for index: int in range(mini(ids.size(), DyeRules.CONFIG.instant_targets)):
		var position: int = random.randi_range(0, ids.size() - 1)
		target.piece_ids.append(ids[position])
		ids.remove_at(position)
	return target

func build(context: ChoiceEffectContext, target: SkillTarget) -> ChoiceEffectRequest:
	var request: ChoiceEffectRequest = ChoiceEffectRequest.new()
	request.kind = ChoiceEffectRequest.Kind.DYE
	request.color = target.color
	request.piece_ids = target.piece_ids.duplicate()
	if target.piece_ids.is_empty() and empty_targets_allowed(context):
		return request
	if target.color < 0 or target.color >= context.color_weights.size() or target.piece_ids.is_empty() or target.piece_ids.size() > DyeRules.CONFIG.instant_targets:
		request.error = "染色目标配置无效"
		return request
	var legal: Array[int] = []
	for piece: PieceState in context.material:
		if piece.match_color != target.color: legal.append(piece.piece_id)
	var used: Array[int] = []
	for id: int in target.piece_ids:
		if not legal.has(id) or used.has(id): request.error = "原定染色目标已经失效"
		used.append(id)
	return request

func build_surviving(context: ChoiceEffectContext, target: SkillTarget) -> ChoiceEffectRequest:
	if target.color < 0 or target.color >= context.color_weights.size() or target.piece_ids.size() > DyeRules.CONFIG.instant_targets:
		return build(context, target)
	var kept: SkillTarget = target.copy()
	kept.piece_ids.clear()
	var seen: Array[int] = []
	for id: int in target.piece_ids:
		if seen.has(id): return build(context, target)
		seen.append(id)
		for piece: PieceState in context.material:
			if piece.piece_id == id and piece.match_color != target.color: kept.piece_ids.append(id)
	if not kept.piece_ids.is_empty(): return build(context, kept)
	var request: ChoiceEffectRequest = ChoiceEffectRequest.new()
	request.kind = ChoiceEffectRequest.Kind.DYE
	request.color = target.color
	return request
