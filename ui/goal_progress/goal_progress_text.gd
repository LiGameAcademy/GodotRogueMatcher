class_name GoalProgressText
extends RefCounted

## 两处数字共用整局账本，显示不能触发规则结算。
static func current(state: RunState) -> int:
	return state.ledger.total

static func current_tooltip(_state: RunState) -> String:
	return TranslationServer.translate("当前分数 · 整局累计，过关不扣分。选卡额外得分也推进目标。")

static func target_tooltip(state: RunState) -> String:
	var tip: String = TranslationServer.translate("目标分数")
	if state.stage.enabled(): tip += "\n" + TranslationServer.translate("阶段 %d / %d") % [state.stage.index + 1, state.stage.config.targets.size()]
	return tip

static func rule_tooltip(state: RunState) -> String:
	if not state.stage.enabled(): return TranslationServer.translate("达到目标分数后触发技能三选一。")
	var tip: String = TranslationServer.translate("未达标持续增加补棋数量，达标恢复并触发技能三选一。")
	if state.stage.awaiting_reward: tip += "\n" + TranslationServer.translate("阶段通过 · 选择一项技能后进入下一阶段")
	elif state.stage.missing_score() == 0 and state.stage.used_actions == 0: tip += "\n" + TranslationServer.translate("抵扣已足，完成一次有效行动后检验")
	if state.stage.index == state.stage.config.targets.size() - 1: tip += "\n" + TranslationServer.translate("末阶段达标即完成挑战")
	return tip
