class_name PieceTooltip
extends RefCounted

## 从只读规则数据生成提示；不保存能力状态，也不消费随机数。
const COLOR_NAMES: Array[String] = ["红色", "绿色", "蓝色", "黄色", "紫色"]

static func describe(piece: PieceState, explosion: ExplosionState, config: ExplosionConfig, item: ItemData = null) -> String:
	var lines: Array[String] = []
	if explosion.instances.has(piece.piece_id):
		lines.append("爆壳手" if piece.content_id == &"special_demolition" else "引信棋子")
		lines.append("匹配色：%s；可移动、参与同色五连。" % COLOR_NAMES[posmod(piece.match_color, COLOR_NAMES.size())])
		var removal: String = "五连或爆炸" if piece.content_id == &"special_demolition" else "五连、爆炸或颜色／行列清理"
		lines.append("被%s消除后引爆，自身离场。" % removal)
		var radius: int = mini(DemolitionRules.CONFIG.maximum_radius, config.base_radius + explosion.radius_level + (explosion.level(&"core_radius") if piece.content_id == &"special_demolition" else 0))
		var diameter: int = radius * 2 + 1
		lines.append("爆炸范围：周围半径 %d 格（%d×%d，边缘截断）。" % [radius, diameter, diameter])
		lines.append("命中其他引信 / 爆壳手会继续连锁。")
		if piece.content_id == &"special_demolition" and explosion.level(&"core_manual_detonation") > 0:
			lines.append("双击主动爆破：消耗本枚和一次行动，正常补棋。")
		if explosion.level(&"selective_blast") > 0: lines.append("异色爆破：跳过与来源同色的目标。")
		if piece.content_id.is_empty() and explosion.level(&"blast_chain_radius") > 0: lines.append("第2代起引信半径额外+1，最终上限3。")
		var per_target: int = explosion.reward_level * config.reward_per_target
		lines.append("爆炸每清除一枚目标 +%d 分，不受五连倍率影响。" % per_target)
		var bonus: int = explosion.blast_extra_level * config.bonus_per_blast
		if bonus > 0:
			lines.append("至少清除一枚目标时，本次爆炸另加 %d 分。" % bonus)
	elif item != null:
		lines.append(item.get_localized_name())
		lines.append(item.get_effect_description())
	if piece.is_ghost:
		if lines.is_empty(): lines.append("幽灵棋子")
		lines.append("半透明显示；仍占一格，按当前颜色参与五连。")
	return "\n".join(lines)
