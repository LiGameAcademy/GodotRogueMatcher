extends GutTest

const CARD: PackedScene = preload("res://ui/skill_card.tscn")
const BUILD: PackedScene = preload("res://ui/build_card/build_card.tscn")
const BUILD_SCRIPT: Script = preload("res://ui/build_card/build_card.gd")
var old_locale: String

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	old_locale = TranslationServer.get_locale()

func after_each() -> void:
	TranslationServer.set_locale(old_locale)
	await wait_process_frames(2)

func test_registered_icons_match_choices_catalog_and_compact_build_without_mutating_run() -> void:
	var run: RunController = AestheticCases.create("cards")
	var config: String = RunSnapshot.digest(RunSnapshot.config(run))
	for locale: String in ["zh_CN", "en_US"]:
		TranslationServer.set_locale(locale)
		for preset: GameTheme in GameThemes.ALL:
			for id: StringName in SkillMechanicIcons.TEXTURES:
				var skill: SkillDefinition = load("res://gameplay/progression/content/%s.tres" % id) as SkillDefinition
				var card: SkillCard = CARD.instantiate() as SkillCard
				var build: BUILD_SCRIPT = BUILD.instantiate() as BUILD_SCRIPT
				add_child(card)
				add_child(build)
				var frozen: SkillTarget = SkillRules.freeze_target(run.state, skill)
				var displayed: String = RunSnapshot.digest(RunSnapshot.capture(run))
				card.configure(skill, frozen)
				build.configure(skill, 1, 2)
				GameThemeUi.apply(card, preset)
				GameThemeUi.apply(build, preset)
				await wait_process_frames(3)
				assert_true(card.mechanic_icon.visible)
				assert_true(build.mechanic_icon.visible)
				assert_false(build.symbol.visible)
				assert_same(card.mechanic_icon.texture, build.mechanic_icon.texture)
				assert_eq(card.mechanic_icon.rotation_degrees, SkillMechanicIcons.rotation_for(id))
				assert_eq(build.mechanic_icon.rotation_degrees, card.mechanic_icon.rotation_degrees)
				assert_true(build.mechanic_role.visible)
				assert_eq(build.mechanic_role.text, SkillMechanicIcons.role_for(id))
				assert_string_contains(build.tooltip_text, tr(skill.title))
				assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), displayed)
				card.configure_catalog(skill, run)
				await wait_process_frames(3)
				assert_eq(card.mechanic_icon.rotation_degrees, SkillMechanicIcons.rotation_for(id))
				assert_same(card.mechanic_icon.texture, build.mechanic_icon.texture)
				assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), displayed)
				card.queue_free()
				build.queue_free()
				await wait_process_frames(1)
	assert_eq(RunSnapshot.digest(RunSnapshot.config(run)), config)

func test_unregistered_and_same_tag_cards_keep_fallback_and_reused_nodes_clear_previous_icons() -> void:
	var card: SkillCard = CARD.instantiate() as SkillCard
	var build: BUILD_SCRIPT = BUILD.instantiate() as BUILD_SCRIPT
	add_child_autofree(card)
	add_child_autofree(build)
	var column: SkillDefinition = load("res://gameplay/progression/content/line_column_drop.tres") as SkillDefinition
	var core: SkillDefinition = load("res://gameplay/progression/content/core_drop.tres") as SkillDefinition
	var unknown: SkillDefinition = core.duplicate() as SkillDefinition
	unknown.skill_id = &"unregistered_same_tags"
	for skill: SkillDefinition in [column, core, unknown]:
		card.configure(skill, SkillTarget.new())
		build.configure(skill, 1, 0)
		if skill == unknown:
			assert_null(card.mechanic_icon.texture)
			assert_false(card.mechanic_icon.visible)
			assert_false(build.mechanic_icon.visible)
			assert_true(build.symbol.visible)
			assert_false(build.symbol.text.is_empty())
			assert_false(build.mechanic_role.visible)
		else:
			assert_true(build.mechanic_icon.visible)
			assert_eq(card.mechanic_icon.rotation_degrees, 90.0 if skill == column else 0.0)
	assert_eq(core.skill_id, &"core_drop")

