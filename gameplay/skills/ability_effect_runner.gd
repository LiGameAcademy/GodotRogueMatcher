class_name AbilityEffectRunner
extends RefCounted

## Applies ChoiceEffect / CompositeEffect roots without skill_id branches.
## CLEAR removals inside a composite hold blast descendants until every leaf finishes.

static func preflight(run: RunController, effect: SkillEffect, frozen: SkillTarget, selected_color: int = -1, root: bool = true) -> String:
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
		if selected_color != -1 and not composite.requires_color_choice(): return "this skill does not need a color choice"
		for index: int in range(composite.children.size()):
			var child: SkillEffect = composite.children[index]
			var target: SkillTarget = composite_target.leaf_targets[index]
			if target == null: return "composite frozen target missing"
			var needs_color: bool = (child as ChoiceEffect).requires_color_choice() if child is ChoiceEffect else (child as CompositeEffect).requires_color_choice()
			error = preflight(run, child, target, selected_color if needs_color else -1, false)
			if not error.is_empty() and composite.fixed_target_policy == CompositeEffect.FixedTargetPolicy.SKIP_INVALID and child is ChoiceEffect and not needs_color and not target.deferred:
				var choice: ChoiceEffect = child as ChoiceEffect
				var context: ChoiceEffectContext = SkillRules.effect_context(run.state)
				if not choice.build(context, target).error.is_empty():
					error = _validate_request(run, choice.build_surviving(context, target))
			if not error.is_empty(): return error
		if root and not composite.allow_empty_acquisition and _entirely_empty(run, composite, composite_target): return "组合没有可生效目标"
		return ""
	return "unsupported skill effect"

## Read-only fixed filtering; deferred selectors are never sampled during preflight.
static func _entirely_empty(run: RunController, effect: CompositeEffect, frozen: CompositeSkillTarget) -> bool:
	var context: ChoiceEffectContext = SkillRules.effect_context(run.state)
	for index: int in range(effect.children.size()):
		var child: SkillEffect = effect.children[index]
		var target: SkillTarget = frozen.leaf_targets[index]
		if child is CompositeEffect:
			if not _entirely_empty(run, child as CompositeEffect, target as CompositeSkillTarget): return false
		else:
			var choice: ChoiceEffect = child as ChoiceEffect
			if target.deferred:
				if not choice.empty_targets_allowed(context): return false
				continue
			var request: ChoiceEffectRequest = choice.build(context, target)
			if not request.error.is_empty() and effect.fixed_target_policy == CompositeEffect.FixedTargetPolicy.SKIP_INVALID:
				request = choice.build_surviving(context, target)
			if not request.error.is_empty() or request.kind not in [ChoiceEffectRequest.Kind.CLEAR, ChoiceEffectRequest.Kind.DYE, ChoiceEffectRequest.Kind.ASSIGN_FUSE] or not request.piece_ids.is_empty(): return false
	return true

static func apply_skill_effect(run: RunController, effect: SkillEffect, frozen: SkillTarget, result: SkillApplyResult, selected_color: int = -1) -> String:
	if effect == null: return "skill effect missing"
	if effect is CompositeEffect:
		return _apply_composite(run, effect as CompositeEffect, frozen, result, selected_color, true)
	if effect is ChoiceEffect:
		var error: String = _apply_choice(run, effect as ChoiceEffect, frozen, result, selected_color, false)
		if error.is_empty(): result.completed_leaves.append("root")
		else: result.failed_leaf = "root"
		return error
	return "unsupported skill effect"

static func apply_choice_request(run: RunController, request: ChoiceEffectRequest, result: SkillApplyResult, hold_blasts: bool = false) -> String:
	if request == null: return "choice effect request missing"
	if not request.error.is_empty(): return request.error
	var state: RunState = run.state
	match request.kind:
		ChoiceEffectRequest.Kind.TRANSFORM:
			var paid: Array[PieceState] = []
			for id: int in request.cost_piece_ids:
				var piece: PieceState = state.rules.state.get_piece(id)
				if piece != null: paid.append(piece.copy())
			var transformed: Array[PieceState] = run.abilities.transform_material(request.piece_ids, request.content_id, request.cost_piece_ids)
			if not run.abilities.last_error.is_empty(): return run.abilities.last_error
			result.transformed.append_array(transformed)
			result.removed.append_array(paid)
		ChoiceEffectRequest.Kind.UNLOCK_CORE:
			state.explosion.core_pool_unlocked = true
			var core: PieceState = run.abilities.add_core(request.coordinate, request.color)
			result.created.append(core)
			result.matches.append_array(run.resolve_matches_at(core.coordinate, hold_blasts))
		ChoiceEffectRequest.Kind.UNLOCK_LINE:
			if request.stat == LineClearState.AXIS_ROW: state.line_clear.row_unlocked = true
			elif request.stat == LineClearState.AXIS_COLUMN: state.line_clear.column_unlocked = true
			else: return "扫线轴向无效"
			var sweeper: PieceState = run.abilities.add_line_piece(request.stat, request.coordinate, request.color)
			if sweeper == null: return "无法放置扫线手"
			result.created.append(sweeper)
			result.matches.append_array(run.resolve_matches_at(sweeper.coordinate, hold_blasts))
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
		ChoiceEffectRequest.Kind.LINE_UPGRADE:
			state.line_clear.upgrades[request.upgrade] = state.line_clear.level(request.upgrade) + 1
		ChoiceEffectRequest.Kind.DYE:
			result.matches.append_array(DyeRules.recolor(run.abilities, request.piece_ids, request.color, hold_blasts))
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
	return state.rule_error

