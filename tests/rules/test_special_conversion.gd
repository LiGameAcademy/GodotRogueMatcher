extends GutTest

const CARDS: Array[SkillDefinition] = [preload("res://gameplay/progression/content/instant_core_transform.tres"), preload("res://gameplay/progression/content/instant_row_transform.tres"), preload("res://gameplay/progression/content/instant_column_transform.tres")]

class MemorySink extends TelemetrySink:
	func append_event(_event: Dictionary) -> TelemetryWriteResult:
		return TelemetryWriteResult.new()
	func flush() -> TelemetryWriteResult:
		return TelemetryWriteResult.new(TelemetryWriteResult.Status.PERSISTED)
	func close() -> TelemetryWriteResult:
		return flush()

func _run(count: int) -> RunController:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 101)
	run.state.rewards.consumed_count = 2
	for index: int in range(count): run.state.rules.place_piece(Vector2i(index, 2), index % 5)
	return run

func _offer(run: RunController, card: SkillDefinition) -> SkillOffer:
	run.state.pending_rewards = 1
	run.enter_rewards()
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = run.state.rewards.next_offer_id
	run.state.rewards.next_offer_id += 1
	offer.reward_id = run.state.rewards.consumed_count + 1
	offer.choices = [card]
	offer.targets[card.skill_id] = SkillRules.freeze_target(run.state, card)
	run.state.rewards.active_offer = offer
	return offer

func _command(run: RunController, card: SkillDefinition) -> ChooseSkillCommand:
	var offer: SkillOffer = run.state.rewards.active_offer
	var command: ChooseSkillCommand = ChooseSkillCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
	command.offer_id = offer.offer_id
	command.reward_id = offer.reward_id
	command.skill_id = card.skill_id
	return command

func test_all_types_freeze_zero_one_two_three_and_more_without_replacement() -> void:
	for card: SkillDefinition in CARDS:
		for count: int in [0, 1, 2, 3, 7]:
			var run: RunController = _run(count)
			var offer: SkillOffer = _offer(run, card)
			var target: SkillTarget = offer.targets[card.skill_id]
			assert_eq(target.piece_ids.size(), mini(count, 3))
			var before: Array[PieceState] = run.state.rules.state.get_snapshot()
			var next_id: int = run.state.rules.state.next_piece_id()
			var rng_before: int = run.state.rewards.target_random.state
			var result: CommandResult = run.execute_command(_command(run, card))
			assert_eq(result.accepted, count > 0, result.reason)
			if count == 0:
				assert_eq(result.reason, "offer_replaced", "空冻结组已全失效，由本局重建")
				assert_not_null(result.offer)
				assert_eq(result.offer.reward_id, offer.reward_id)
				assert_eq(result.offer.replaces_offer_id, offer.offer_id)
				assert_eq(run.state.pending_rewards, 1)
				assert_eq(run.state.rewards.consumed_count, 2)
				continue
			assert_eq(run.state.rewards.target_random.state, rng_before)
			assert_eq(result.skill.transformed.size(), mini(count, 3))
			assert_true(result.skill.created.is_empty())
			assert_true(result.skill.removed.is_empty())
			assert_true(result.skill.matches.is_empty())
			assert_eq(run.state.ledger.total, 0)
			assert_eq(run.state.rules.state.next_piece_id(), next_id)
			assert_eq(run.state.rules.state.get_piece_count(), count)
			assert_false(run.state.explosion.core_pool_unlocked)
			assert_false(run.state.line_clear.row_unlocked)
			assert_false(run.state.line_clear.column_unlocked)
			var ids: Array[int] = []
			for piece: PieceState in result.skill.transformed:
				assert_false(ids.has(piece.piece_id))
				ids.append(piece.piece_id)
				var original: PieceState = before[piece.piece_id - 1]
				assert_eq(piece.match_color, original.match_color)
				assert_eq(piece.coordinate, original.coordinate)
				assert_eq(piece.content_id, (card.choice_effect as TransformMaterialEffect).content_id)
			assert_eq(ids, target.piece_ids)

