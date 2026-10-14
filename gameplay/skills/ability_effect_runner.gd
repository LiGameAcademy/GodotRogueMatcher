class_name AbilityEffectRunner
extends RefCounted

## Applies ChoiceEffect / CompositeEffect roots without skill_id branches.
## CLEAR removals inside a composite hold blast descendants until every leaf finishes.

static func preflight(run: RunController, effect: SkillEffect, frozen: SkillTarget, selected_color: int = -1) -> String:
	if effect == null: return "skill effect missing"
	if effect is ChoiceEffect:
		return _preflight_choice(run, effect as ChoiceEffect, frozen, selected_color)
	if effect is CompositeEffect:
		var composite: CompositeEffect = effect as CompositeEffect
		var error: String = composite.validation_error()
		if not error.is_empty(): return error
		var composite_target: CompositeSkillTarget = frozen as CompositeSkillTarget
		if composite_target == null or composite_target.leaf_targets.size() != composite.children.size():
			return "composite frozen targets missing"
		var first: SkillEffect = composite.children[0]
		if first is ChoiceEffect:
			return _preflight_choice(run, first as ChoiceEffect, composite_target.leaf_targets[0], selected_color if (first as ChoiceEffect).requires_color_choice() else -1)
		if first is CompositeEffect:
			return preflight(run, first, composite_target.leaf_targets[0], selected_color)
		return "unsupported composite child effect"
	return "unsupported skill effect"

static func apply_skill_effect(run: RunController, effect: SkillEffect, frozen: SkillTarget, result: SkillApplyResult, selected_color: int = -1) -> String:
	if effect == null: return "skill effect missing"
	if effect is CompositeEffect:
		return _apply_composite(run, effect as CompositeEffect, frozen, result, selected_color, true)
	if effect is ChoiceEffect:
		return _apply_choice(run, effect as ChoiceEffect, frozen, result, selected_color, false)
	return "unsupported skill effect"

static func apply_choice_request(run: RunController, request: ChoiceEffectRequest, result: SkillApplyResult, hold_blasts: bool = false) -> String:
	if request == null: return "choice effect request missing"
	if not request.error.is_empty(): return request.error
	var state: RunState = run.state
	match request.kind:
		ChoiceEffectRequest.Kind.UNLOCK_CORE:
			state.explosion.core_pool_unlocked = true
			var core: PieceState = run.abilities.add_core(request.coordinate, request.color)
			result.created.append(core)
			result.matches.append_array(run.resolve_matches_at(core.coordinate))
		ChoiceEffectRequest.Kind.UNLOCK_LINE:
			if request.stat == LineClearState.AXIS_ROW: state.line_clear.row_unlocked = true
			elif request.stat == LineClearState.AXIS_COLUMN: state.line_clear.column_unlocked = true
			else: return "扫线轴向无效"
			var sweeper: PieceState = run.abilities.add_line_piece(request.stat, request.coordinate, request.color)
			if sweeper == null: return "无法放置扫线手"
			result.created.append(sweeper)
			result.matches.append_array(run.resolve_matches_at(sweeper.coordinate))
		ChoiceEffectRequest.Kind.GOAL_BONUS:
			state.goal_bonus_score = request.score_bonus
		ChoiceEffectRequest.Kind.REFILL:
			state.spawning.extend_refill(request.delta, request.batches)
		ChoiceEffectRequest.Kind.COLOR_WEIGHT:
			state.spawning.color_weights[request.color] += request.delta
		ChoiceEffectRequest.Kind.UPGRADE:
			state.explosion.upgrades[request.upgrade] = state.explosion.level(request.upgrade) + 1
			if request.upgrade in [&"core_fuse_payload", &"fuse_match_plant"]: state.explosion.fuse_unlocked = true
		ChoiceEffectRequest.Kind.DYE_UPGRADE:
			state.dye.upgrades[request.upgrade] = state.dye.level(request.upgrade) + 1
		ChoiceEffectRequest.Kind.DYE:
			result.matches.append_array(DyeRules.recolor(run.abilities, request.piece_ids, request.color))
		ChoiceEffectRequest.Kind.CLEAR:
			var batch: Array[PieceState] = []
			for id: int in request.piece_ids:
				var piece: PieceState = state.rules.state.get_piece(id).copy()
				batch.append(piece)
				if not request.score_cleared: result.removed.append(piece)
			result.matches.append_array(run.abilities.resolve_removal(batch, &"skill_clear", hold_blasts, request.score_cleared))
		ChoiceEffectRequest.Kind.THIN:
			for id: int in request.piece_ids:
				result.removed.append(state.rules.remove_piece(id))
		ChoiceEffectRequest.Kind.ASSIGN_FUSE:
			state.explosion.fuse_unlocked = true
			for target: int in request.piece_ids:
				run.abilities.assign_fuse(target)
				result.marked_ids.append(target)
		ChoiceEffectRequest.Kind.DEMOLITION_STAT:
			match request.stat as DemolitionStatEffect.Stat:
				DemolitionStatEffect.Stat.RADIUS:
					if not run.abilities.upgrade_radius(): return "已满级"
				DemolitionStatEffect.Stat.REWARD:
					if not run.abilities.upgrade_reward(): return "已满级"
				DemolitionStatEffect.Stat.MULTIPLIER:
					state.explosion.multiplier_level += 1
				DemolitionStatEffect.Stat.MATCH_EXTRA:
					state.explosion.match_extra_level += 1
				DemolitionStatEffect.Stat.BLAST_EXTRA:
					state.explosion.blast_extra_level += 1
	return ""