func test_orientation_and_modulation_are_instance_local_and_do_not_intercept_input() -> void:
	var a: SkillCard = CARD.instantiate() as SkillCard
	var b: SkillCard = CARD.instantiate() as SkillCard
	add_child_autofree(a)
	add_child_autofree(b)
	var row: SkillDefinition = load("res://gameplay/progression/content/line_row_drop.tres") as SkillDefinition
	var column: SkillDefinition = load("res://gameplay/progression/content/line_column_drop.tres") as SkillDefinition
	a.configure(row, SkillTarget.new())
	b.configure(column, SkillTarget.new())
	await wait_process_frames(3)
	assert_same(a.mechanic_icon.texture, b.mechanic_icon.texture)
	a.mechanic_icon.modulate = Color.RED
	assert_eq(b.mechanic_icon.modulate, Color.WHITE)
	assert_eq(b.mechanic_icon.rotation_degrees, 90.0)
	assert_eq(a.mechanic_icon.rotation_degrees, 0.0)
	assert_eq(a.mechanic_icon.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(b.mechanic_icon.mouse_filter, Control.MOUSE_FILTER_IGNORE)

func test_refill_icons_keep_real_remaining_uses_and_multiplier_keeps_level() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 129)
	run.initialize()
	run.state.rewards.consumed_count = 3
	for id: StringName in [&"refill_less", &"refill_more", &"score_multiplier"]:
		AestheticCases.install(run, load("res://gameplay/progression/content/%s.tres" % id) as SkillDefinition)
	assert_eq(run.state.rule_error, "")
	var hud: Hud = (load("res://ui/hud.tscn") as PackedScene).instantiate() as Hud
	add_child_autofree(hud)
	for remaining: int in [3, 2, 1, 0]:
		var snapshot: String = RunSnapshot.digest(RunSnapshot.capture(run))
		for locale: String in ["zh_CN", "en_US"]:
			TranslationServer.set_locale(locale)
			hud.show_run(run)
			await wait_process_frames(3)
			for id: StringName in [&"refill_less", &"refill_more"]:
				assert_eq(hud.build_list._cards.has(id), remaining > 0)
				if remaining == 0: continue
				var card: BUILD_SCRIPT = hud.build_list._cards[id] as BUILD_SCRIPT
				assert_same(card.mechanic_icon.texture, SkillMechanicIcons.texture_for(id))
				assert_false(card.level_label.visible)
				assert_string_contains(card.badge.text, str(remaining))
				assert_string_contains(card.remaining_label.text, str(remaining))
				assert_true(card.get_global_rect().encloses(card.mechanic_role.get_global_rect()))
			var multiplier: BUILD_SCRIPT = hud.build_list._cards[&"score_multiplier"] as BUILD_SCRIPT
			assert_same(multiplier.mechanic_icon.texture, SkillMechanicIcons.MULTIPLIER)
			assert_eq(multiplier.badge.text, "Lv.1")
			assert_false(multiplier.remaining_label.visible)
			assert_true(multiplier.get_global_rect().encloses(multiplier.mechanic_role.get_global_rect()))
			assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), snapshot)
		if remaining > 0: run.state.spawning.consume_refill_count(RunController.SPAWN_CONFIG)
	assert_not_same(SkillMechanicIcons.REFILL_LESS, SkillMechanicIcons.REFILL_MORE)

