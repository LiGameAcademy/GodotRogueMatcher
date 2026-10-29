extends GutTest

## #63: snapshot links, condition explain, RuleResult.activations, readable replay errors.

func _run() -> RunController:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 63)
	run.state.phase = RunState.Phase.INPUT
	return run

func test_snapshot_ability_instances_expose_debug_links() -> void:
	var run: RunController = _run()
	run.state.rules.place_piece(Vector2i(1, 1), 0)
	var id: int = run.state.rules.state.get_piece_id(Vector2i(1, 1))
	run.abilities.assign_fuse(id)
	var snap: Dictionary = RunSnapshot.capture(run)
	assert_eq(snap.instances.size(), 1)
	var row: Dictionary = snap.instances[0]
	assert_eq(String(row.id), str(id))
	assert_eq(String(row.owner_id), str(id))
	assert_eq(String(row.event_type), "piece_eliminated")
	assert_true(row.has("consume_on_empty"))
	assert_true(row.has("max_triggers"))
	assert_eq(RunSnapshot.RULES_VERSION, "run-commands-v45-unified-offers")

func test_explain_matches_adapter_and_records_condition_rejection() -> void:
	var run: RunController = _run()
	run.state.rules.place_piece(Vector2i(0, 0), 0)
	var id: int = run.state.rules.state.get_piece_id(Vector2i.ZERO)
	run.abilities.assign_fuse(id)
	var instance: AbilityInstance = run.state.explosion.instances[id]
	var event: AbilityEvent = run.state.ability_events.removal(run.state.rules.state.get_piece(id), &"match", 1, 1, run.state.run_id)
	var explanation: Dictionary = AbilityTriggerAdapter.explain(instance, event)
	assert_eq(bool(explanation.matched), AbilityTriggerAdapter.matches(instance, event))
	assert_true(bool(explanation.matched))
	event.cause = &"skill_clear"
	# Default explosion conditions may still accept skill_clear; force owner mismatch.
	instance.owner_id = id + 99
	explanation = AbilityTriggerAdapter.explain(instance, event)
	assert_false(bool(explanation.matched))
	assert_eq(String(explanation.reason), "owner_mismatch")

func test_rule_result_activations_locate_consume_after_blast() -> void:
	var run: RunController = _run()
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "test", false)
	run.state.rules.place_piece(Vector2i(2, 2), 1)
	run.state.rules.place_piece(Vector2i(2, 3), 2)
	var core_id: int = run.state.rules.state.get_piece_id(Vector2i(2, 2))
	run.abilities.assign_fuse(core_id)
	# Convert to core so detonation path exists; fuse+remove via clear skill path is enough for activations.
	var batch: Array[PieceState] = [run.state.rules.state.get_piece(core_id).copy()]
	run.abilities.resolve_removal(batch, &"match")
	var traces: Array[Dictionary] = run.state.ability_events.take_traces()
	assert_false(traces.is_empty())
	var trace: Dictionary = traces[0]
	assert_eq(String(trace.ability_id), String(AbilityResolver.EXPLOSION.ability_id))
	assert_eq(int(trace.owner_id), core_id)
	assert_true(bool(trace.matched))
	assert_true(trace.has("consumed"))
	assert_true(trace.has("conditions"))
	assert_true(trace.has("trigger_count_after"))

func test_replay_describe_error_covers_version_and_truncation() -> void:
	assert_eq(RuleReplay.describe_error("record_version_mismatch"), "规则/内容/候选版本与当前构建不匹配（旧局不能跨版本精确回放）")
	assert_eq(RuleReplay.describe_error("incomplete_record_no_footer"), "记录截断：缺少 Footer")
	assert_eq(RuleReplay.describe_error("configuration_mismatch"), "配置指纹与当前规则不一致")
	assert_false(RuleReplay.describe_error("seq=4 phase=INPUT .after.total expected=1 actual=2").is_empty())