static func _apply_choice(run: RunController, effect: ChoiceEffect, frozen: SkillTarget, result: SkillApplyResult, selected_color: int, hold_blasts: bool) -> String:
	var target: SkillTarget = frozen
	if frozen.deferred:
		if not effect.dynamic_targets() or not frozen.valid_deferred_contract(): return "invalid deferred target"
		var reason: String = effect.rejection(SkillRules.effect_context(run.state))
		if not reason.is_empty() and not (effect is DyeMaterialEffect and (effect as DyeMaterialEffect).allow_empty_targets): return reason
		target = effect.freeze(SkillRules.effect_context(run.state), run.state.rewards.target_random)
	if effect.requires_color_choice():
		target = (effect as ClearMaterialEffect).choose_color(frozen, selected_color)
		if target == null: return "choose a valid color first"
	elif selected_color != -1:
		return "this skill does not need a color choice"
	var context: ChoiceEffectContext = SkillRules.effect_context(run.state)
	var request: ChoiceEffectRequest = effect.build(context, target)
	var error: String = _validate_request(run, request)
	if not error.is_empty(): return error
	return apply_choice_request(run, request, result, hold_blasts)

static func _apply_composite(run: RunController, effect: CompositeEffect, frozen: SkillTarget, result: SkillApplyResult, selected_color: int, flush_blasts: bool, refresh_first: bool = false, parent_path: String = "") -> String:
	var error: String = effect.validation_error()
	if not error.is_empty(): return error
	var composite_target: CompositeSkillTarget = frozen as CompositeSkillTarget
	if composite_target == null or composite_target.leaf_targets.size() != effect.children.size():
		return "composite frozen targets missing"
	var color_consumed: bool = false
	for index: int in range(effect.children.size()):
		var child: SkillEffect = effect.children[index]
		var path: String = str(index) if parent_path.is_empty() else parent_path + "." + str(index)
		var leaf_frozen: SkillTarget = composite_target.leaf_targets[index]
		# 只刷新真正到达的叶；不能提前刷新整棵子树，再由内层重复抽样。
		if (index > 0 or refresh_first) and child is ChoiceEffect and not leaf_frozen.deferred:
			var context: ChoiceEffectContext = SkillRules.effect_context(run.state)
			leaf_frozen = (child as ChoiceEffect).refresh_after_previous(context, leaf_frozen, run.state.rewards.target_random)
		var leaf_color: int = -1
		if (child is ChoiceEffect and (child as ChoiceEffect).requires_color_choice()) or (child is CompositeEffect and (child as CompositeEffect).requires_color_choice()):
			if color_consumed or selected_color == -1: return "choose a valid color first"
			leaf_color = selected_color
			color_consumed = true
		elif selected_color != -1 and not color_consumed and index == effect.children.size() - 1:
			return "this skill does not need a color choice"
		if child is ChoiceEffect:
			error = _apply_choice_with_policy(run, child as ChoiceEffect, leaf_frozen, result, leaf_color, true, effect.fixed_target_policy)
		elif child is CompositeEffect:
			error = _apply_composite(run, child as CompositeEffect, leaf_frozen, result, leaf_color, false, index > 0 or refresh_first, path)
		else:
			error = "unsupported composite child effect"
		if not error.is_empty():
			if result.failed_leaf.is_empty(): result.failed_leaf = path
			return error
		if child is ChoiceEffect: result.completed_leaves.append(path)
	if flush_blasts:
		result.matches.append_array(run.abilities.flush_held_blasts())
		if not run.state.rule_error.is_empty(): result.failed_leaf = "descendants"
	return run.state.rule_error

