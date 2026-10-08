class_name TutorialSession
extends RefCounted

## 练习拥有独立Run，不接GameManager、记录器或采集器。
const CONFIG: TutorialConfig = preload("res://gameplay/tutorial/tutorial_config.tres")
var run: RunController
var lesson: int = 0

func reset() -> void:
	run = _new_run()
	lesson = 0
	_prepare_line()
	run.start_turn()

func next_lesson() -> void:
	lesson += 1
	if lesson == 2:
		# 清理练习补入的棋子，保留第一步已提交的50分。
		for piece: PieceState in run.state.rules.state.get_snapshot():
			run.state.rules.remove_piece(piece.piece_id)
		_prepare_line()
	elif lesson == 3:
		run = _new_run()
		run.state.explosion.upgrades[&"core_manual_detonation"] = 1
		run.abilities.add_core(CONFIG.core)
		run.abilities.upgrade_reward()
		run.state.rules.place_piece(CONFIG.core + Vector2i.UP, 0)
		run.state.rules.place_piece(CONFIG.core + Vector2i.LEFT, 2)
		run.state.rules.place_piece(Vector2i(4, 4), 3)
		run.start_turn()

func move(piece_id: int, target: Vector2i) -> CommandResult:
	var expected: Vector2i = CONFIG.spare if lesson == 1 else CONFIG.source
	var destination: Vector2i = CONFIG.refill_target if lesson == 1 else CONFIG.target
	var piece: PieceState = run.state.rules.state.get_piece(piece_id)
	if lesson == 3 or piece == null or piece.coordinate != expected or target != destination:
		return _reject("请按高亮位置完成本步练习")
	var command: MovePieceCommand = MovePieceCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
	command.piece_id = piece_id
	command.target = target
	return run.execute_command(command)

func detonate(coordinate: Vector2i) -> CommandResult:
	if lesson != 3 or coordinate != CONFIG.core: return _reject("请双击中间的爆破棋子")
	var command: DetonateCoreCommand = DetonateCoreCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
	command.piece_id = run.state.rules.state.get_piece_id(coordinate)
	return run.execute_command(command)

func choose(offer_id: int, skill_id: StringName, color: int = -1) -> CommandResult:
	var offer: SkillOffer = run.state.rewards.active_offer
	if offer == null: return _reject("没有待选择技能")
	var command: ChooseSkillCommand = ChooseSkillCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
	command.offer_id = offer_id
	command.reward_id = offer.reward_id
	command.skill_id = skill_id
	command.selected_color = color
	return run.execute_command(command)

func _new_run() -> RunController:
	return RunController.new(BoardRules.new(BoardState.new(CONFIG.dimensions.x, CONFIG.dimensions.y), 5), CONFIG.seed)

func _prepare_line() -> void:
	for coordinate: Vector2i in CONFIG.line:
		run.state.rules.place_piece(coordinate, CONFIG.line_color)
	run.state.rules.place_piece(CONFIG.source, CONFIG.line_color)
	run.state.rules.place_piece(CONFIG.spare, 0)

func _reject(reason: String) -> CommandResult:
	var result: CommandResult = CommandResult.new()
	result.reason = reason
	return result
