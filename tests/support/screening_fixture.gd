extends RefCounted

const CHOICE: Script = preload("res://tests/support/shape_unlock_fixture.gd")

static func move(run: RunController) -> CommandResult:
	var command: MovePieceCommand = MovePieceCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
	command.piece_id = run.state.rules.state.get_piece_id(ScreeningDeck.source(run.initialization))
	command.target = ScreeningDeck.target(run.initialization)
	return run.execute_command(command)

static func settle(run: RunController) -> RunStepResult:
	for index: int in range(12):
		if run.state.pending_rewards > 0:
			var response: CommandResult = CHOICE.choose(run, &"fixture_screening_refill")
			if response == null or not response.accepted: return null
		var step: RunStepResult = run.advance()
		if step.kind in [&"input", &"error", &"finished"]: return step
	return null