func test_dye_build_uses_one_shared_glyph_but_distinct_roles_and_real_levels() -> void:
	var ids: Array[StringName] = [&"match_dye_echo", &"dye_target_up", &"dye_chain_depth"]
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 129)
	run.initialize()
	for id: StringName in ids:
		var skill: SkillDefinition = load("res://gameplay/progression/content/%s.tres" % id) as SkillDefinition
		AestheticCases.install(run, skill)
	assert_eq(run.state.rule_error, "")
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	var hud: Hud = (load("res://ui/hud.tscn") as PackedScene).instantiate() as Hud
	add_child_autofree(hud)
	for locale: String in ["zh_CN", "en_US"]:
		TranslationServer.set_locale(locale)
		hud.show_run(run)
		await wait_process_frames(3)
		var roles: Array[String] = []
		for id: StringName in ids:
			var card: BUILD_SCRIPT = hud.build_list._cards[id] as BUILD_SCRIPT
			assert_same(card.mechanic_icon.texture, SkillMechanicIcons.DYE)
			assert_eq(card.badge.text, "Lv.1")
			assert_false(card.remaining_label.visible)
			assert_false(roles.has(card.mechanic_role.text))
			roles.append(card.mechanic_role.text)
			assert_true(card.get_global_rect().encloses(card.mechanic_role.get_global_rect()))
		assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)
	var instant: SkillDefinition = load("res://gameplay/progression/content/instant_color_dye.tres") as SkillDefinition
	assert_null(SkillMechanicIcons.texture_for(instant.skill_id))
	assert_eq(SkillMechanicIcons.role_for(instant.skill_id), "")

func test_fuse_roles_and_relay_level_two_preserve_rules_and_other_fuse_cards_keep_fallback() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 129)
	run.initialize()
	for id: StringName in [&"core_drop", &"assign_fuse", &"fuse_match_plant", &"fuse_relay", &"relay_capacity", &"relay_capacity"]:
		AestheticCases.install(run, load("res://gameplay/progression/content/%s.tres" % id) as SkillDefinition)
	assert_eq(run.state.rule_error, "")
	assert_false(SkillRules.effect_context(run.state).fuse_ids.is_empty())
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	var hud: Hud = (load("res://ui/hud.tscn") as PackedScene).instantiate() as Hud
	add_child_autofree(hud)
	for locale: String in ["zh_CN", "en_US"]:
		TranslationServer.set_locale(locale)
		hud.show_run(run)
		await wait_process_frames(3)
		var roles: Array[String] = []
		for id: StringName in [&"fuse_match_plant", &"fuse_relay", &"relay_capacity"]:
			var card: BUILD_SCRIPT = hud.build_list._cards[id] as BUILD_SCRIPT
			assert_same(card.mechanic_icon.texture, SkillMechanicIcons.FUSE)
			assert_eq(card.badge.text, "Lv.2" if id == &"relay_capacity" else "Lv.1")
			assert_false(card.remaining_label.visible)
			assert_false(roles.has(card.mechanic_role.text))
			roles.append(card.mechanic_role.text)
			assert_true(card.get_global_rect().encloses(card.mechanic_role.get_global_rect()))
		assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)
	for id: StringName in [&"instant_fuse_ignite", &"marked_reward", &"chain_reward"]:
		assert_null(SkillMechanicIcons.texture_for(id))
		assert_eq(SkillMechanicIcons.role_for(id), "")

