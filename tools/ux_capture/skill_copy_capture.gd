extends Node

## 固定候选与棋盘；只截图，不写试玩记录或偏好。
const GAME: PackedScene = preload("res://gameplay/game.tscn")
const POPUP: PackedScene = preload("res://ui/popup_skill_choice.tscn")
var game: Node2D
var popup: Control

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	game = GAME.instantiate() as Node2D
	game.set("show_start_menu", false)
	game.set("persist_preferences", false)
	game.set("record_runs", false)
	game.set("collect_telemetry", false)
	add_child(game)
	var board: Board = game.get_node("Board") as Board
	await board.initialized
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 864, preload("res://gameplay/progression/stages/stage_config.tres"))
	run.initialize("fixture_dye")
	board.run = run
	board.rules = run.state.rules
	GameManager.reset_game(run)
	board.rebuild_view()
	game.call("_refresh_hud")
	game.call("_set_volume", 0.0, false)
	var label: String = "after"
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--before": label = "before"
	var popup_scene: PackedScene = POPUP
	if label == "before": popup_scene = load("res://production/skill_copy/baseline/popup_skill_choice.tscn") as PackedScene
	popup = popup_scene.instantiate() as Control
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 150
	add_child(layer)
	layer.add_child(popup)
	var output: String = "res://production/skill_copy/" + label
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	for locale: String in ["zh_CN", "en_US"]:
		TranslationServer.set_locale(locale)
		for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(1024, 640)]:
			get_window().size = resolution
			for group: int in range(2):
				var ids: Array[StringName] = [&"core_manual_detonation", &"refill_less", &"blast_chain_bonus"]
				if group == 1: ids = [&"match_dye_echo", &"instant_color_clear", &"blast_aftershock"]
				var offer: SkillOffer = _offer(board.run, ids)
				if popup is PopupSkillChoice:
					(popup as PopupSkillChoice).show_offer(offer)
				else:
					(popup.get_node("Center/Panel/Column/Heading") as Label).text = tr("目标达成 · 第%d次选择") % offer.reward_id
					(popup.get_node("Center/Panel/Column/Message") as Label).text = tr("选择一项技能，继续你的构筑")
					for index: int in range(offer.choices.size()):
						var card: Button = popup.get_node("Center/Panel/Column/Options").get_child(index) as Button
						card.call("configure", offer.choices[index], offer.targets[offer.choices[index].skill_id])
				await _frames(10)
				await get_tree().create_timer(0.35).timeout
				await _capture(output.path_join("cards_%s_%d_%d.png" % [locale, resolution.x, group]))
				if label == "after" and locale == "zh_CN" and resolution.x == 1280 and group == 0:
					var refill_card: SkillCard = (popup as PopupSkillChoice).options.get_child(1) as SkillCard
					await _hover(refill_card.consume_label.get_global_rect().get_center())
					await _capture(output.path_join("consume_hint.png"))
					await _hover(Vector2(1.0, 1.0))
	print("SKILL_COPY_CAPTURE_COMPLETE ", label, " CONFIG ", RunSnapshot.digest(RunSnapshot.config(board.run)))
	get_tree().quit()

func _offer(run: RunController, ids: Array[StringName]) -> SkillOffer:
	var offer: SkillOffer = SkillOffer.new()
	offer.reward_id = 3
	for id: StringName in ids:
		for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
			if skill.skill_id != id: continue
			offer.choices.append(skill)
			var target: SkillTarget = skill.choice_effect.freeze(SkillRules.effect_context(run.state), run.state.rewards.target_random) if skill.choice_effect != null else SkillTarget.new()
			target.level_after = 1
			offer.targets[id] = target
	return offer

func _frames(count: int) -> void:
	for frame: int in range(count): await get_tree().process_frame

func _hover(point: Vector2) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion, true)
	await get_tree().create_timer(0.85).timeout

func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var screenshot: Image = get_viewport().get_texture().get_image()
	var error: Error = screenshot.save_png(path)
	if error != OK: push_error(error_string(error))
