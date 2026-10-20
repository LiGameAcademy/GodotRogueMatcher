class_name SpawnPoolText
extends RefCounted

## 只读条件概率；已锁定预告和出生时的唯一限制分别说明。
static func describe(state: RunState) -> String:
	var weights: Array[int] = state.spawning.color_weights
	var total: int = 0
	for weight: int in weights: total += weight
	var lines: PackedStringArray = [TranslationServer.translate("类型候选 · 新生成的预告")]
	if state.explosion.core_pool_unlocked:
		var config: DemolitionConfig = DemolitionRules.CONFIG
		var core: int = config.core_type_weight + state.explosion.level(&"core_supply_up") * config.core_supply_per_level
		var sum: int = config.ordinary_type_weight + core
		lines.append(TranslationServer.translate("普通 %d/%d（%.1f%%）") % [config.ordinary_type_weight, sum, 100.0 * config.ordinary_type_weight / sum])
		lines.append(TranslationServer.translate("爆破手候选 %d/%d（%.1f%%）") % [core, sum, 100.0 * core / sum])
	else:
		lines.append(TranslationServer.translate("普通 100% · 爆破手尚未解锁"))
	lines.append(TranslationServer.translate("\n普通类型内的颜色概率"))
	for color: int in range(weights.size()):
		var chance: float = 100.0 * weights[color] / total if total > 0 else 0.0
		lines.append("%s  %d/%d（%.1f%%）" % [TranslationServer.translate(PieceTooltip.COLOR_NAMES[color]), weights[color], total, chance])
	lines.append(TranslationServer.translate("\n颜色权重只影响新预告，已显示的棋子不会重抽。\n爆破手场上唯一：候选出生时若已有爆破手，会转成预告中的普通颜色。"))
	return "\n".join(lines)