static func _apply_choice_with_policy(run: RunController, effect: ChoiceEffect, frozen: SkillTarget, result: SkillApplyResult, selected_color: int, hold_blasts: bool, policy: CompositeEffect.FixedTargetPolicy) -> String:
	var target: SkillTarget = frozen
	if frozen.deferred:
		if not effect.dynamic_targets() or not frozen.valid_deferred_contract(): return "invalid deferred target"
		var reason: String = effect.rejection(SkillRules.effect_context(run.state))
		if not reason.is_empty() and not (effect is DyeMaterialEffect and (effect as DyeMaterialEffect).allow_empty_targets): return reason
		target = effect.freeze(SkillRules.effect_context(run.state), run.state.rewards.target_random)
	if effect.requires_color_choice():
		target = (effect as ClearMaterialEffect).choose_color(frozen, selected_color)
		if target == null: return "choose a valid color first"
	elif selected_color != -1:
		return "this skill does not need a color choice"
	var context: ChoiceEffectContext = SkillRules.effect_context(run.state)
	var request: ChoiceEffectRequest = effect.build(context, target)
	var filtered: bool = false
	if not request.error.is_empty() and policy == CompositeEffect.FixedTargetPolicy.SKIP_INVALID:
		request = _skip_invalid_fixed_targets(effect, context, target, request)
		if request.error.is_empty():
			filtered = true
			result.target_changes.append({"kind": request.kind, "outcome": "empty" if request.piece_ids.is_empty() else "partial", "reason": "fixed_targets_invalidated", "original": target.piece_ids.duplicate(), "remaining": request.piece_ids.duplicate()})
	var validation: String = _validate_request(run, request)
	if not validation.is_empty(): return validation
	if request.kind in [ChoiceEffectRequest.Kind.CLEAR, ChoiceEffectRequest.Kind.DYE, ChoiceEffectRequest.Kind.ASSIGN_FUSE] and request.piece_ids.is_empty():
		if not filtered:
			result.target_changes.append({"kind": request.kind, "outcome": "empty", "reason": "declared_empty", "original": [], "remaining": []})
		return ""
	return apply_choice_request(run, request, result, hold_blasts)

static func _skip_invalid_fixed_targets(effect: ChoiceEffect, context: ChoiceEffectContext, target: SkillTarget, _failed: ChoiceEffectRequest) -> ChoiceEffectRequest:
	return effect.build_surviving(context, target)

static func _preflight_choice(run: RunController, effect: ChoiceEffect, frozen: SkillTarget, selected_color: int) -> String:
	if frozen == null: return "missing frozen target"
	if frozen.deferred:
		if not effect.dynamic_targets() or effect.requires_color_choice() or not frozen.valid_deferred_contract(): return "invalid deferred target"
		if selected_color != -1: return "this skill does not need a color choice"
		var reason: String = effect.rejection(SkillRules.effect_context(run.state))
		if not reason.is_empty(): return reason
		if effect is TransformMaterialEffect:
			var transform: TransformMaterialEffect = effect as TransformMaterialEffect
			var count: int = transform.available_target_count(SkillRules.effect_context(run.state))
			return run.abilities.validation_error(1, count if transform.content_id == &"special_demolition" else 0, 0, count if transform.content_id != &"special_demolition" else 0)
		return "" if effect.empty_targets_allowed(SkillRules.effect_context(run.state)) else run.abilities.validation_error(1)
	var target: SkillTarget = frozen
	if effect.requires_color_choice():
		target = (effect as ClearMaterialEffect).choose_color(frozen, selected_color)
		if target == null: return "choose a valid color first"
	elif selected_color != -1:
		return "this skill does not need a color choice"
	var context: ChoiceEffectContext = SkillRules.effect_context(run.state)
	var request: ChoiceEffectRequest = effect.build(context, target)
	return _validate_request(run, request)

static func _validate_request(run: RunController, request: ChoiceEffectRequest) -> String:
	if not request.error.is_empty(): return request.error
	if request.kind in [ChoiceEffectRequest.Kind.CLEAR, ChoiceEffectRequest.Kind.DYE, ChoiceEffectRequest.Kind.ASSIGN_FUSE] and request.piece_ids.is_empty(): return ""
	if request.kind in [ChoiceEffectRequest.Kind.CLEAR, ChoiceEffectRequest.Kind.DYE]: return run.abilities.validation_error(1)
	if request.kind == ChoiceEffectRequest.Kind.UNLOCK_CORE: return _preflight_unlock_core(run, request)
	if request.kind == ChoiceEffectRequest.Kind.UNLOCK_LINE: return _preflight_unlock_line(run, request)
	if request.kind == ChoiceEffectRequest.Kind.TRANSFORM:
		return run.abilities.transformation_error(request.piece_ids, request.content_id, request.cost_piece_ids)
	return ""
static func _preflight_unlock_core(run: RunController, request: ChoiceEffectRequest) -> String:
	var state: RunState = run.state
	var preview: BoardRules = state.rules.placement_preview()
	preview.place_piece(request.coordinate, request.color, &"special_demolition")
	var groups: Array[BoardMatchGroup] = preview.find_matches_at(request.coordinate)
	return run.abilities.validation_error(groups.size(), 1, 1)

static func _preflight_unlock_line(run: RunController, request: ChoiceEffectRequest) -> String:
	var state: RunState = run.state
	var content: StringName = state.line_clear.content_id(request.stat)
	if content.is_empty(): return "扫线轴向无效"
	var preview: BoardRules = state.rules.placement_preview()
	preview.place_piece(request.coordinate, request.color, content)
	var groups: Array[BoardMatchGroup] = preview.find_matches_at(request.coordinate)
	return run.abilities.validation_error(groups.size(), 0, 1, 1)