func test_capabilities_specials_and_ghosts_are_never_overwritten() -> void:
	for card: SkillDefinition in CARDS:
		var run: RunController = _run(3)
		run.abilities.assign_fuse(1)
		var ghost: PieceState = run.state.rules.place_piece(Vector2i(7, 2), 3, &"", true)
		var core: PieceState = run.abilities.add_core(Vector2i(7, 7), 4)
		var line: PieceState = run.abilities.add_line_piece(0, Vector2i(6, 7), 2)
		var offer: SkillOffer = _offer(run, card)
		assert_eq((offer.targets[card.skill_id] as SkillTarget).piece_ids.size(), 2)
		assert_true(run.execute_command(_command(run, card)).accepted)
		assert_eq(run.state.rules.state.get_piece(1).content_id, &"")
		assert_true(run.state.rules.state.get_piece(ghost.piece_id).is_ghost)
		assert_eq(run.state.rules.state.get_piece(core.piece_id).content_id, core.content_id)
		assert_eq(run.state.rules.state.get_piece(line.piece_id).content_id, line.content_id)

func test_duplicate_stale_and_newly_marked_targets_reject_atomically() -> void:
	for card: SkillDefinition in CARDS:
		for invalid: String in ["duplicate", "stale", "marked", "budget"]:
			var run: RunController = _run(4)
			var target: SkillTarget = _offer(run, card).targets[card.skill_id]
			match invalid:
				"duplicate": target.piece_ids[2] = target.piece_ids[0]
				"stale": run.state.rules.remove_piece(target.piece_ids.back())
				"marked": run.abilities.assign_fuse(target.piece_ids.back())
				"budget":
					run.abilities.config = run.abilities.config.duplicate(true) as ExplosionConfig
					run.abilities.config.event_budget = 1
			var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
			var result: SkillApplyResult = SkillRules.apply(run, run.state.rewards.active_offer.offer_id, card.skill_id)
			assert_false(result.success, invalid)
			assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before, invalid)
			assert_true(result.transformed.is_empty())

func test_conversion_instances_are_independent_and_manual_quota_is_not_refilled() -> void:
	for card: SkillDefinition in CARDS:
		var a: RunController = _run(3)
		var b: RunController = _run(3)
		var line: bool = card != CARDS[0]
		var manual: SkillDefinition = ManualActivationRules.skill(line)
		a.state.manual_uses_used[manual.skill_id] = 2
		_offer(a, card)
		var result: CommandResult = a.execute_command(_command(a, card))
		assert_true(result.accepted, result.reason)
		assert_eq(a.state.manual_uses_used[manual.skill_id], 2)
		var instances: Dictionary[int, AbilityInstance] = a.state.line_clear.instances if line else a.state.explosion.instances
		assert_ne(instances[1], instances[2])
		instances[1].trigger_count += 1
		assert_eq(instances[2].trigger_count, 0)
		assert_eq(b.state.rules.state.get_piece(1).content_id, &"")
		assert_true(b.state.explosion.instances.is_empty())
		assert_true(b.state.line_clear.instances.is_empty())
		assert_eq((card.choice_effect as TransformMaterialEffect).count, 3)
		if not line: assert_null(a.abilities.add_core(Vector2i(8, 8), 0))

