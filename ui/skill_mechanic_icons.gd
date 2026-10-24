class_name SkillMechanicIcons
extends RefCounted

## 显示侧首批图标清单；不依据名称/宽泛Tag猜测，不写入技能规则Resource。
const EXPLOSION: Texture2D = preload("res://assets/textures/ui/icon_ability_explosion.png")
const SWEEP: Texture2D = preload("res://assets/textures/ui/icon_ability_sweep.png")
const TEXTURES: Dictionary[StringName, Texture2D] = {
	&"core_drop": EXPLOSION,
	&"core_supply_up": EXPLOSION,
	&"core_radius": EXPLOSION,
	&"line_row_drop": SWEEP,
	&"line_column_drop": SWEEP,
	&"line_row_span": SWEEP,
	&"line_column_span": SWEEP,
}
const ROLES: Dictionary[StringName, String] = {
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
