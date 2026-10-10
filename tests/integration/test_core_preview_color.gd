extends GutTest

const GAME: PackedScene = preload("res://gameplay/game.tscn")
const CORE: SkillDefinition = preload("res://gameplay/progression/content/core_drop.tres")
const CARD: PackedScene = preload("res://ui/skill_card.tscn")

func test_skill_core_freezes_weighted_color_and_displays_it_before_selection() -> void:
	for color: int in range(5):
		var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
		run.state.spawning.color_weights = [0, 0, 0, 0, 0]
		run.state.spawning.color_weights[color] = 20
		run.prepare_spawn_plan()
		var plan: String = RunSnapshot.canonical(run.state.spawning.plan_data())
		var content_random: int = run.state.spawning.content_random.state
		run.state.pending_rewards = 1
		run.enter_rewards()
		var generator: SkillOfferGenerator = SkillOfferGenerator.new()
		var offer: SkillOffer = generator.generate(run)
		var target: SkillTarget = offer.targets[&"core_drop"]
		var card: SkillCard = CARD.instantiate() as SkillCard
		add_child_autofree(card)
		card.configure(CORE, target)
		assert_string_contains(card.preview_label.text, PieceTooltip.COLOR_NAMES[color])
		assert_eq(target.color, color, "首枚按棋子池权重锁定颜色")
		var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
		for repeat: int in range(3):
			assert_same(generator.generate(run), offer)
			assert_string_contains(SkillChoiceText.compact_preview(CORE, target), PieceTooltip.COLOR_NAMES[color])
		assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)
		# 卡片已显示的颜色不能因随后调整权重而重抽。
		run.state.spawning.color_weights = [20, 20, 20, 20, 20]
		var result: SkillApplyResult = SkillRules.apply(run, offer.offer_id, &"core_drop")
		assert_true(result.success)
		assert_eq(result.created[0].match_color, color)
		assert_eq(run.state.spawning.content_random.state, content_random)
		assert_eq(RunSnapshot.canonical(run.state.spawning.plan_data()), plan)

func test_real_board_spawn_animation_and_rebuild_preserve_all_preview_colors() -> void:
	var game: Node2D = GAME.instantiate() as Node2D
	game.set("persist_preferences", false)
	game.set("record_runs", false)
	game.set("collect_telemetry", false)
	add_child_autofree(game)
	var board: Board = game.get_node("Board") as Board
	await board.initialized
	get_tree().paused = false
	board.view.configure(9, 9, Vector2(64, 64), Vector2.ONE)
	for color: int in range(5):
		var selected: RunController = null
		for seed_value: int in range(500):
			var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), seed_value)
			run.state.spawning.color_weights = [0, 0, 0, 0, 0]
			run.state.spawning.color_weights[color] = 20
			run.state.explosion.core_pool_unlocked = true
			run.prepare_spawn_plan()
			if run.state.spawning.preview(1)[0].core_candidate:
				selected = run
				break
		assert_not_null(selected)
		if selected == null: return
		board.run = selected
		board.rules = selected.state.rules
		board.view.rebuild([])
		var preview: SpawnToken = selected.state.spawning.preview(1)[0]
		var birth: SpawnResult = selected.spawn_one()
		assert_eq(birth.piece.match_color, preview.color)
		await board.present_spawns([birth])
		_assert_visible_core(board.view.get_piece(birth.piece.piece_id), color)
		board.view.rebuild(board.rules.state.get_snapshot())
		board.refresh_ability_markers()
		_assert_visible_core(board.view.get_piece(birth.piece.piece_id), color)
		var summoned: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
		summoned.state.spawning.color_weights = [0, 0, 0, 0, 0]
		summoned.state.spawning.color_weights[color] = 20
		summoned.state.pending_rewards = 1
		summoned.enter_rewards()
		var offer: SkillOffer = SkillOfferGenerator.new().generate(summoned)
		var result: SkillApplyResult = SkillRules.apply(summoned, offer.offer_id, &"core_drop")
		assert_true(result.success)
		board.run = summoned
		board.rules = summoned.state.rules
		board.view.rebuild([])
		board.present_skill_result(result)
		assert_true(await board.finish_presentation())
		_assert_visible_core(board.view.get_piece(result.created[0].piece_id), color)
	# 等待导演信号退出后再交给 GUT 清理场景。
	await wait_process_frames(2)

func test_invalid_frozen_core_color_rejects_without_consuming_choice() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	run.state.pending_rewards = 1
	run.enter_rewards()
	var offer: SkillOffer = SkillOfferGenerator.new().generate(run)
	for color: int in [-1, 5]:
		offer.targets[&"core_drop"].color = color
		var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
		assert_false(SkillRules.apply(run, offer.offer_id, &"core_drop").success)
		assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)

func test_core_budget_preflight_uses_frozen_blue_color() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	for x: int in range(4): run.state.rules.place_piece(Vector2i(x, 0), 2)
	run.state.pending_rewards = 1
	run.enter_rewards()
	var offer: SkillOffer = SkillOfferGenerator.new().generate(run)
	offer.targets[&"core_drop"].coordinate = Vector2i(4, 0)
	offer.targets[&"core_drop"].color = 2
	var config: ExplosionConfig = run.abilities.config.duplicate() as ExplosionConfig
	config.event_budget = 1
	run.abilities = AbilityResolver.new(run.state, config)
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	assert_false(SkillRules.apply(run, offer.offer_id, &"core_drop").success)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)

func _assert_visible_core(piece: ChessPiece, color: int) -> void:
	assert_not_null(piece)
	assert_eq(piece.piece_type, color)
	assert_true(piece.polygon.visible, "验证实际可见图形，不能只核对规则数据")
	assert_false(piece.sprite.visible)
	assert_eq(piece.polygon.color, ChessPiece.color_for(color))
	assert_true(piece.ability_marker.visible)
	assert_string_contains(piece.tooltip_region.tooltip_text, PieceTooltip.COLOR_NAMES[color])

func test_normal_commands_replay_non_green_skill_core() -> void:
	var seen: bool = false
	for seed_value: int in range(8):
		var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), seed_value)
		run.initialize()
		run.recorder = RunRecorder.new()
		run.recorder.begin(run, "test", false)
		var bot: GreedyBot = GreedyBot.new(seed_value)
		for step: int in range(120):
			if run.state.is_game_over or not run.state.rule_error.is_empty(): break
			if run.state.phase in [RunState.Phase.INPUT, RunState.Phase.REWARDS] and not (run.state.phase == RunState.Phase.REWARDS and run.state.rewards.active_offer == null):
				var command: RunCommand = bot.choose(run)
				var offer: SkillOffer = run.state.rewards.active_offer
				if offer != null and offer.targets.has(&"core_drop"):
					var choice: ChooseSkillCommand = ChooseSkillCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
					choice.offer_id = offer.offer_id
					choice.reward_id = offer.reward_id
					choice.skill_id = &"core_drop"
					command = choice
				if command == null: break
				assert_true(run.execute_command(command).accepted)
				if command is ChooseSkillCommand and (command as ChooseSkillCommand).skill_id == &"core_drop":
					seen = run.state.rewards.applications.back().created[0].match_color != 1
					break
			else:
				run.advance()
		if not seen: continue
		run.recorder.finish(run, "abandoned", "test_complete")
		var replay: RuleReplay = RuleReplay.new()
		assert_true(replay.replay(run.recorder.records), replay.error)
		assert_eq(replay.checked_records, run.recorder.records.size())
		break
	assert_true(seen, "普通开局通过真实选卡命令产生非绿色首枚，并精确回放")