func test_match_bonus_roles_keep_conditions_levels_and_multiplier_separate_without_awarding_score() -> void:
	var ids: Array[StringName] = [&"match_extra", &"precision_reward", &"longline_reward"]
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 129)
	run.initialize()
	for id: StringName in [&"match_extra", &"precision_reward", &"precision_reward", &"longline_reward", &"longline_reward", &"longline_reward", &"score_multiplier"]:
		AestheticCases.install(run, load("res://gameplay/progression/content/%s.tres" % id) as SkillDefinition)
	assert_eq(run.state.rule_error, "")
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	var hud: Hud = (load("res://ui/hud.tscn") as PackedScene).instantiate() as Hud
	add_child_autofree(hud)
	for locale: String in ["zh_CN", "en_US"]:
		TranslationServer.set_locale(locale)
		hud.show_run(run)
		await wait_process_frames(3)
		var roles: Array[String] = []
		for index: int in range(ids.size()):
			var card: BUILD_SCRIPT = hud.build_list._cards[ids[index]] as BUILD_SCRIPT
			assert_same(card.mechanic_icon.texture, SkillMechanicIcons.MATCH_BONUS)
			assert_eq(card.badge.text, "Lv.%d" % (index + 1))
			assert_false(card.remaining_label.visible)
			assert_false(roles.has(card.mechanic_role.text))
			roles.append(card.mechanic_role.text)
			assert_true(card.get_global_rect().encloses(card.mechanic_role.get_global_rect()))
			if index == 1:
				assert_string_contains(card.tooltip_text, "恰好消除5枚" if locale == "zh_CN" else "exactly 5")
				assert_string_contains(card.tooltip_text, "不受倍率影响" if locale == "zh_CN" else "unaffected by multipliers")
			elif index == 2:
				assert_string_contains(card.tooltip_text, "≥6" if locale == "zh_CN" else "6+")
				assert_string_contains(card.tooltip_text, "不吃倍率" if locale == "zh_CN" else "not multiplied")
		var multiplier: BUILD_SCRIPT = hud.build_list._cards[&"score_multiplier"] as BUILD_SCRIPT
		assert_same(multiplier.mechanic_icon.texture, SkillMechanicIcons.MULTIPLIER)
		assert_not_same(multiplier.mechanic_icon.texture, SkillMechanicIcons.MATCH_BONUS)
		assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)
	for id: StringName in [&"goal_score_bonus", &"blast_reward", &"color_weight_up"]:
		assert_null(SkillMechanicIcons.texture_for(id))

func test_blast_payoffs_keep_hit_generation_and_threshold_conditions_without_starting_refill_uses() -> void:
	var ids: Array[StringName] = [&"blast_extra", &"blast_chain_bonus", &"blast_refill_relief"]
	var levels: Array[int] = [2, 3, 1]
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 129)
	run.initialize()
	for id: StringName in [&"core_drop", &"assign_fuse", &"blast_extra", &"blast_extra", &"blast_chain_bonus", &"blast_chain_bonus", &"blast_chain_bonus", &"blast_refill_relief", &"match_extra"]:
		AestheticCases.install(run, load("res://gameplay/progression/content/%s.tres" % id) as SkillDefinition)
	assert_eq(run.state.rule_error, "")
	assert_eq(run.state.spawning.refill_batches[-1], 0)
	assert_eq(run.state.spawning.refill_batches[1], 0)
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	var hud: Hud = (load("res://ui/hud.tscn") as PackedScene).instantiate() as Hud
	add_child_autofree(hud)
	for locale: String in ["zh_CN", "en_US"]:
		TranslationServer.set_locale(locale)
		hud.show_run(run)
		await wait_process_frames(3)
		var roles: Array[String] = []
		for index: int in range(ids.size()):
			var card: BUILD_SCRIPT = hud.build_list._cards[ids[index]] as BUILD_SCRIPT
			assert_same(card.mechanic_icon.texture, SkillMechanicIcons.EXPLOSION)
			assert_eq(card.badge.text, "Lv.%d" % levels[index])
			assert_false(card.remaining_label.visible)
			assert_false(roles.has(card.mechanic_role.text))
			roles.append(card.mechanic_role.text)
			assert_true(card.get_global_rect().encloses(card.mechanic_role.get_global_rect()))
			if index == 0:
				assert_string_contains(card.tooltip_text, "命中爆炸" if locale == "zh_CN" else "blast that hits a piece")
			elif index == 1:
				assert_string_contains(card.tooltip_text, "第2/3/≥4代" if locale == "zh_CN" else "2 / 3 / 4+")
			else:
				assert_string_contains(card.tooltip_text, "≥8" if locale == "zh_CN" else "8+ pieces")
				assert_string_contains(card.tooltip_text, "不叠加减量" if locale == "zh_CN" else "not a larger reduction")
		var match_bonus: BUILD_SCRIPT = hud.build_list._cards[&"match_extra"] as BUILD_SCRIPT
		assert_same(match_bonus.mechanic_icon.texture, SkillMechanicIcons.MATCH_BONUS)
		assert_not_same(match_bonus.mechanic_icon.texture, SkillMechanicIcons.EXPLOSION)
		assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)
	assert_eq(run.state.spawning.refill_batches[-1], 0)
	assert_eq(run.state.spawning.refill_batches[1], 0)
	for id: StringName in [&"blast_reward", &"selective_blast", &"blast_aftershock"]:
		assert_null(SkillMechanicIcons.texture_for(id))

