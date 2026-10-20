extends GutTest

const POPUP: PackedScene = preload("res://ui/popup_skill_choice.tscn")
const TRANSFER: PackedScene = preload("res://ui/card_transfer/card_transfer.tscn")
const CORE: SkillDefinition = preload("res://gameplay/progression/content/core_drop.tres")
const SCORE: SkillDefinition = preload("res://gameplay/progression/content/score_multiplier.tres")
const CLEAR: SkillDefinition = preload("res://gameplay/progression/content/instant_color_clear.tres")
var run: RunController
var popup: PopupSkillChoice

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	run = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 8)
	run.state.rules.place_piece(Vector2i.ZERO, 0)
	run.state.rules.place_piece(Vector2i.ONE, 1)
	run.state.pending_rewards = 1
	run.enter_rewards()
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = 1
	offer.reward_id = 1
	offer.choices = [CORE, SCORE, CLEAR]
	for skill: SkillDefinition in offer.choices: offer.targets[skill.skill_id] = SkillRules.freeze_target(run.state, skill)
	run.state.rewards.active_offer = offer
	popup = POPUP.instantiate() as PopupSkillChoice
	add_child_autofree(popup)
	popup.show_offer(offer)
	popup.set_low_effects(true)
	watch_signals(popup)

func after_each() -> void:
	get_tree().paused = false

func test_select_switch_inspect_and_pause_do_not_submit_or_mutate_run() -> void:
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	assert_true(popup.confirm_button.disabled)
	popup.confirm_selection()
	popup._select(0)
	popup._select(1)
	popup.toggle_board_view()
	popup.confirm_selection()
	popup.toggle_selection_pause()
	popup.confirm_selection()
	popup.toggle_selection_pause()
	popup.toggle_board_view()
	assert_signal_not_emitted(popup, "skill_selected")
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)
	popup.confirm_selection()
	popup.confirm_selection()
	assert_signal_emitted_with_parameters(popup, "skill_selected", [1, SCORE.skill_id])
	assert_signal_emit_count(popup, "skill_selected", 1)

func test_color_choice_uses_same_bottom_confirmation_without_automatic_submission() -> void:
	popup._select(2)
	assert_false(popup.picker.confirm_button.visible)
	assert_true(popup.confirm_button.disabled)
	popup.picker.select_color(0)
	assert_false(popup.confirm_button.disabled)
	assert_signal_not_emitted(popup, "color_skill_selected")
	popup.confirm_selection()
	popup.confirm_selection()
	assert_signal_emitted_with_parameters(popup, "color_skill_selected", [1, CLEAR.skill_id, 0])
	assert_signal_emit_count(popup, "color_skill_selected", 1)

func test_rejected_selection_keeps_candidate_and_does_not_fly_card() -> void:
	var original: SkillOffer = popup.offer
	popup._select(1)
	popup.confirm_selection()
	popup.show_error("预算不足")
	assert_same(popup.offer, original)
	assert_false(popup.confirm_button.disabled)
	assert_signal_not_emitted(popup, "card_acquired")
	popup.confirm_selection()
	assert_signal_emit_count(popup, "skill_selected", 2)

func test_accepted_selection_emits_visual_once_after_rule_commit() -> void:
	popup._select(1)
	popup.confirm_selection()
	var result: SkillApplyResult = SkillRules.apply(run, 1, SCORE.skill_id)
	assert_true(result.success)
	popup.accept_selection(true)
	popup.accept_selection(true)
	assert_signal_emit_count(popup, "card_acquired", 1)
	assert_eq(run.state.rewards.consumed_count, 1)

func test_reveal_and_transfer_are_visual_only_and_support_pause_low_effects_and_cancel() -> void:
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	var card: SkillCard = popup.options.get_child(0) as SkillCard
	get_tree().paused = true
	card.reveal(0.0, false)
	assert_true(card.card_back.visible)
	await wait_seconds(0.30)
	assert_false(card.card_back.visible)
	assert_eq(card.scale, Vector2.ONE)
	var transfer: CardTransfer = TRANSFER.instantiate() as CardTransfer
	add_child_autofree(transfer)
	var source: Rect2 = Rect2(Vector2(400, 100), Vector2(256, 352))
	var destination: Rect2 = Rect2(Vector2(20, 200), Vector2(200, 300))
	transfer.play(CORE, popup.offer.targets[CORE.skill_id], source, destination, false)
	assert_true(transfer.card.visible)
	assert_eq(transfer.card.effect_label.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	await wait_seconds(0.40)
	assert_false(transfer.card.visible)
	transfer.play(CORE, popup.offer.targets[CORE.skill_id], source, destination, true)
	assert_false(transfer.card.visible)
	transfer.play(CORE, popup.offer.targets[CORE.skill_id], source, destination, false)
	transfer.cancel()
	assert_false(transfer.card.visible)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)

func test_closing_submitted_popup_without_success_acknowledgement_does_not_fly_card() -> void:
	popup._select(1)
	popup.confirm_selection()
	popup.accept_selection()
	assert_signal_not_emitted(popup, "card_acquired")
	assert_eq(run.state.rewards.consumed_count, 0)
