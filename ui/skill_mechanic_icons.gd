class_name SkillMechanicIcons
extends RefCounted

## 显示侧首批图标清单；不依据名称/宽泛Tag猜测，不写入技能规则Resource。
const EXPLOSION: Texture2D = preload("res://assets/textures/ui/icon_ability_explosion.png")
const SWEEP: Texture2D = preload("res://assets/textures/ui/icon_ability_sweep.png")
const REFILL_LESS: Texture2D = preload("res://assets/textures/ui/icon_ability_refill_less.svg")
const REFILL_MORE: Texture2D = preload("res://assets/textures/ui/icon_ability_refill_more.svg")
const MULTIPLIER: Texture2D = preload("res://assets/textures/ui/icon_ability_multiplier.svg")
const DYE: Texture2D = preload("res://assets/textures/ui/icon_ability_dye.svg")
const FUSE: Texture2D = preload("res://assets/textures/ui/icon_ability_fuse.svg")
const MATCH_BONUS: Texture2D = preload("res://assets/textures/ui/icon_ability_match_bonus.svg")
const TEXTURES: Dictionary[StringName, Texture2D] = {
	&"match_extra": MATCH_BONUS,
	&"precision_reward": MATCH_BONUS,
	&"longline_reward": MATCH_BONUS,
	&"fuse_match_plant": FUSE,
	&"fuse_relay": FUSE,
	&"relay_capacity": FUSE,
	&"match_dye_echo": DYE,
	&"dye_target_up": DYE,
	&"dye_chain_depth": DYE,
	&"refill_less": REFILL_LESS,
	&"refill_more": REFILL_MORE,
	&"score_multiplier": MULTIPLIER,
	&"core_drop": EXPLOSION,
	&"core_supply_up": EXPLOSION,
	&"core_radius": EXPLOSION,
	&"line_row_drop": SWEEP,
	&"line_column_drop": SWEEP,
	&"line_row_span": SWEEP,
	&"line_column_span": SWEEP,
}
const ROLES: Dictionary[StringName, String] = {
	&"match_extra": "补分",
	&"precision_reward": "正好",
	&"longline_reward": "长连",
	&"fuse_match_plant": "布雷",
	&"fuse_relay": "传递",
	&"relay_capacity": "接力",
	&"match_dye_echo": "接续",
	&"dye_target_up": "扩散",
	&"dye_chain_depth": "再续",
	&"refill_less": "减量",
	&"refill_more": "增量",
	&"score_multiplier": "倍率（短）",
	&"core_drop": "登场",
	&"core_supply_up": "补给",
	&"core_radius": "范围",
	&"line_row_drop": "登场",
	&"line_column_drop": "登场",
	&"line_row_span": "范围",
	&"line_column_span": "范围",
}
const VERTICAL: Array[StringName] = [&"line_column_drop", &"line_column_span"]

static func texture_for(id: StringName) -> Texture2D:
	return TEXTURES.get(id) as Texture2D

static func role_for(id: StringName) -> String:
	return TranslationServer.translate(ROLES.get(id, "")) if ROLES.has(id) else ""

static func rotation_for(id: StringName) -> float:
	return 90.0 if id in VERTICAL else 0.0