static func _apply_choice(run: RunController, effect: ChoiceEffect, frozen: SkillTarget, result: SkillApplyResult, selected_color: int, hold_blasts: bool) -> String:
	var target: SkillTarget = frozen
	if effect.requires_color_choice():
		target = (effect as ClearMaterialEffect).choose_color(frozen, selected_color)
		if target == null: return "choose a valid color first"
	elif selected_color != -1:
		return "this skill does not need a color choice"
	var context: ChoiceEffectContext = SkillRules.effect_context(run.state)
	var request: ChoiceEffectRequest = effect.build(context, target)
	var error: String = request.error
	if error.is_empty() and request.kind in [ChoiceEffectRequest.Kind.CLEAR, ChoiceEffectRequest.Kind.DYE]:
		error = run.abilities.validation_error(1)
	if not error.is_empty(): return error
	if request.kind == ChoiceEffectRequest.Kind.UNLOCK_CORE:
		error = _preflight_unlock_core(run, request)
		if not error.is_empty(): return error
	if request.kind == ChoiceEffectRequest.Kind.UNLOCK_LINE:
		error = _preflight_unlock_line(run, request)
		if not error.is_empty(): return error
	return apply_choice_request(run, request, result, hold_blasts)

static func _apply_composite(run: RunController, effect: CompositeEffect, frozen: SkillTarget, result: SkillApplyResult, selected_color: int, flush_blasts: bool) -> String:
	var error: String = effect.validation_error()
	if not error.is_empty(): return error
	var composite_target: CompositeSkillTarget = frozen as CompositeSkillTarget
	if composite_target == null or composite_target.leaf_targets.size() != effect.children.size():
		return "composite frozen targets missing"
	var color_consumed: bool = false
	for index: int in range(effect.children.size()):
		var child: SkillEffect = effect.children[index]
		var leaf_frozen: SkillTarget = composite_target.leaf_targets[index]
		# After leaf0 commits, later leaves reselect against the updated authoritative state.
		if index > 0:
			var context: ChoiceEffectContext = SkillRules.effect_context(run.state)
			if child is ChoiceEffect:
				leaf_frozen = (child as ChoiceEffect).refresh_after_previous(context, leaf_frozen, run.state.rewards.target_random)
			elif child is CompositeEffect:
				leaf_frozen = (child as CompositeEffect).refresh_after_previous(context, leaf_frozen as CompositeSkillTarget, run.state.rewards.target_random)
		var leaf_color: int = -1
		if child is ChoiceEffect and (child as ChoiceEffect).requires_color_choice():
			if color_consumed or selected_color == -1: return "choose a valid color first"
			leaf_color = selected_color
			color_consumed = true
		elif selected_color != -1 and not color_consumed and index == effect.children.size() - 1:
			return "this skill does not need a color choice"
		if child is ChoiceEffect:
			error = _apply_choice_with_policy(run, child as ChoiceEffect, leaf_frozen, result, leaf_color, true, effect.fixed_target_policy)
		elif child is CompositeEffect:
			error = _apply_composite(run, child as CompositeEffect, leaf_frozen, result, leaf_color, false)
		else:
			error = "unsupported composite child effect"
		if not error.is_empty(): return error
	if flush_blasts:
		result.matches.append_array(run.abilities.flush_held_blasts())
	return ""

