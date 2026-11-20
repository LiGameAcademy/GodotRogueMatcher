extends RefCounted

const DEMO: Script = preload("res://gameplay/skills/debug/mixed_template_demo.gd")
const CHOICE: Script = preload("res://tests/support/shape_unlock_fixture.gd")

static func move(run: RunController) -> CommandResult:
	var command: MovePieceCommand = MovePieceCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
	command.piece_id = run.state.rules.state.get_piece_id(DEMO.source(run.initialization))
	command.target = DEMO.target(run.initialization)
	return run.execute_command(command)

static func finish(run: RunController) -> RunStepResult:
	for index: int in range(12):
		if run.state.pending_rewards > 0:
			var response: CommandResult = CHOICE.choose(run, &"fixture_mixed_refill")
			if response == null or not response.accepted: return null
		var step: RunStepResult = run.advance()
		if step.kind in [&"input", &"error", &"ended"]: return step
	return null

static func settle_ui(test: GutTest, board: Board) -> void:
	var ready: bool = await test.wait_until(func() -> bool:
		var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
		return board.can_selected or (is_instance_valid(popup) and popup.offer != null), 6.0)
	test.assert_true(ready)
	if not ready or board.can_selected: return
	var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	test.assert_eq(popup.offer.choices.size(), 1)
	popup._select(0)
	popup.confirm_selection()
	test.assert_true(await test.wait_until(func() -> bool: return board.can_selected, 6.0))
