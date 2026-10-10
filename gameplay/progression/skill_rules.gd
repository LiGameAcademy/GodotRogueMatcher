class_name SkillRules
extends RefCounted

## 技能合法条件和应用入口；与界面、回合动画无关。
static func level(state: RunState, skill: SkillDefinition) -> int:
	if skill.choice_effect is InstallDyeUpgradeEffect:
		return state.dye.level((skill.choice_effect as InstallDyeUpgradeEffect).upgrade)
	if skill.choice_effect is InstallUpgradeEffect:
		return state.explosion.level((skill.choice_effect as InstallUpgradeEffect).upgrade)
	match skill.action:
		SkillDefinition.Action.BLAST_RADIUS: return state.explosion.radius_level
		SkillDefinition.Action.BLAST_REWARD: return state.explosion.reward_level
		SkillDefinition.Action.SCORE_MULTIPLIER: return state.explosion.multiplier_level
		SkillDefinition.Action.MATCH_EXTRA: return state.explosion.match_extra_level
		SkillDefinition.Action.BLAST_EXTRA: return state.explosion.blast_extra_level
	return state.rewards.acquired.get(skill.skill_id, 0)

static func unmarked_material(state: RunState) -> Array[int]:
	var ids: Array[int] = []
	for piece: PieceState in state.rules.state.get_snapshot():
		if piece.content_id.is_empty() and not state.explosion.instances.has(piece.piece_id):
			ids.append(piece.piece_id)
	return ids

static func effect_context(state: RunState) -> ChoiceEffectContext:
	var context: ChoiceEffectContext = ChoiceEffectContext.new()
	context.spawn_config = RunController.SPAWN_CONFIG
	context.next_refill = state.next_refill_count()
	context.color_weights = state.spawning.color_weights.duplicate()
	context.refill_batches = state.spawning.refill_batches.duplicate()
	context.upgrades = state.explosion.upgrades.duplicate()
	context.dye_upgrades = state.dye.upgrades.duplicate()
	for piece: PieceState in state.rules.state.get_snapshot():
		if piece.content_id.is_empty(): context.material.append(piece.copy())
		if piece.content_id.is_empty() and state.explosion.instances.has(piece.piece_id): context.fuse_ids.append(piece.piece_id)
	return context

static func rejection(state: RunState, skill: SkillDefinition, config: ExplosionConfig, frozen_pressure: float = -1.0) -> String:
	if state.is_game_over or not state.rule_error.is_empty():
		return "本局已经结束或规则异常"
	if not is_finite(skill.base_weight) or skill.base_weight <= 0.0:
		return "技能权重必须为正数"
	if skill.requires_core and not state.explosion.core_pool_unlocked: return "需先获得爆壳手登场"
	if skill.requires_fuse_unlock and not state.explosion.fuse_unlocked: return "需先解锁引信路线"
	if skill.requires_fuse and effect_context(state).fuse_ids.is_empty(): return "棋盘上需要引信"
	if not skill.prerequisite.is_empty() and state.rewards.acquired.get(skill.prerequisite, 0) == 0: return "缺少前置升级"
	if skill.maximum_level > 0 and level(state, skill) >= skill.maximum_level: return "已满级"
	if level(state, skill) >= 1000000: return "等级已达安全上限"
	var early_rescue: bool = RescueOfferRules.early_allowed(state, skill, frozen_pressure)
	if not early_rescue and state.rewards.consumed_count + 1 < skill.minimum_reward: return "尚未进入候选阶段"
	if skill.choice_effect != null:
		if not early_rescue and state.rewards.consumed_count + 1 < skill.minimum_reward: return "尚未进入中期候选池"
		return skill.choice_effect.rejection(effect_context(state))
	match skill.action:
		SkillDefinition.Action.CORE_DROP:
			if state.explosion.core_pool_unlocked: return "已解锁核心供给"
			if state.rules.state.get_empty_coordinates().is_empty(): return "没有空格"
			for piece: PieceState in state.rules.state.get_snapshot():
				if piece.content_id == &"special_demolition": return "爆壳手仍在场"
		SkillDefinition.Action.ASSIGN_FUSE:
			if unmarked_material(state).is_empty(): return "没有可赋引信的普通棋子"
		SkillDefinition.Action.BLAST_RADIUS:
			if not state.explosion.unlocked: return "尚未解锁爆炸"
			if state.explosion.radius_level >= config.maximum_radius_level: return "已满级"
		SkillDefinition.Action.BLAST_REWARD:
			if not state.explosion.unlocked: return "尚未解锁爆炸"
			if state.explosion.reward_level >= config.reward_maximum_level: return "已满级"
		SkillDefinition.Action.BLAST_EXTRA:
			if not state.explosion.unlocked: return "尚未解锁爆炸"
		SkillDefinition.Action.THIN:
			if not early_rescue and state.rewards.consumed_count + 1 < skill.minimum_reward: return "尚未进入中期候选池"
			if unmarked_material(state).is_empty(): return "没有可疏整材料"
	return ""

