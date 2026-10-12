extends GutTest

func _source(id: int = 1, core: bool = false) -> PieceState:
	var source: PieceState = PieceState.new()
	source.piece_id = id
	source.match_color = 2
	source.coordinate = Vector2i(3, 3)
	source.content_id = &"special_demolition" if core else &""
	return source

func _instance(id: int = 1) -> AbilityInstance:
	var instance: AbilityInstance = AbilityInstance.new()
	instance.owner_id = id
	instance.definition = AbilityResolver.EXPLOSION
	return instance

func _cause(causes: Array[StringName]) -> RemovalCauseCondition:
	var condition: RemovalCauseCondition = RemovalCauseCondition.new()
	condition.allowed_causes = causes
	return condition

func _composite(operator: String, children: Array[TriggerCondition]) -> CompositeTriggerCondition:
	var condition: CompositeTriggerCondition = CompositeTriggerCondition.new()
	condition.operator = operator
	condition.conditions = children
	return condition

func test_duplicate_event_and_completion_never_repeat_unlimited_ability() -> void:
	var bus: AbilityEvents = AbilityEvents.new()
	var instance: AbilityInstance = _instance()
	instance.definition = instance.definition.duplicate(true) as AbilityDefinition
	instance.definition.max_triggers = 0
	var event: AbilityEvent = bus.removal(_source(), &"match", 9, 1)
	var accepted: Array[AbilityActivation] = bus.dispatch([event, event], [instance, instance])
	assert_eq(accepted.size(), 1)
	assert_eq(instance.trigger_count, 0, "接受事件时不能提前消费")
	assert_true(bus.complete(accepted[0], true, 1))
	assert_false(bus.complete(accepted[0], true, 1))
	assert_true(bus.dispatch([event], [instance]).is_empty())
	assert_eq(instance.trigger_count, 1)
	assert_eq(instance.pending_event_id, 0)
	assert_eq(bus.dispatch([bus.removal(_source(), &"match", 10, 1)], [instance]).size(), 1)

func test_failed_application_does_not_consume_and_empty_policy_is_explicit() -> void:
	var bus: AbilityEvents = AbilityEvents.new()
	var instance: AbilityInstance = _instance()
	instance.definition = instance.definition.duplicate(true) as AbilityDefinition
	instance.definition.consume_on_empty = false
	var accepted: Array[AbilityActivation] = bus.dispatch([bus.removal(_source(), &"match", 1, 1)], [instance])
	assert_false(bus.complete(accepted[0], false, 1))
	assert_eq(instance.trigger_count, 0)
	assert_eq(instance.pending_event_id, 0)
	accepted = bus.dispatch([bus.removal(_source(), &"match", 2, 1)], [instance])
	assert_true(bus.complete(accepted[0], true, 0))
	assert_eq(instance.trigger_count, 0)
	instance.definition.consume_on_empty = true
	accepted = bus.dispatch([bus.removal(_source(), &"consume", 3, 1)], [instance])
	assert_true(accepted.is_empty(), "普通引信不允许主动引爆")
	accepted = bus.dispatch([bus.removal(_source(1, true), &"consume", 3, 1)], [instance])
	assert_true(bus.complete(accepted[0], true, 0))
	assert_eq(instance.trigger_count, 1)
	assert_eq(AbilityResolver.EXPLOSION.consume_on_empty, true)

func test_event_source_is_frozen_twice_and_does_not_query_removed_board_piece() -> void:
	var bus: AbilityEvents = AbilityEvents.new()
	var source: PieceState = _source()
	var event: AbilityEvent = bus.removal(source, &"match", 7, 2, "test-run", 5, &"parent_blast")
	source.match_color = 4
	source.coordinate = Vector2i.ZERO
	var accepted: Array[AbilityActivation] = bus.dispatch([event], [_instance()])
	event.source.match_color = 3
	assert_eq(accepted[0].event.source.match_color, 2)
	assert_eq(accepted[0].event.source.coordinate, Vector2i(3, 3))
	assert_eq(accepted[0].event.root_action_id, 7)
	assert_eq(accepted[0].event.generation, 2)
	assert_eq(accepted[0].event.to_context().run_id, "test-run")
	assert_eq(accepted[0].event.to_context().parent_event_id, 5)
	assert_eq(accepted[0].event.to_context().source_ability_id, &"parent_blast")

func test_shuffled_events_and_listeners_have_stable_generation_source_ability_order() -> void:
	var bus: AbilityEvents = AbilityEvents.new()
	var later: AbilityEvent = bus.removal(_source(1), &"match", 1, 2)
	var second: AbilityEvent = bus.removal(_source(2), &"match", 1, 1)
	var first: AbilityEvent = bus.removal(_source(1), &"match", 1, 1)
	var a: AbilityInstance = _instance(1)
	var b: AbilityInstance = _instance(1)
	a.definition = a.definition.duplicate(true) as AbilityDefinition
	b.definition = b.definition.duplicate(true) as AbilityDefinition
	a.definition.ability_id = &"a"
	b.definition.ability_id = &"b"
	var accepted: Array[AbilityActivation] = bus.dispatch([later, second, first], [_instance(2), b, a])
	assert_eq(accepted.size(), 3, "未完成的同实例能力不能再排第二次")
	assert_eq(accepted[0].event.event_id, first.event_id)
	assert_same(accepted[0].instance, a)
	assert_same(accepted[1].instance, b)
	assert_eq(accepted[2].event.source.piece_id, 2)

