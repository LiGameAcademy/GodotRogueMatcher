extends GutTest

const CARD: PackedScene = preload("res://ui/skill_card.tscn")
const POPUP: PackedScene = preload("res://ui/popup_skill_choice.tscn")

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false

func after_each() -> void:
	get_tree().paused = false

func test_all_skill_descriptions_fit_card_and_popup_at_base_viewport() -> void:
	var popup: PopupSkillChoice = POPUP.instantiate() as PopupSkillChoice
	add_child_autofree(popup)
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), MatchSystem.MIN_MATCH_COUNT), 864)
	for x: int in range(9):
		for y: int in range(7): run.state.rules.place_piece(Vector2i(x, y), posmod(x + y, 5))
	for offset: int in range(0, SkillOfferGenerator.CATALOG.size(), 3):
		var offer: SkillOffer = SkillOffer.new()
		for index: int in range(offset, mini(offset + 3, SkillOfferGenerator.CATALOG.size())):
			var skill: SkillDefinition = SkillOfferGenerator.CATALOG[index]
			offer.choices.append(skill)
			var target: SkillTarget = skill.choice_effect.freeze(SkillRules.effect_context(run.state), run.state.rewards.target_random) if skill.choice_effect != null else SkillTarget.new()
			target.level_before = SkillRules.level(run.state, skill)
			target.level_after = target.level_before + 1
			offer.targets[skill.skill_id] = target
		popup.show_offer(offer)
		await wait_process_frames(3)
		var panel: Control = popup.get_node("Center/Panel") as Control
		assert_true(get_viewport().get_visible_rect().grow(1.0).encloses(panel.get_global_rect()), "三选一弹窗不得超出窗口")
		for index: int in range(offer.choices.size()):
			var card: SkillCard = popup.options.get_child(index) as SkillCard
			assert_true(card.get_global_rect().encloses(card.action_frame.get_global_rect()), "%s操作区域不得溢出卡片" % offer.choices[index].skill_id)
			assert_true(card.get_global_rect().encloses(card.rarity_frame.get_global_rect()), "%s顶部徽章不得溢出卡片" % offer.choices[index].skill_id)
			assert_gte(card.effect_label.size.y, float(card.effect_label.get_minimum_size().y), "%s完整效果说明可见" % offer.choices[index].skill_id)

func test_rarity_frames_are_instance_owned_and_template_stays_unchanged() -> void:
	var first: SkillCard = CARD.instantiate() as SkillCard
	var second: SkillCard = CARD.instantiate() as SkillCard
	add_child_autofree(first)
	add_child_autofree(second)
	var template: StyleBoxFlat = first.rarity_frame.get_theme_stylebox("panel") as StyleBoxFlat
	var original: Color = template.bg_color
	var target: SkillTarget = SkillTarget.new()
	first.configure(preload("res://gameplay/progression/content/blast_aftershock.tres"), target)
	second.configure(preload("res://gameplay/progression/content/core_manual_detonation.tres"), target)
	var first_style: StyleBoxFlat = first.rarity_frame.get_theme_stylebox("panel") as StyleBoxFlat
	var second_style: StyleBoxFlat = second.rarity_frame.get_theme_stylebox("panel") as StyleBoxFlat
	assert_ne(first_style, second_style)
	first_style.bg_color = Color.RED
	assert_ne(second_style.bg_color, Color.RED)
	assert_eq(template.bg_color, original)