static func _apply_choice_with_policy(run: RunController, effect: ChoiceEffect, frozen: SkillTarget, result: SkillApplyResult, selected_color: int, hold_blasts: bool, policy: CompositeEffect.FixedTargetPolicy) -> String:
	var target: SkillTarget = frozen
	if effect.requires_color_choice():
		target = (effect as ClearMaterialEffect).choose_color(frozen, selected_color)
		if target == null: return "choose a valid color first"
	elif selected_color != -1:
		return "this skill does not need a color choice"
	var context: ChoiceEffectContext = SkillRules.effect_context(run.state)
	var request: ChoiceEffectRequest = effect.build(context, target)
	if not request.error.is_empty() and policy == CompositeEffect.FixedTargetPolicy.SKIP_INVALID:
		request = _skip_invalid_fixed_targets(effect, context, target, request)
	if not request.error.is_empty(): return request.error
	if request.kind in [ChoiceEffectRequest.Kind.CLEAR, ChoiceEffectRequest.Kind.DYE] and request.piece_ids.is_empty():
		return ""
	if request.kind in [ChoiceEffectRequest.Kind.CLEAR, ChoiceEffectRequest.Kind.DYE]:
		var budget: String = run.abilities.validation_error(1)
		if not budget.is_empty(): return budget
	if request.kind == ChoiceEffectRequest.Kind.UNLOCK_CORE:
		var unlock_error: String = _preflight_unlock_core(run, request)
		if not unlock_error.is_empty(): return unlock_error
	if request.kind == ChoiceEffectRequest.Kind.UNLOCK_LINE:
		var line_error: String = _preflight_unlock_line(run, request)
		if not line_error.is_empty(): return line_error
	return apply_choice_request(run, request, result, hold_blasts)

static func _skip_invalid_fixed_targets(effect: ChoiceEffect, context: ChoiceEffectContext, target: SkillTarget, failed: ChoiceEffectRequest) -> ChoiceEffectRequest:
	if failed.kind not in [ChoiceEffectRequest.Kind.CLEAR, ChoiceEffectRequest.Kind.DYE]:
		return failed
	var alive: Array[int] = []
	for piece: PieceState in context.material:
		alive.append(piece.piece_id)
	var kept: Array[int] = []
	for id: int in target.piece_ids:
		if alive.has(id) and not kept.has(id): kept.append(id)
	var request: ChoiceEffectRequest = ChoiceEffectRequest.new()
	request.kind = failed.kind
	request.score_cleared = failed.score_cleared
	request.color = target.color
	request.piece_ids = kept
	request.error = ""
	if effect is ClearMaterialEffect and kept.is_empty():
		return request
	if effect is DyeMaterialEffect and kept.is_empty():
		return request
	return request

static func _preflight_choice(run: RunController, effect: ChoiceEffect, frozen: SkillTarget, selected_color: int) -> String:
	var target: SkillTarget = frozen
	if effect.requires_color_choice():
		target = (effect as ClearMaterialEffect).choose_color(frozen, selected_color)
		if target == null: return "choose a valid color first"
	elif selected_color != -1:
		return "this skill does not need a color choice"
	var context: ChoiceEffectContext = SkillRules.effect_context(run.state)
	var request: ChoiceEffectRequest = effect.build(context, target)
	if not request.error.is_empty(): return request.error
	if request.kind in [ChoiceEffectRequest.Kind.CLEAR, ChoiceEffectRequest.Kind.DYE]:
		return run.abilities.validation_error(1)
	if request.kind == ChoiceEffectRequest.Kind.UNLOCK_CORE:
		return _preflight_unlock_core(run, request)
	if request.kind == ChoiceEffectRequest.Kind.UNLOCK_LINE:
		return _preflight_unlock_line(run, request)
	return ""

static func _preflight_unlock_core(run: RunController, request: ChoiceEffectRequest) -> String:
	var state: RunState = run.state
	var preview: BoardRules = BoardRules.new(BoardState.new(state.rules.state.columns, state.rules.state.rows), state.rules.minimum_match_count)
	for piece: PieceState in state.rules.state.get_snapshot():
		preview.place_piece(piece.coordinate, piece.match_color, piece.content_id, piece.is_ghost)
	preview.place_piece(request.coordinate, request.color, &"special_demolition")
	var groups: Array[BoardMatchGroup] = preview.find_matches_at(request.coordinate)
	return run.abilities.validation_error(groups.size(), 1, 1)

static func _preflight_unlock_line(run: RunController, request: ChoiceEffectRequest) -> String:
	var state: RunState = run.state
	var content: StringName = state.line_clear.content_id(request.stat)
	if content.is_empty(): return "扫线轴向无效"
	var preview: BoardRules = BoardRules.new(BoardState.new(state.rules.state.columns, state.rules.state.rows), state.rules.minimum_match_count)
	for piece: PieceState in state.rules.state.get_snapshot():
		preview.place_piece(piece.coordinate, piece.match_color, piece.content_id, piece.is_ghost)
	preview.place_piece(request.coordinate, request.color, content)
	var groups: Array[BoardMatchGroup] = preview.find_matches_at(request.coordinate)
	return run.abilities.validation_error(groups.size(), 0, 1, 1)
