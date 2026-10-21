extends RefCounted

static func run(empty: bool = false, stage: StageConfig = null) -> RunController:
	var controller: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 118, stage, ShapeUnlockDemo.PROFILE)
	controller.initialize("fixture_shape_unlock_empty" if empty else "fixture_shape_unlock")
	return controller

static func choose(controller: RunController, id: StringName = &"fixture_unlock_l") -> CommandResult:
	var offer: SkillOffer = controller.prepare_offer()
	if offer == null: return null
	var command: ChooseSkillCommand = ChooseSkillCommand.new(controller.state.run_id, controller.last_command_id + 1, controller.state.action_id)
	command.offer_id = offer.offer_id
	command.reward_id = offer.reward_id
	command.skill_id = id
	return controller.execute_command(command)

static func record(controller: RunController, disk: bool = false) -> void:
	controller.recorder = RunRecorder.new()
	controller.recorder.begin(controller, "shape_unlock_fixture", disk, "development", "user://shape_unlock_records")
