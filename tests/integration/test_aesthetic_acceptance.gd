extends GutTest

const HOST: PackedScene = preload("res://tools/aesthetic_acceptance/aesthetic_acceptance.tscn")
var host: Node
var old_locale: String
var old_size: Vector2i
var old_scale: Vector2i
var seen_causes: Array[StringName] = []

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	old_locale = TranslationServer.get_locale()
	old_size = get_window().size
	old_scale = get_window().content_scale_size
	host = HOST.instantiate()
	add_child_autofree(host)
	await wait_until(func() -> bool: return host.board != null and not host.loading, 5.0)

func after_each() -> void:
	UIManager.close_popup()
	get_tree().paused = false
	host.queue_free()
	await wait_process_frames(4)
	TranslationServer.set_locale(old_locale)
	get_window().size = old_size
	get_window().content_scale_size = old_scale

func _observe(step: PresentationStep, _epoch: int, _token: int) -> void:
	for result: MatchResult in step.matches: seen_causes.append(result.cause)

func test_actual_closed_loops_preserve_rules_across_normal_and_low_effects() -> void:
	for key: String in ["match", "blast_row", "row_blast"]:
		var baseline: String = ""
		for low: bool in [false, true]:
			host.low = low
			await host.load_case(key)
			seen_causes.clear()
			var board: Board = host.board as Board
			board.director.step_requested.connect(_observe)
			await host.play_case()
			assert_eq(board.run.state.rule_error, "", key)
			assert_eq(board.director.error, "", key)
			assert_true(board.can_selected, key + " input restored")
			assert_gt(board.run.state.ledger.total, 0, key + " real score")
			assert_eq(board.view._pieces.size(), board.rules.state.get_piece_count())
			if key == "match": assert_true(seen_causes.has(&"match"))
			if key != "match":
				assert_true(seen_causes.has(&"explosion"), str(seen_causes))
				assert_true(seen_causes.has(&"line_clear"), str(seen_causes))
				if key == "blast_row": assert_lt(seen_causes.find(&"explosion"), seen_causes.find(&"line_clear"))
				else: assert_lt(seen_causes.find(&"line_clear"), seen_causes.find(&"explosion"))
			var digest: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
			if not low: baseline = digest
			else: assert_eq(digest, baseline, key + " presentation cannot alter rules/RNG")

func test_real_reward_popup_unlocks_l_and_restores_input() -> void:
	for low: bool in [false, true]:
		host.low = low
		await host.load_case("shape")
		await host.play_case()
		assert_true(await wait_until(func() -> bool: return UIManager.current_popup is PopupSkillChoice, 4.0))
		var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
		await wait_process_frames(8)
		popup._select(0)
		popup.confirm_selection()
		var board: Board = host.board as Board
		assert_true(await wait_until(func() -> bool: return board.can_selected, 6.0))
		assert_eq(board.run.state.rule_error, "")
		assert_true(board.run.state.rules.shape_unlocks.contains(&"l"))
		assert_eq(board.run.state.ledger.total, 50)
		assert_eq(board.view._pieces.size(), board.rules.state.get_piece_count())

func test_three_real_card_types_fit_and_can_be_chosen_bilingually() -> void:
	for locale: String in ["zh_CN", "en_US"]:
		TranslationServer.set_locale(locale)
		get_window().size = Vector2i(1024, 640)
		get_window().content_scale_size = Vector2i(1024, 640)
		for selected: int in range(3):
			host.low = true
			await host.load_case("cards")
			var board: Board = host.board as Board
			var before: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
			await host.play_case()
			assert_true(await wait_until(func() -> bool: return UIManager.current_popup is PopupSkillChoice, 4.0))
			var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
			await wait_process_frames(5)
			assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), before, "display is read only")
			var panel: Control = popup.get_node("Center/Panel") as Control
			assert_true(get_viewport().get_visible_rect().grow(1).encloses(panel.get_global_rect()), locale)
			for index: int in range(3):
				var card: SkillCard = popup.options.get_child(index) as SkillCard
				assert_true(card.get_global_rect().encloses(card.action_label.get_global_rect()), "%s card %s action %s %s" % [locale, card.get_global_rect(), card.action_label.get_global_rect(), card.action_label.text])
				assert_gte(card.effect_label.size.y, card.effect_label.get_minimum_size().y)
				assert_true(card.flavor_label.visible)
				assert_true(card.get_global_rect().encloses(card.flavor_label.get_global_rect()))
				assert_eq(AestheticCases.CARDS[index].flavor_text, "", "sample must not modify shipped definition")
				assert_eq(card.effect_label.get_parsed_text(), SkillChoiceText.summary(AestheticCases.CARDS[index]))
			var upgrade: SkillCard = popup.options.get_child(0) as SkillCard
			assert_true(upgrade.level_label.visible)
			assert_string_contains(upgrade.level_label.text, "2")
			var finite: SkillCard = popup.options.get_child(1) as SkillCard
			assert_true(finite.consume_label.visible)
			if locale == "en_US":
				var composite_card: SkillCard = popup.options.get_child(2) as SkillCard
				assert_string_contains(composite_card.preview_label.text, "Clear a chosen color")
				assert_string_contains(composite_card.flavor_label.text, "Tidy up")
			popup._select(selected)
			if selected == 2: popup.picker.select_color(0)
			popup.confirm_selection()
			assert_true(await wait_until(func() -> bool: return board.can_selected, 8.0), "%s %d: %s" % [locale, selected, popup.message.text if is_instance_valid(popup) else "closed"])
			assert_eq(board.run.state.rule_error, "", locale)
			assert_gt(board.run.state.rewards.acquired.get(AestheticCases.CARDS[selected].skill_id, 0), 0)

