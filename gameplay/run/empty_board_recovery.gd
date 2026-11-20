class_name EmptyBoardRecovery
extends RefCounted

## Called only at an input boundary after rewards and the original continuation finish.
static func advance(run: RunController) -> RunStepResult:
	var state: RunState = run.state
	var shapes: ShapeUnlockState = state.rules.shape_unlocks
	if not shapes.recovery_pending: return null
	if state.rules.state.get_piece_count() > 0:
		shapes.recovery_pending = false
		return null
	var result: RunStepResult = RunStepResult.new()
	result.kind = &"recovery"
	if shapes.recovery_attempted:
		_fail(state, "empty_board_after_recovery")
		return result
	shapes.recovery_attempted = true
	shapes.recovery_batch_id += 1
	# A fresh rule identity resets per-root trigger guards; no valid move or stage action is added.
	state.action_id += 1
	shapes.recovery_action_id = state.action_id
	state.rule_action_id = shapes.recovery_action_id
	var count: int = state.next_refill_count()
	if count <= 0:
		_fail(state, "empty_recovery_has_no_supply")
		return result
	# Consume the displayed tokens, never the finite modifier's batch counters.
	result.spawns = run.spawn_batch(count, &"empty_recovery", shapes.recovery_batch_id)
	if state.rule_error.is_empty():
		result.matches.append_array(DemolitionRules.settle(state, shapes.recovery_action_id))
	if state.rule_error.is_empty() and state.rules.state.get_piece_count() == 0:
		_fail(state, "empty_board_after_recovery")
	# Keep the process/budget alive through any rewards caused by these births.
	# The next actual input boundary closes it only when the board remains nonempty.
	run.check_rewards()
	return result

static func _fail(state: RunState, reason: String) -> void:
	state.rule_error = reason
	state.phase = RunState.Phase.ERROR