func test_manual_icons_keep_real_shared_quota_at_zero_without_changing_run() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 129)
	run.initialize()
	var ids: Array[StringName] = [&"core_manual_detonation", &"line_manual_clear"]
	for id: StringName in [&"core_drop", &"line_row_drop", &"line_column_drop"] + ids:
		AestheticCases.install(run, load("res://gameplay/progression/content/%s.tres" % id) as SkillDefinition)
	assert_eq(run.state.rule_error, "")
	var hud: Hud = (load("res://ui/hud.tscn") as PackedScene).instantiate() as Hud
	add_child_autofree(hud)
	for used: int in [0, 3]:
		# Quota is run-owned, shared by both sweeper axes; rendering never consumes it.
		for id: StringName in ids: run.state.manual_uses_used[id] = used
		var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
		for locale: String in ["zh_CN", "en_US"]:
			TranslationServer.set_locale(locale)
			hud.show_run(run)
			await wait_process_frames(3)
			for id: StringName in ids:
				var card: BUILD_SCRIPT = hud.build_list._cards[id] as BUILD_SCRIPT
				assert_true(card.mechanic_icon.visible)
				assert_same(card.mechanic_icon.texture, SkillMechanicIcons.EXPLOSION if id == ids[0] else SkillMechanicIcons.MANUAL_SWEEP)
				assert_eq(card.mechanic_role.text, "主动" if locale == "zh_CN" else "Manual")
				assert_eq(card.badge.text, "Lv.1 · %d" % (3 - used))
				assert_string_contains(card.remaining_label.text, "%d / 3" % (3 - used))
				assert_true(card.get_global_rect().encloses(card.mechanic_role.get_global_rect()))
			assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)
	assert_not_same(SkillMechanicIcons.MANUAL_SWEEP, SkillMechanicIcons.SWEEP)

func test_fuse_assignment_capacity_and_payload_keep_lifecycles_and_live_levels() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 129)
	run.initialize()
	for x: int in range(9):
		if run.state.rules.state.get_piece_id(Vector2i(x, 4)) == 0:
			run.state.rules.place_piece(Vector2i(x, 4), x % 5)
	for id: StringName in [&"core_drop", &"assign_fuse", &"fuse_capacity"]:
		AestheticCases.install(run, load("res://gameplay/progression/content/%s.tres" % id) as SkillDefinition)
	var ids: Array[StringName] = [&"assign_fuse", &"fuse_capacity", &"core_fuse_payload"]
	var skills: Array[SkillDefinition] = []
	for id: StringName in ids: skills.append(load("res://gameplay/progression/content/%s.tres" % id) as SkillDefinition)
	var offer: SkillOffer = AestheticCases.offer(run, skills)
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	var card: SkillCard = CARD.instantiate() as SkillCard
	add_child_autofree(card)
	for locale: String in ["zh_CN", "en_US"]:
		TranslationServer.set_locale(locale)
		for skill: SkillDefinition in skills:
			card.configure(skill, offer.targets[skill.skill_id])
			assert_same(card.mechanic_icon.texture, SkillMechanicIcons.FUSE)
			assert_eq(skill.is_persistent, skill.skill_id != &"assign_fuse")
			assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)
	# Finish the offered upgrade via the real acceptance path, then install payload.
	var result: SkillApplyResult = SkillRules.apply(run, offer.offer_id, &"fuse_capacity")
	assert_true(result.success, result.error)
	AestheticCases.install(run, skills[2])
	assert_eq(run.state.rule_error, "")
	var hud: Hud = (load("res://ui/hud.tscn") as PackedScene).instantiate() as Hud
	add_child_autofree(hud)
	before = RunSnapshot.digest(RunSnapshot.capture(run))
	for locale: String in ["zh_CN", "en_US"]:
		TranslationServer.set_locale(locale)
		hud.show_run(run)
		await wait_process_frames(3)
		assert_false(hud.build_list._cards.has(&"assign_fuse"))
		for id: StringName in [&"fuse_capacity", &"core_fuse_payload"]:
			var build: BUILD_SCRIPT = hud.build_list._cards[id] as BUILD_SCRIPT
			assert_same(build.mechanic_icon.texture, SkillMechanicIcons.FUSE)
			assert_eq(build.badge.text, "Lv.2" if id == &"fuse_capacity" else "Lv.1")
			assert_false(build.remaining_label.visible)
			assert_eq(build.mechanic_role.text, SkillMechanicIcons.role_for(id))
			assert_true(build.get_global_rect().encloses(build.mechanic_role.get_global_rect()))
			assert_string_contains(build.tooltip_text, "2 → 3 → 4" if id == &"fuse_capacity" else ("爆炸前" if locale == "zh_CN" else "Before the blast"))
		assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)

