extends GutTest

var previous_run: RunController
var protected_run: RunController

func before_each() -> void:
	previous_run = GameManager.run
	protected_run = _run(134)
	GameManager.reset_game(protected_run)

func after_each() -> void:
	GameManager.reset_game(previous_run)

func _run(seed_value: int) -> RunController:
	return RunController.new(BoardRules.new(BoardState.new(9, 9), 5), seed_value)

func test_local_score_config_does_not_write_current_game() -> void:
	var local: RunController = _run(1)
	var other: RunController = _run(2)
	var before: String = RunSnapshot.digest(RunSnapshot.capture(protected_run))
	var config: ItemEffectConfig = ItemEffectConfig.new()
	config.effects = [EffectAddScore.new(0.5, 10)]
	assert_true(config.apply_effects({"score": 100, "ledger": local.state.ledger}))
	assert_eq(local.state.ledger.total, 60)
	assert_eq(other.state.ledger.total, 0)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(protected_run)), before)

func test_local_dye_and_destroy_keep_identity_and_do_not_touch_other_runs() -> void:
	var local: RunController = _run(1)
	var other: RunController = _run(2)
	var piece: PieceState = local.state.rules.place_piece(Vector2i(3, 2), 1)
	other.state.rules.place_piece(Vector2i(3, 2), 1)
	var before: String = RunSnapshot.digest(RunSnapshot.capture(protected_run))
	var context: Dictionary = {"run": local, "coordinate": Vector2i(2, 2)}
	assert_true(EffectDyePiece.new(4, "adjacent", 1).apply(context))
	assert_eq(local.state.rules.state.get_piece(piece.piece_id).match_color, 4)
	assert_eq(other.state.rules.state.get_piece_at(Vector2i(3, 2)).match_color, 1)
	assert_true(EffectDestroyPieces.new("adjacent", false).apply(context))
	assert_null(local.state.rules.state.get_piece(piece.piece_id))
	assert_eq(local.state.ledger.total, 0)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(protected_run)), before)

func test_score_effect_requires_explicit_ledger_instead_of_global_fallback() -> void:
	var before: String = RunSnapshot.digest(RunSnapshot.capture(protected_run))
	assert_false(EffectAddScore.new(1.0, 10).apply({"score": 100}))
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(protected_run)), before)

func test_legacy_dispatchers_are_not_installed_or_subscribed() -> void:
	for name_text: String in ["SpawnManager", "ItemEffectSystem", "ItemPlacer", "ItemRegistry"]:
		assert_null(get_node_or_null("/root/" + name_text))
	var before: String = RunSnapshot.digest(RunSnapshot.capture(protected_run))
	GameManager.turn_started.emit(1)
	GameManager.turn_ended.emit(1)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(protected_run)), before)

func test_local_catalog_instances_do_not_share_mutable_effect_config() -> void:
	var catalog: ItemRegistry = ItemRegistry.new()
	var first: ItemData = catalog.create_dye_station()
	var second: ItemData = catalog.create_dye_station()
	(first.effect_config.effects[0] as EffectDyePiece).target_color = 4
	assert_ne(first.effect_config, second.effect_config)
	assert_eq((second.effect_config.effects[0] as EffectDyePiece).target_color, -1)

func test_retained_timing_values_only_control_explicit_local_invocation() -> void:
	var config: ItemEffectConfig = ItemEffectConfig.new()
	config.conditions = [ConditionTiming.new(ItemEffectConfig.TriggerTiming.ON_MATCH)]
	config.effects = [EffectAddScore.new(1.0)]
	var ledger: ScoreLedger = ScoreLedger.new()
	assert_eq(ItemEffectConfig.TriggerTiming.ON_MATCH, 3)
	assert_false(config.apply_effects({"ledger": ledger, "score": 50, "timing": ItemEffectConfig.TriggerTiming.ON_TURN_START}))
	assert_eq(ledger.total, 0)
	assert_true(config.apply_effects({"ledger": ledger, "score": 50, "timing": ItemEffectConfig.TriggerTiming.ON_MATCH}))
	assert_eq(ledger.total, 50)