static func apply(run: RunController, offer_id: int, skill_id: StringName, selected_color: int = -1) -> SkillApplyResult:
	var result: SkillApplyResult = SkillApplyResult.new()
	var state: RunState = run.state
	var rewards: RewardState = state.rewards
	var offer: SkillOffer = rewards.active_offer
	if offer == null or offer.offer_id != offer_id or offer.reward_id != rewards.consumed_count + 1 or state.pending_rewards <= 0 or state.phase != RunState.Phase.REWARDS:
		result.error = "奖励已处理或候选已失效"
		return result
	var skill: SkillDefinition = null
	for choice: SkillDefinition in offer.choices:
		if choice.skill_id == skill_id: skill = choice
	if skill == null:
		result.error = "该技能不在当前候选中"
		return result
	result.error = rejection(state, skill, run.abilities.config)
	if not result.error.is_empty(): return result
	var targets: SkillTarget = offer.targets.get(skill_id)
	if targets == null:
		result.error = "Missing frozen target"
		return result
	if skill.choice_effect != null and skill.choice_effect.requires_color_choice():
		targets = (skill.choice_effect as ClearMaterialEffect).choose_color(targets, selected_color)
		if targets == null:
			result.error = "请先选择有效颜色"
			return result
	elif selected_color != -1:
		result.error = "该技能无需选色"
		return result
	var request: ChoiceEffectRequest = null
	# 冻结目标在提交前再次校验，失败不修改棋盘、不消费奖励。
	if skill.choice_effect != null:
		request = skill.choice_effect.build(effect_context(state), targets)
		result.error = request.error
		if result.error.is_empty() and request.kind in [ChoiceEffectRequest.Kind.CLEAR, ChoiceEffectRequest.Kind.DYE]:
			result.error = run.abilities.validation_error(1)
		if not result.error.is_empty(): return result
	elif skill.action == SkillDefinition.Action.CORE_DROP:
		var coordinate: Vector2i = targets.coordinate
		if not state.rules.state.is_valid_coordinate(coordinate) or state.rules.state.get_piece_id(coordinate) != 0:
			result.error = "原定空格已经被占用"
			return result
		# 先在独立棋盘预检事件预算，避免落子后才发现无法完整结算。
		var preview: BoardRules = BoardRules.new(BoardState.new(state.rules.state.columns, state.rules.state.rows), state.rules.minimum_match_count)
		for piece: PieceState in state.rules.state.get_snapshot():
			preview.place_piece(piece.coordinate, piece.match_color, piece.content_id, piece.is_ghost)
		preview.place_piece(coordinate, run.abilities.config.core_color, &"special_demolition")
		var groups: Array[BoardMatchGroup] = preview.find_matches_at(coordinate)
		result.error = run.abilities.validation_error(groups.size(), 1, 1)
		if not result.error.is_empty():
			return result
	elif skill.action in [SkillDefinition.Action.ASSIGN_FUSE, SkillDefinition.Action.THIN]:
		var legal: Array[int] = unmarked_material(state)
		var maximum: int = 2 + state.explosion.level(&"fuse_capacity") if skill.action == SkillDefinition.Action.ASSIGN_FUSE else skill.target_count
		if targets.piece_ids.is_empty() or targets.piece_ids.size() > maximum:
			result.error = "材料目标配置无效"
			return result
		var unique: Array[int] = []
		for target: int in targets.piece_ids:
			if not legal.has(target) or unique.has(target):
				result.error = "原定材料目标已经失效"
				return result
			unique.append(target)
	state.action_id += 1
	state.rule_action_id = state.action_id
	if request != null:
		match request.kind:
			ChoiceEffectRequest.Kind.REFILL: state.spawning.extend_refill(request.delta, request.batches)
			ChoiceEffectRequest.Kind.COLOR_WEIGHT: state.spawning.color_weights[request.color] += request.delta
			ChoiceEffectRequest.Kind.UPGRADE:
				state.explosion.upgrades[request.upgrade] = state.explosion.level(request.upgrade) + 1
				if request.upgrade in [&"core_fuse_payload", &"fuse_match_plant"]: state.explosion.fuse_unlocked = true
			ChoiceEffectRequest.Kind.DYE_UPGRADE:
				state.dye.upgrades[request.upgrade] = state.dye.level(request.upgrade) + 1
			ChoiceEffectRequest.Kind.DYE:
				result.matches = DyeRules.recolor(run.abilities, request.piece_ids, request.color)
			ChoiceEffectRequest.Kind.CLEAR:
				for id: int in request.piece_ids: result.removed.append(state.rules.state.get_piece(id).copy())
				result.matches = run.abilities.resolve_removal(result.removed, &"skill_clear")
	else:
		_apply_legacy(run, skill, targets, result)
	result.matches.append_array(DemolitionRules.settle(state, state.rule_action_id))
	rewards.acquired[skill_id] = rewards.acquired.get(skill_id, 0) + 1
	rewards.previous_unselected.clear()
	for choice: SkillDefinition in offer.choices:
		if choice.skill_id != skill_id: rewards.previous_unselected.append(choice.skill_id)
	rewards.consumed_count += 1
	state.pending_rewards -= 1
	rewards.active_offer = null
	result.success = true
	result.reward_id = offer.reward_id
	result.offer_id = offer_id
	result.skill_id = skill_id
	rewards.applications.append(result)
	return result