func test_instant_conversion_icons_keep_frozen_targets_colors_and_supply_locked() -> void:
	var ids: Array[StringName] = [&"instant_core_transform", &"instant_row_transform", &"instant_column_transform"]
	var contents: Array[StringName] = [&"special_demolition", LineClearState.CONTENT_ROW, LineClearState.CONTENT_COLUMN]
	for index: int in range(ids.size()):
		var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 129)
		run.initialize()
		run.state.rewards.consumed_count = 2
		for x: int in range(9):
			if run.state.rules.state.get_piece_id(Vector2i(x, 4)) == 0:
				run.state.rules.place_piece(Vector2i(x, 4), x % 5)
		var skill: SkillDefinition = load("res://gameplay/progression/content/%s.tres" % ids[index]) as SkillDefinition
		var offer: SkillOffer = AestheticCases.offer(run, [skill])
		var target: SkillTarget = offer.targets[skill.skill_id]
		assert_eq(target.piece_ids.size(), 3)
		var originals: Dictionary[int, PieceState] = {}
		for id: int in target.piece_ids: originals[id] = run.state.rules.state.get_piece(id).copy()
		var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
		var card: SkillCard = CARD.instantiate() as SkillCard
		add_child_autofree(card)
		for locale: String in ["zh_CN", "en_US"]:
			TranslationServer.set_locale(locale)
			card.configure(skill, target)
			await wait_process_frames(3)
			assert_same(card.mechanic_icon.texture, SkillMechanicIcons.EXPLOSION if index == 0 else SkillMechanicIcons.SWEEP)
			assert_eq(card.mechanic_icon.rotation_degrees, 90.0 if index == 2 else 0.0)
			assert_eq(SkillMechanicIcons.role_for(skill.skill_id), "改装" if locale == "zh_CN" else "Convert")
			assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)
		var result: SkillApplyResult = SkillRules.apply(run, offer.offer_id, skill.skill_id)
		assert_true(result.success, result.error)
		for id: int in originals:
			var piece: PieceState = run.state.rules.state.get_piece(id)
			assert_eq(piece.content_id, contents[index])
			assert_eq(piece.match_color, originals[id].match_color)
			assert_eq(piece.coordinate, originals[id].coordinate)
		assert_false(run.state.explosion.core_pool_unlocked)
		assert_false(run.state.line_clear.row_unlocked)
		assert_false(run.state.line_clear.column_unlocked)
		var hud: Hud = (load("res://ui/hud.tscn") as PackedScene).instantiate() as Hud
		add_child_autofree(hud)
		hud.show_run(run)
		assert_false(hud.build_list._cards.has(skill.skill_id))