func test_all_any_not_and_always_only_query_and_do_not_consume_rng() -> void:
	var bus: AbilityEvents = AbilityEvents.new()
	var instance: AbilityInstance = _instance()
	instance.definition = instance.definition.duplicate(true) as AbilityDefinition
	instance.definition.conditions = [_composite("AND", [AlwaysAbilityCondition.new(),
		_composite("OR", [_cause([&"match"]), _cause([&"explosion"])]),
		_composite("NOR", [_cause([&"consume"])])])]
	assert_eq(AbilityTriggerAdapter.validation_error(instance.definition), "")
	seed(123)
	var expected: int = randi()
	seed(123)
	assert_true(AbilityTriggerAdapter.matches(instance, bus.removal(_source(), &"match", 1, 1)))
	assert_true(AbilityTriggerAdapter.matches(instance, bus.removal(_source(), &"explosion", 1, 1)))
	assert_false(AbilityTriggerAdapter.matches(instance, bus.removal(_source(1, true), &"consume", 1, 1)))
	assert_eq(instance.trigger_count, 0)
	assert_eq(randi(), expected)

func test_invalid_event_cause_composition_or_depth_is_diagnostic() -> void:
	var definition: AbilityDefinition = AbilityResolver.EXPLOSION.duplicate(true) as AbilityDefinition
	definition.conditions = [_cause([&"typo"])]
	assert_string_contains(AbilityTriggerAdapter.validation_error(definition), "原因")
	definition.conditions = [_composite("AND", [])]
	assert_string_contains(AbilityTriggerAdapter.validation_error(definition), "子项")
	definition.conditions = [_composite("XOR", [AlwaysAbilityCondition.new()])]
	assert_string_contains(AbilityTriggerAdapter.validation_error(definition), "未支持")
	var nested: TriggerCondition = AlwaysAbilityCondition.new()
	for index: int in range(9): nested = _composite("AND", [nested])
	definition.conditions = [nested]
	assert_string_contains(AbilityTriggerAdapter.validation_error(definition), "过深")
	definition.conditions = []
	definition.max_triggers = -1
	assert_string_contains(AbilityTriggerAdapter.validation_error(definition), "为负")

func test_reset_invalidates_old_bus_events_and_pending_completion() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	var core: PieceState = run.abilities.add_core(Vector2i(4, 4))
	var instance: AbilityInstance = run.state.explosion.instances[core.piece_id]
	var old: AbilityEvents = run.state.ability_events
	var event: AbilityEvent = old.removal(core, &"consume", 1, 1)
	var accepted: Array[AbilityActivation] = old.dispatch([event], [instance])
	run.state.reset_counters()
	assert_true(old.dispatch([event], [instance]).is_empty())
	assert_false(old.complete(accepted[0], true, 1))
	assert_true(run.state.ability_events.dispatch([event], [_instance(core.piece_id)]).is_empty())
	assert_eq(instance.trigger_count, 0)
	assert_eq(run.state.explosion.instances.size(), 0)
	assert_eq(run.state.ability_events.data().next_event_id, 1)

func test_invalid_batch_is_rejected_before_reserving_or_consuming_any_instance() -> void:
	var bus: AbilityEvents = AbilityEvents.new()
	var first: AbilityInstance = _instance()
	var invalid: AbilityInstance = _instance(2)
	invalid.definition = invalid.definition.duplicate(true) as AbilityDefinition
	invalid.definition.event_type = &"typo"
	var event: AbilityEvent = bus.removal(_source(), &"match", 1, 1)
	assert_true(bus.dispatch([event], [first, invalid]).is_empty())
	assert_string_contains(bus.last_error, "未接入")
	assert_eq(first.pending_event_id, 0)
	assert_eq(first.trigger_count, 0)
	assert_true(bus.data().dispatched.is_empty())
	assert_true(bus.dispatch([null], [first]).is_empty())
	assert_string_contains(bus.last_error, "来源")
	assert_true(bus.dispatch([event], [first, _instance()]).is_empty())
	assert_string_contains(bus.last_error, "身份重复")
	assert_eq(bus.dispatch([event], [first]).size(), 1, "无效批次没有吞掉事件")

func test_real_empty_manual_detonation_keeps_action_cost_and_consumes_once() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	var core: PieceState = run.abilities.add_core(Vector2i(4, 4))
	var instance: AbilityInstance = run.state.explosion.instances[core.piece_id]
	run.state.explosion.upgrades[&"core_manual_detonation"] = 1
	run.state.phase = RunState.Phase.INPUT
	var command: DetonateCoreCommand = DetonateCoreCommand.new(run.state.run_id, 1, 0)
	command.piece_id = core.piece_id
	var result: CommandResult = run.execute_command(command)
	assert_true(result.accepted)
	assert_eq(run.state.action_id, 1)
	assert_null(run.state.rules.state.get_piece(core.piece_id))
	assert_eq(instance.trigger_count, 1)
	assert_eq(instance.pending_event_id, 0)
	assert_eq(run.state.ledger.total, 0)
	assert_same(run.execute_command(command), result)
	assert_eq(instance.trigger_count, 1)
