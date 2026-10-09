class_name StageText
extends RefCounted

static func progress(state: RunState) -> String:
	var stage: StageState = state.stage
	var hint: String = TranslationServer.translate("过关三选一 · 行动耗尽未达标失败")
	if stage.index == stage.config.targets.size() - 1: hint = TranslationServer.translate("末阶段达标即完成挑战")
	if stage.missing_score() == 0 and stage.used_actions == 0: hint = TranslationServer.translate("抵扣已足，完成一次有效行动后检验")
	if stage.awaiting_reward: hint = TranslationServer.translate("阶段通过 · 选择一项技能后进入下一阶段")
	return TranslationServer.translate("阶段 %d / %d · 目标 %d · 还差 %d\n行动得分 %d + 抵扣 %d · 剩余行动 %d / %d\n%s") % [stage.index + 1, stage.config.targets.size(), stage.target(), stage.missing_score(), stage.action_score, stage.carry_in, stage.remaining_actions(), stage.action_limit(), hint]

static func end_title(state: RunState) -> String:
	match state.end_reason:
		&"challenge_completed": return TranslationServer.translate("挑战完成")
		&"stage_target_missed": return TranslationServer.translate("行动耗尽 · 阶段挑战失败")
	return TranslationServer.translate("棋盘已满，本局结束")

static func end_summary(state: RunState) -> String:
	if not state.stage.enabled(): return ""
	var stage: StageState = state.stage
	return TranslationServer.translate("阶段 %d / %d · 目标 %d · 尚差 %d 分\n行动得分 %d · 抵扣 %d · 已用行动 %d / %d\n\n") % [stage.index + 1, stage.config.targets.size(), stage.target(), stage.missing_score(), stage.action_score, stage.carry_in, stage.used_actions, stage.action_limit()]
