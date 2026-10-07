extends GutTest

func _instance(owner_id: int = 1) -> AbilityInstance:
	var instance: AbilityInstance = AbilityInstance.new()
	instance.owner_id = owner_id
	instance.definition = AbilityResolver.EXPLOSION
	return instance

func _event(cause: StringName = &"match", source_id: int = 1) -> AbilityEvent:
	var event: AbilityEvent = AbilityEvent.new()
	event.cause = cause
	event.source = PieceState.new()
	event.source.piece_id = source_id
	event.source.match_color = 1
	event.source.coordinate = Vector2i(4, 4)
	event.root_action_id = 7
	return event

func test_resource_composes_core_trigger_conditions_and_independent_effect() -> void:
	var definition: AbilityDefinition = AbilityResolver.EXPLOSION
	assert_eq(AbilityTriggerAdapter.validation_error(definition), "")
	assert_true(definition.trigger is GameplayTrigger)
	assert_true(definition.trigger.conditions[0] is CompositeTriggerCondition)
	assert_true(definition.trigger.should_trigger(_event().to_context()))
	assert_true(definition.trigger.should_trigger(_event(&"explosion").to_context()))
	assert_false(definition.trigger.should_trigger(_event(&"cleanup").to_context()))
	var event: AbilityEvent = _event()
	event.event_type = &"turn_started"
	assert_false(definition.trigger.should_trigger(event.to_context()))
	assert_true(definition.effect is ExplodeEffect)

func test_instances_own_counts_without_mutating_shared_trigger_or_global_rng() -> void:
	var first: AbilityInstance = _instance()
	var second: AbilityInstance = _instance()
	seed(123)
	var expected: int = randi()
	seed(123)
	assert_true(AbilityTriggerAdapter.try_accept(first, _event()))
	assert_false(AbilityTriggerAdapter.try_accept(first, _event()), "同一实例只接受一次")
	assert_eq(randi(), expected, "确定触发不能消费全局随机数")
	assert_same(first.definition.trigger, second.definition.trigger)
	assert_eq(first.trigger_count, 1)
	assert_eq(second.trigger_count, 0)
	assert_eq(first.definition.trigger.trigger_count, 0)
	assert_true(AbilityTriggerAdapter.try_accept(second, _event()))
	assert_eq(second.trigger_count, 1)

func test_wrong_owner_event_or_cause_never_consumes_trigger_count() -> void:
	var instance: AbilityInstance = _instance()
	assert_false(AbilityTriggerAdapter.try_accept(instance, _event(&"match", 2)))
	assert_false(AbilityTriggerAdapter.try_accept(instance, _event(&"cleanup")))
	var event: AbilityEvent = _event()
	event.event_type = &"skill_acquired"
	assert_false(AbilityTriggerAdapter.try_accept(instance, event))
	assert_eq(instance.trigger_count, 0)
	assert_false(instance.has_triggered)

func test_changing_only_condition_changes_real_resolver_trigger() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	var core: PieceState = run.abilities.add_core(Vector2i(2, 0))
	var instance: AbilityInstance = run.state.explosion.instances[core.piece_id]
	var definition: AbilityDefinition = instance.definition.duplicate(true) as AbilityDefinition
	var composite: CompositeTriggerCondition = definition.trigger.conditions[0] as CompositeTriggerCondition
	var condition: RemovalCauseCondition = composite.conditions[1] as RemovalCauseCondition
	condition.allowed_causes = [&"explosion"]
	instance.definition = definition
	for x: int in [0, 1, 3, 4]: run.state.rules.place_piece(Vector2i(x, 0), 1)
	run.state.rules.place_piece(Vector2i(2, 1), 0)
	var random_state: int = run.state.random.state
	var results: Array[MatchResult] = run.resolve_all_matches()
	assert_eq(results.size(), 1, "匹配依然成立，但条件阻止核心爆炸")
	assert_eq(run.state.ledger.total, 50)
	assert_eq(run.state.rules.state.get_piece_count(), 1)
	assert_eq(instance.trigger_count, 0)
	assert_eq(run.state.random.state, random_state)
	assert_true(AbilityResolver.EXPLOSION.trigger.should_trigger(_event().to_context()), "模板不能被实例配置修改")

func test_invalid_probability_refuses_entire_batch_before_board_or_score_commit() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	var core: PieceState = run.abilities.add_core(Vector2i(2, 0))
	var instance: AbilityInstance = run.state.explosion.instances[core.piece_id]
	instance.definition = instance.definition.duplicate(true) as AbilityDefinition
	instance.definition.trigger.trigger_chance = 0.5
	for x: int in [0, 1, 3, 4]: run.state.rules.place_piece(Vector2i(x, 0), 1)
	assert_eq(run.abilities.resolve(run.state.rules.find_matches()).size(), 0)
	assert_string_contains(run.abilities.last_error, "随机协议")
	assert_eq(run.state.ledger.total, 0)
	assert_eq(run.state.rules.state.get_piece_count(), 5)
	assert_eq(instance.trigger_count, 0)
	assert_true(run.state.explosion.instances.has(core.piece_id))

func test_cyclic_or_missing_condition_is_a_diagnostic_not_recursive_evaluation() -> void:
	var definition: AbilityDefinition = AbilityResolver.EXPLOSION.duplicate(true) as AbilityDefinition
	var composite: CompositeTriggerCondition = CompositeTriggerCondition.new()
	composite.conditions = [composite]
	definition.trigger.conditions = [composite]
	assert_string_contains(AbilityTriggerAdapter.validation_error(definition), "循环")
	assert_string_contains(String(RunSnapshot.trigger_config(definition).invalid), "循环")
	composite.conditions.clear()
	definition.trigger.conditions = [null]
	assert_string_contains(AbilityTriggerAdapter.validation_error(definition), "缺失")
	assert_string_contains(String(RunSnapshot.trigger_config(definition).invalid), "缺失")
	definition.trigger = null
	assert_string_contains(String(RunSnapshot.trigger_config(definition).invalid), "缺失")

func test_configuration_and_snapshot_include_trigger_parameters_and_instance_counts() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	var core: PieceState = run.abilities.add_core(Vector2i(4, 4))
	var config: Dictionary = RunSnapshot.config(run)
	assert_eq(config.ability_trigger.event, "piece_eliminated")
	assert_eq(config.ability_trigger.limit, "1")
	assert_false(RunSnapshot.canonical(config).contains("Resource#"))
	var changed: AbilityDefinition = AbilityResolver.EXPLOSION.duplicate(true) as AbilityDefinition
	var composite: CompositeTriggerCondition = changed.trigger.conditions[0] as CompositeTriggerCondition
	(composite.conditions[1] as RemovalCauseCondition).allowed_causes = [&"match"]
	assert_ne(RunSnapshot.digest(RunSnapshot.trigger_config(changed)), RunSnapshot.digest(config.ability_trigger))
	assert_eq(RunSnapshot.capture(run).instances[0].trigger_count, "0")
	assert_true(AbilityTriggerAdapter.try_accept(run.state.explosion.instances[core.piece_id], _event(&"match", core.piece_id)))
	assert_eq(RunSnapshot.capture(run).instances[0].trigger_count, "1")