func test_converted_row_column_core_chain_uses_type_upgrades_and_single_use_instances() -> void:
	var run: RunController = _run(0)
	var row: PieceState = run.state.rules.place_piece(Vector2i(0, 2), 0)
	var column: PieceState = run.state.rules.place_piece(Vector2i(4, 2), 1)
	var core: PieceState = run.state.rules.place_piece(Vector2i(4, 5), 2)
	var extra_core: PieceState = run.state.rules.place_piece(Vector2i(5, 5), 3)
	run.state.rules.place_piece(Vector2i(5, 6), 4)
	assert_eq(run.abilities.transform_material([row.piece_id], LineClearState.CONTENT_ROW).size(), 1)
	assert_eq(run.abilities.transform_material([column.piece_id], LineClearState.CONTENT_COLUMN).size(), 1)
	assert_eq(run.abilities.transform_material([core.piece_id, extra_core.piece_id], &"special_demolition").size(), 2)
	run.state.line_clear.upgrades[&"line_clear_score"] = 1
	run.state.explosion.reward_level = 1
	var results: Array[MatchResult] = run.abilities.resolve_removal([run.state.rules.state.get_piece(row.piece_id)], &"skill_clear")
	var sources: Array[int] = []
	for result: MatchResult in results:
		sources.append(result.source_id)
		if result.cause == &"line_clear": assert_gt(result.score_entry.extra_score, 0)
	assert_eq(sources, [row.piece_id, column.piece_id, core.piece_id, extra_core.piece_id])
	assert_true(run.state.line_clear.instances.is_empty())
	assert_true(run.state.explosion.instances.is_empty())
	assert_eq(run.state.rule_error, "")

func test_real_files_replay_all_three_conversion_commands() -> void:
	for card: SkillDefinition in CARDS:
		var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 101)
		run.initialize("fixture_transform")
		run.recorder = RunRecorder.new()
		run.recorder.begin(run, "fixture", true, "issue101", "user://test_conversion")
		assert_true(run.execute_command(_command(run, card)).accepted)
		while run.state.phase != RunState.Phase.INPUT and not run.state.is_game_over: run.advance()
		run.recorder.finish(run, "abandoned", "conversion_test")
		var replay: RuleReplay = RuleReplay.new()
		assert_true(replay.replay_file(run.recorder.path), replay.error)
		assert_eq(RunSnapshot.digest(RunSnapshot.capture(replay.run)), RunSnapshot.digest(RunSnapshot.capture(run)))
		DirAccess.remove_absolute(run.recorder.path)

func test_telemetry_records_transformation_without_counting_births_removals_or_score() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 101)
	run.initialize("fixture_transform")
	run.recorder = RunRecorder.new()
	var projector: TelemetryProjector = TelemetryProjector.new(MemorySink.new(), "conversion-test")
	run.recorder.record_appended.connect(projector.observe_record)
	run.recorder.begin(run, "fixture", false)
	assert_true(run.execute_command(_command(run, CARDS[2])).accepted)
	var facts: int = 0
	var choices: int = 0
	for event: Dictionary in projector.events:
		if event.event_name == "rule_fact":
			assert_eq(event.payload.fact, "transformation")
			assert_eq(event.payload.piece.content_id, "special_line_column")
			facts += 1
		if event.event_name == "skill_acquired":
			assert_eq(event.payload.transformed.size(), 3)
			assert_true(event.payload.created.is_empty())
			assert_true(event.payload.removed.is_empty())
			assert_eq(event.payload.score_delta, "0")
			assert_eq(event.payload.net_empty, "0")
			choices += 1
	assert_eq(facts, 3)
	assert_eq(choices, 1)
	assert_eq(projector.error, "")

func test_composite_keeps_both_batches_of_transformation_results() -> void:
	var run: RunController = _run(6)
	var effect: CompositeEffect = CompositeEffect.new()
	effect.children = [CARDS[0].choice_effect, CARDS[1].choice_effect]
	var frozen: CompositeSkillTarget = effect.freeze(SkillRules.effect_context(run.state), run.state.rewards.target_random)
	var result: SkillApplyResult = SkillApplyResult.new()
	assert_eq(AbilityEffectRunner.preflight(run, effect, frozen), "")
	assert_eq(AbilityEffectRunner.apply_skill_effect(run, effect, frozen, result), "")
	assert_eq(result.transformed.size(), 6)
	assert_eq(run.state.explosion.instances.size(), 3)
	assert_eq(run.state.line_clear.instances.size(), 3)