static func _apply_legacy(run: RunController, skill: SkillDefinition, targets: SkillTarget, result: SkillApplyResult) -> void:
	var state: RunState = run.state
	match skill.action:
		SkillDefinition.Action.CORE_DROP:
			state.explosion.core_pool_unlocked = true
			var core: PieceState = run.abilities.add_core(targets.coordinate)
			result.created.append(core)
			result.matches = run.resolve_matches_at(core.coordinate)
		SkillDefinition.Action.ASSIGN_FUSE:
			state.explosion.fuse_unlocked = true
			for target: int in targets.piece_ids:
				run.abilities.assign_fuse(target)
				result.marked_ids.append(target)
		SkillDefinition.Action.BLAST_RADIUS: run.abilities.upgrade_radius()
		SkillDefinition.Action.BLAST_REWARD: run.abilities.upgrade_reward()
		SkillDefinition.Action.SCORE_MULTIPLIER: state.explosion.multiplier_level += 1
		SkillDefinition.Action.MATCH_EXTRA: state.explosion.match_extra_level += 1
		SkillDefinition.Action.BLAST_EXTRA: state.explosion.blast_extra_level += 1
		SkillDefinition.Action.THIN:
			for target: int in targets.piece_ids:
				result.removed.append(state.rules.remove_piece(target))
