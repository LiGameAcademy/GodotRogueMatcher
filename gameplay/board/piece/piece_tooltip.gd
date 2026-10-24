class_name PieceTooltip
extends RefCounted

## 从只读规则数据生成提示；不保存能力状态，也不消费随机数。
const COLOR_NAMES: Array[String] = ["花生", "腰果", "杏仁", "核桃", "开心果"]

static func describe(piece: PieceState, explosion: ExplosionState, config: ExplosionConfig, item: ItemData = null, line_clear: LineClearState = null, manual_uses_used: Dictionary[StringName, int] = {}) -> String:
	var lines: Array[String] = []
	if explosion.instances.has(piece.piece_id):
		lines.append(TranslationServer.translate("爆壳手") if piece.content_id == &"special_demolition" else TranslationServer.translate("引信棋子"))
		lines.append(TranslationServer.translate("匹配色：%s；可移动、参与同色五连。") % TranslationServer.translate(COLOR_NAMES[posmod(piece.match_color, COLOR_NAMES.size())]))
		var removal: String = TranslationServer.translate("五连或爆炸") if piece.content_id == &"special_demolition" else TranslationServer.translate("五连、爆炸或颜色／行列清理")
		lines.append(TranslationServer.translate("被%s消除后引爆，自身离场。") % removal)
		var radius: int = mini(DemolitionRules.CONFIG.maximum_radius, config.base_radius + explosion.radius_level + (explosion.level(&"core_radius") if piece.content_id == &"special_demolition" else 0))
		var diameter: int = radius * 2 + 1
		lines.append(TranslationServer.translate("爆炸范围：周围半径 %d 格（%d×%d，边缘截断）。") % [radius, diameter, diameter])
		lines.append(TranslationServer.translate("命中其他引信 / 爆壳手会继续连锁。"))
		if piece.content_id == &"special_demolition" and explosion.level(&"core_manual_detonation") > 0:
			lines.append(TranslationServer.translate("双击主动爆破：消耗本枚和一次行动，正常补棋。"))
			lines.append(_manual_remaining(manual_uses_used, false))
		if explosion.level(&"selective_blast") > 0: lines.append(TranslationServer.translate("异色爆破：跳过与来源同色的目标。"))
		if piece.content_id.is_empty() and explosion.level(&"blast_chain_radius") > 0: lines.append(TranslationServer.translate("第2代起引信半径额外+1，最终上限3。"))
		var per_target: int = explosion.reward_level * config.reward_per_target
		lines.append(TranslationServer.translate("爆炸每清除一枚目标 +%d 分，不受五连倍率影响。") % per_target)
		var bonus: int = explosion.blast_extra_level * config.bonus_per_blast
		if bonus > 0:
			lines.append(TranslationServer.translate("至少清除一枚目标时，本次爆炸另加 %d 分。") % bonus)
	elif LineClearState.is_line_piece(piece.content_id):
		var axis_name: String = TranslationServer.translate("行清除手") if piece.content_id == LineClearState.CONTENT_ROW else TranslationServer.translate("列清除手")
		lines.append(axis_name)
		lines.append(TranslationServer.translate("匹配色：%s；可移动、参与同色五连。") % TranslationServer.translate(COLOR_NAMES[posmod(piece.match_color, COLOR_NAMES.size())]))
		lines.append(TranslationServer.translate("被消除时扫清所在行或列；命中特殊棋子会继续触发。"))
		if line_clear != null:
			var bonus: int = LineClearRules.score_per_target(line_clear.level(&"line_clear_score"))
			if bonus > 0: lines.append(TranslationServer.translate("扫线每直接清除1枚，额外+%d分。") % bonus)
			var axis: int = LineClearState.axis_of(piece.content_id)
			var count: int = LineClearRules.line_count(line_clear.level(LineClearRules.upgrade_for_axis(axis)))
			var shape: String = TranslationServer.translate("连续%d行（边缘截断）") if axis == LineClearState.AXIS_ROW else TranslationServer.translate("连续%d列（边缘截断）")
			lines.append(shape % count)
			if line_clear.level(&"line_cross_upgrade") > 0:
				lines.append(TranslationServer.translate("十字扫线：同时清连续%d行与%d列（边缘截断）。") % [LineClearRules.line_count(line_clear.level(&"line_row_span")), LineClearRules.line_count(line_clear.level(&"line_column_span"))])
		if line_clear != null and line_clear.level(&"line_manual_clear") > 0:
			lines.append(TranslationServer.translate("双击主动扫线：消耗本枚和一次行动，正常补棋。"))
			lines.append(_manual_remaining(manual_uses_used, true))
	elif item != null:
		lines.append(item.get_localized_name())
		lines.append(item.get_effect_description())
	if piece.is_ghost:
		if lines.is_empty(): lines.append(TranslationServer.translate("幽灵棋子"))
		lines.append(TranslationServer.translate("半透明显示；仍占一格，按当前颜色参与五连。"))
	return "\n".join(lines)

static func _manual_remaining(used: Dictionary[StringName, int], line: bool) -> String:
	var count: int = ManualActivationRules.remaining_count(used, ManualActivationRules.skill(line))
	if count == 0: return TranslationServer.translate("主动次数已用完；被消除时仍正常触发。")
	return TranslationServer.translate("主动剩余 %d / %d 次；空放也扣次数，连锁不额外扣。") % [count, ManualActivationRules.skill(line).manual_use_limit]