func test_flash_reaches_visible_nut_and_is_isolated_from_other_instances_and_template() -> void:
	var board: Board = host.board as Board
	var pieces: Array[PieceState] = board.rules.state.get_snapshot()
	var a: ChessPiece = board.view.get_piece(pieces[0].piece_id)
	var b: ChessPiece = board.view.get_piece(pieces[1].piece_id)
	var template: PackedScene = load("res://gameplay/board/piece/nut_visual.tscn") as PackedScene
	var c: NutVisual = template.instantiate() as NutVisual
	add_child_autofree(c)
	a._set_flash(0.75)
	assert_true(a.nut_visual.visible)
	assert_eq((a.nut_visual.material as ShaderMaterial).get_shader_parameter("flash_amount"), 0.75)
	assert_eq((b.nut_visual.material as ShaderMaterial).get_shader_parameter("flash_amount"), 0.0)
	assert_eq((c.material as ShaderMaterial).get_shader_parameter("flash_amount"), 0.0)
	a.reset()
	assert_eq((a.nut_visual.material as ShaderMaterial).get_shader_parameter("flash_amount"), 0.0)

func test_empty_build_hint_uses_full_width_then_returns_to_three_columns() -> void:
	var list: Control = host.game.get_node("UILayer/HUD").build_list as Control
	await wait_process_frames(4)
	assert_eq(list.cards.columns, 1)
	assert_gt(list.empty_label.size.x, 150.0, "empty hint must not wrap into a narrow grid cell")
	await host.load_case("cards")
	list = host.game.get_node("UILayer/HUD").build_list as Control
	await wait_process_frames(4)
	assert_eq(list.cards.columns, 3)
	assert_false(list.empty_label.visible)

func test_legacy_v43_replay_and_flavor_do_not_change_rule_configuration() -> void:
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay_file("res://tests/fixtures/issue128_legacy_v43.jsonl"), replay.error)
	assert_true(replay.complete)
	var run: RunController = AestheticCases.create("cards")
	var before: String = RunSnapshot.digest(RunSnapshot.config(run))
	for fields: Dictionary in RunSnapshot.config(run).skills:
		assert_false(fields.has("flavor_text"))
		assert_false(fields.has("short_description"))
	for skill: SkillDefinition in run.state.rewards.active_offer.choices:
		skill.flavor_text = "another display-only sentence"
	assert_eq(RunSnapshot.digest(RunSnapshot.config(run)), before)

func test_legacy_debug_keys_cannot_escape_acceptance_fixture() -> void:
	var run: RunController = host.board.run as RunController
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	for code: Key in [KEY_F6, KEY_F7, KEY_F10, KEY_F11, KEY_F12]:
		var event: InputEventKey = InputEventKey.new()
		event.pressed = true
		event.physical_keycode = code
		host.game._unhandled_key_input(event)
		await wait_process_frames(2)
		assert_same(host.board.run, run)
		assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)

func test_pause_locale_and_menu_restore_keep_icon_header_at_small_viewport() -> void:
	get_window().size = Vector2i(1024, 640)
	get_window().content_scale_size = Vector2i(1024, 640)
	var game: Node2D = host.game as Node2D
	var hud: Hud = game.get_node("UILayer/HUD") as Hud
	for locale: String in ["zh_CN", "en_US"]:
		TranslationServer.set_locale(locale)
		game.call("_on_locale_changed", "", locale)
		for paused: bool in [true, false]:
			game.call("_toggle_pause")
			await wait_process_frames(4)
			assert_eq(get_tree().paused, paused)
			assert_eq(hud.pause_button.text, "")
			assert_eq(hud.pause_button.tooltip_text, tr("继续 / ESC") if paused else tr("暂停 / ESC"))
			assert_lte(hud.pause_button.size.x, 44.0)
			assert_true(get_viewport().get_visible_rect().encloses(hud.pause_button.get_global_rect()))
		game.call("_play_from_menu", false)
		assert_eq(hud.pause_button.text, "")
