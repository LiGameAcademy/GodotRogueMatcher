extends GutTest

const HUD: PackedScene = preload("res://ui/hud.tscn")
const CARD_SCRIPT: Script = preload("res://ui/build_card/build_card.gd")
const CORE: SkillDefinition = preload("res://gameplay/progression/content/core_drop.tres")
const SUPPLY: SkillDefinition = preload("res://gameplay/progression/content/core_supply_up.tres")

func _apply(run: RunController, skill: SkillDefinition) -> void:
	run.state.pending_rewards = 1
	run.enter_rewards()
	var current: int = SkillRules.level(run.state, skill)
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = run.state.rewards.next_offer_id
	run.state.rewards.next_offer_id += 1
	offer.reward_id = run.state.rewards.consumed_count + 1
	offer.choices = [skill]
	var target: SkillTarget = skill.acquisition_effect(current).freeze(SkillRules.effect_context(run.state), run.state.rewards.target_random)
	target.level_before = current
	target.level_after = current + 1
	offer.targets[skill.skill_id] = target
	run.state.rewards.active_offer = offer
	assert_true(SkillRules.apply(run, offer.offer_id, skill.skill_id).success)

func test_build_card_and_pool_read_real_level_without_changing_rules() -> void:
	var previous_locale: String = TranslationServer.get_locale()
	TranslationServer.set_locale("zh_CN")
	var hud: Hud = HUD.instantiate() as Hud
	add_child_autofree(hud)
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	_apply(run, CORE)
	_apply(run, SUPPLY)
	hud.show_run(run)
	var card: CARD_SCRIPT = hud.build_list._cards[SUPPLY.skill_id] as CARD_SCRIPT
	assert_eq(card.level_label.text, "Lv.1")
	_apply(run, SUPPLY)
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	hud.show_run(run)
	assert_same(hud.build_list._cards[SUPPLY.skill_id], card)
	assert_eq(card.level_label.text, "Lv.2")
	assert_string_contains(SkillPoolText.details(run, SUPPLY), "等级 2 / 2")
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)
	run.abilities.resolve_removal(run.state.rules.state.get_snapshot(), &"skill_clear")
	hud.show_run(run)
	assert_true(hud.build_list._cards.has(CORE.skill_id))
	assert_eq(card.level_label.text, "Lv.2")
	# 只读刷新及池查询没有重抽或消费能力。
	assert_eq(run.state.skill_instances[SUPPLY.skill_id].abilities[0].trigger_count, 2)
	assert_eq(run.state.rewards.consumed_count, 3)
	TranslationServer.set_locale(previous_locale)
