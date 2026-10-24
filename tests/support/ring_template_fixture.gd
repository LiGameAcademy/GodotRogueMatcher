extends RefCounted

const RING: MatchShapeTemplate = preload("res://gameplay/board/matching/ring_template.tres")
const U: MatchShapeTemplate = preload("res://gameplay/board/matching/u_template.tres")

static func run(ring_enabled: bool = true, u_enabled: bool = false) -> RunController:
	var templates: Array[MatchShapeTemplate] = []
	if ring_enabled: templates.append(RING)
	if u_enabled: templates.append(U)
	return RunController.new(BoardRules.new(BoardState.new(9, 9), 5, templates), 118, null, RunController.RING_PROFILE)

static func unlock_run(empty: bool = false) -> RunController:
	var result: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 118, null, RunController.RING_PROFILE)
	result.initialize("fixture_shape_unlock_ring_empty" if empty else "fixture_shape_unlock_ring")
	return result

static func place(controller: RunController, offsets: Array[Vector2i], origin: Vector2i = Vector2i.ZERO, color: int = 0, missing: Vector2i = Vector2i(-1, -1)) -> void:
	for offset: Vector2i in offsets:
		if offset != missing and controller.state.rules.state.get_piece_at(origin + offset) == null:
			controller.state.rules.place_piece(origin + offset, color)

static func move(controller: RunController, piece: PieceState, target: Vector2i) -> CommandResult:
	var command: MovePieceCommand = MovePieceCommand.new(controller.state.run_id, controller.last_command_id + 1, controller.state.action_id)
	command.piece_id = piece.piece_id
	command.target = target
	return controller.execute_command(command)

static func next_coordinate(controller: RunController, target: Vector2i) -> bool:
	var empty: Array[Vector2i] = controller.state.rules.state.get_empty_coordinates()
	for seed_value: int in range(10000):
		var random: RandomNumberGenerator = RandomNumberGenerator.new()
		random.seed = seed_value
		if empty[random.randi_range(0, empty.size() - 1)] == target:
			controller.state.random.seed = seed_value
			return true
	return false
## Resolve genuine classic score rewards without hiding thresholds or changing the board.
static func bonus(controller: RunController) -> void:
	var helpers: Script = load("res://tests/support/shape_unlock_fixture.gd") as Script
	while controller.state.pending_rewards > 0:
		var offer: SkillOffer = controller.prepare_offer()
		if offer == null: return
		var skill: StringName = &"fixture_unlock_u" if offer.choices.any(func(choice: SkillDefinition) -> bool: return choice.skill_id == &"fixture_unlock_u") else &"refill_less"
		var result: CommandResult = helpers.choose(controller, skill)
		if result == null or not result.accepted: return
## The ring's 104 points legitimately cross the first classic reward threshold.
static func confirm_bonus(test: GutTest) -> void:
	var ready: bool = await test.wait_until(func() -> bool:
		var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
		return is_instance_valid(popup) and popup.offer != null and not popup.offer.choices.any(func(choice: SkillDefinition) -> bool: return choice.skill_id == &"fixture_unlock_ring") and popup.offer.choices.any(func(choice: SkillDefinition) -> bool: return choice.skill_id == &"fixture_unlock_u"), 6.0)
	test.assert_true(ready, "classic bonus must offer the remaining U unlock")
	if not ready: return
	var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	for index: int in range(popup.offer.choices.size()):
		if popup.offer.choices[index].skill_id == &"fixture_unlock_u":
			popup._select(index)
			popup.confirm_selection()
			return
