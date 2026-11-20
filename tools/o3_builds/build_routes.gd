class_name O3BuildRoutes
extends RefCounted

## O3/#122 read-only route registry. Not a natural-acquisition sampler or balance verdict.
const ORDER: Array[StringName] = [&"B1", &"L1", &"B2", &"L2", &"M1", &"M2"]
const MEASURES: Array[StringName] = [&"startup", &"sustain", &"synergy", &"upgrade"]

static func routes() -> Dictionary:
	return {
		&"B1": {
			"title": "爆破基础兑现",
			"engines": [&"core_drop"],
			"growth": [&"core_supply_up", &"blast_radius", &"blast_reward", &"blast_extra"],
			"focus": "供给、利用、范围与得分分别验证",
			"fixture": "partial",
		},
		&"L1": {
			"title": "单轴扫线",
			"engines": [&"line_row_drop", &"line_column_drop"],
			"growth": [&"line_row_span", &"line_column_span", &"line_clear_score"],
			"focus": "固有离场不依赖主动；行列各基础覆盖",
			"fixture": "line_clear_score",
		},
		&"B2": {
			"title": "引信连锁",
			"engines": [&"core_drop", &"assign_fuse"],
			"growth": [&"core_fuse_payload", &"fuse_relay", &"marked_reward", &"fuse_capacity", &"fuse_match_plant"],
			"focus": "一次标记与持续供给、布局及延续",
			"fixture": "fuse_chain",
		},
		&"L2": {
			"title": "十字扫线",
			"engines": [&"line_row_drop", &"line_column_drop"],
			"growth": [&"line_cross_upgrade", &"line_row_span", &"line_column_span", &"line_clear_score"],
			"focus": "摆位、边缘截断、交叉去重与两轴取舍",
			"fixture": "cross_pair",
		},
		&"M1": {
			"title": "爆破启动扫线",
			"engines": [&"core_drop", &"line_row_drop", &"line_column_drop"],
			"growth": [&"blast_radius", &"line_row_span", &"line_column_span"],
			"focus": "爆破→扫线可靠性与额外选择成本",
			"fixture": "blast_starts_line",
		},
		&"M2": {
			"title": "扫线启动爆破",
			"engines": [&"line_row_drop", &"line_column_drop", &"core_drop", &"assign_fuse"],
			"growth": [&"core_fuse_payload", &"blast_radius", &"fuse_relay"],
			"focus": "扫线→爆破及提前消耗布局代价",
			"fixture": "line_starts_blast",
		},
	}

static func all_skill_ids() -> Array[StringName]:
	var seen: Dictionary[StringName, bool] = {}
	var ids: Array[StringName] = []
	var table: Dictionary = routes()
	for route_id: StringName in ORDER:
		var route: Dictionary = table[route_id]
		for key: String in ["engines", "growth"]:
			for skill_id: StringName in route[key]:
				if seen.has(skill_id): continue
				seen[skill_id] = true
				ids.append(skill_id)
	return ids

static func catalog_missing() -> Array[StringName]:
	var present: Dictionary[StringName, bool] = {}
	for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
		present[skill.skill_id] = true
	var missing: Array[StringName] = []
	for skill_id: StringName in all_skill_ids():
		if not present.has(skill_id): missing.append(skill_id)
	return missing
