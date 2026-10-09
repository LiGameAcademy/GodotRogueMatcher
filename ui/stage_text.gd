class_name StageText
extends RefCounted

static func progress(state: RunState) -> String:
	var stage: StageState = state.stage
	var hint: String = TranslationServer.translate("未达标持续补棋升压 · 达标降压并三选一")
	if stage.index == stage.config.targets.size() - 1: hint = TranslationServer.translate("末阶段达标即完成挑战")
	if stage.missing_score() == 0 and stage.used_actions == 0: hint = TranslationServer.translate("抵扣已足，完成一次有效行动后检验")
	if stage.awaiting_reward: hint = TranslationServer.translate("阶段通过 · 选择一项技能后进入下一阶段")
	return TranslationServer.translate("阶段 %d / %d · 目标 %d · 还差 %d\n行动得分 %d + 抵扣 %d · 下次应补 %d 枚\n%s") % [stage.index + 1, stage.config.targets.size(), stage.target(), stage.missing_score(), stage.action_score, stage.carry_in, state.next_refill_count(), hint]

static func end_title(state: RunState) -> String:
	match state.end_reason:
		&"challenge_completed": return TranslationServer.translate("挑战完成")
	return TranslationServer.translate("棋盘已满，本局结束")

static func end_summary(state: RunState) -> String:
	if not state.stage.enabled(): return ""
	var stage: StageState = state.stage
	return TranslationServer.translate("阶段 %d / %d · 目标 %d · 尚差 %d 分\n行动得分 %d · 抵扣 %d · 已用行动 %d\n\n") % [stage.index + 1, stage.config.targets.size(), stage.target(), stage.missing_score(), stage.action_score, stage.carry_in, stage.used_actions]
