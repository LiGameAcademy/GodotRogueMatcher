extends GutTest

## Verifies nested production selectors and the committed dye/match/mark/descendant order.
const HOST: PackedScene = preload("res://tools/chain_rhythm_acceptance/chain_rhythm_acceptance.tscn")
const HOST_SCRIPT: Script = preload("res://tools/chain_rhythm_acceptance/chain_rhythm_acceptance.gd")
const CASE: Script = preload("res://tools/chain_rhythm_acceptance/composite_rhythm_case.gd")

var _host: HOST_SCRIPT
var _phases: Array[Dictionary] = []
var _cancel_once: bool = false

func after_each() -> void:
	get_tree().paused = false
	UIManager.close_popup()
	if is_instance_valid(_host): _host.queue_free()
	_host = null
	await wait_process_frames(5)

func _start_host() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_host = HOST.instantiate() as HOST_SCRIPT
	add_child_autofree(_host)
	assert_true(await wait_until(func() -> bool: return not _host.loading, 6.0))

func test_nested_dynamic_acquire_matches_then_marks_before_two_descendants() -> void:
	var run: RunController = CASE.create()
	var offer: SkillOffer = run.state.rewards.active_offer
	assert_not_null(offer)
	var target: CompositeSkillTarget = offer.targets[offer.choices[0].skill_id] as CompositeSkillTarget
	assert_true((target.leaf_targets[0] as CompositeSkillTarget).leaf_targets[0].deferred)
	assert_true(target.leaf_targets[1].deferred)
	var result: SkillApplyResult = SkillRules.apply(run, offer.offer_id, offer.choices[0].skill_id)
	assert_true(result.success, result.error)
	assert_eq(result.completed_leaves, ["0.0", "1"])
	assert_eq(result.marked_ids, [6, 8])
	var causes: Array[StringName] = []
	for event: MatchResult in result.matches: causes.append(event.cause)
	assert_eq(causes, [&"dye", &"match", &"explosion", &"explosion"])
	assert_eq(run.state.ledger.total, 60)
	assert_eq(run.state.rewards.consumed_count, 1)
	assert_true(run.abilities.flush_held_blasts().is_empty())
	run.retire()

func test_skill_plan_preserves_mark_boundary_before_deferred_descendants() -> void:
	var run: RunController = CASE.create()
	var offer: SkillOffer = run.state.rewards.active_offer
	var result: SkillApplyResult = SkillRules.apply(run, offer.offer_id, offer.choices[0].skill_id)
	var plan: Array[PresentationStep] = PlaybackPlanBuilder.skill(result, 0.2)
	assert_eq(plan.size(), 5, "dye, match, mark, blast, blast need separate causal steps")
	assert_eq(plan[2].kind, PresentationStep.Kind.MARK_FUSES)
	assert_eq(plan[2].policy, PresentationStep.Policy.COMPLETE_REQUIRED)
	assert_eq(result.mark_batches[0].after_match_count, 2)
	result.mark_batches[0].pieces[0].coordinate = Vector2i.ZERO
	assert_eq(plan[2].pieces[0].coordinate, Vector2i(3, 3))
	assert_eq(run.state.rules.state.get_piece(8).coordinate, Vector2i(8, 8))
	run.retire()

func test_real_nested_choice_keeps_mark_visibility_and_rules_in_four_modes() -> void:
	await _start_host()
	_host.board.view.match_visualized.connect(_on_match)
	_host.board.view.fuses_visualized.connect(_on_mark)
	var baseline: String = ""
	for fast: bool in [false, true]:
		for reduced: bool in [false, true]:
			await _host.load_case("composite_chain")
			_host.configure_modes(fast, reduced)
			_phases.clear()
			await _host.play_case()
			assert_true(_host._sample_valid(_host.report))
			assert_eq(_phases.size(), 5)
			if _phases.size() != 5: continue
			assert_eq(_phases[0].cause, "dye")
			assert_eq(_phases[1].cause, "match")
			assert_eq(_phases[0].marked, [false, false])
			assert_eq(_phases[1].marked, [false, false])
			assert_eq(_phases[2].cause, "mark")
			assert_eq(_phases[2].marked, [true, true])
			assert_eq(_phases[3].cause, "explosion")
			assert_eq(int(_host.report.visualized_score), 60)
			assert_eq(_host.board.run.state.rewards.consumed_count, 1)
			assert_true(_host.report.input_restored)
			if baseline.is_empty(): baseline = str(_host.report.rules_digest)
			else: assert_eq(str(_host.report.rules_digest), baseline)
			var invalid: Dictionary = _host.report.duplicate(true)
			invalid.markers[0].at_ms = 0.0
			assert_false(_host._sample_valid(invalid))

func test_cancel_at_mark_boundary_retires_old_run_and_clears_pending_markers() -> void:
	await _start_host()
	_host.board.view.fuses_visualized.connect(_cancel_at_mark)
	for fast: bool in [false, true]:
		for reduced: bool in [false, true]:
			await _host.load_case("composite_chain")
			_host.configure_modes(fast, reduced)
			var old: RunController = _host.board.run
			_cancel_once = true
			_host.play_case()
			assert_true(await wait_until(func() -> bool: return _host.case_key == "blast_row" and not _host.loading, 6.0))
			assert_true(old.is_retired())
			var digest: String = RunSnapshot.digest(RunSnapshot.capture(_host.board.run))
			await wait_process_frames(20)
			assert_eq(RunSnapshot.digest(RunSnapshot.capture(_host.board.run)), digest)
			assert_true(_host.report.is_empty())
			assert_true(_host.board.can_selected)
			assert_true((_host.board.view.get("_deferred_fuse_ids") as Array).is_empty())

func _marker_flags() -> Array[bool]:
	var flags: Array[bool] = []
	for id: int in [6, 8]:
		var piece: ChessPiece = _host.board.view.get_piece(id)
		flags.append(is_instance_valid(piece) and StringName(piece.get("_ability_kind")) == &"引")
	return flags

func _on_match(result: MatchResult, _cells: Array[Cell]) -> void:
	_phases.append({"cause": String(result.cause), "marked": _marker_flags()})

func _on_mark(_pieces: Array[PieceState]) -> void:
	_phases.append({"cause": "mark", "marked": _marker_flags()})

func _cancel_at_mark(_pieces: Array[PieceState]) -> void:
	if _cancel_once:
		_cancel_once = false
		_host.load_case.call_deferred("blast_row")
