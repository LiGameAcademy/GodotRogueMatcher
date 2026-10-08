class_name PlayerPreferences
extends RefCounted

## 只保存已提供的表现选项；不保存局内规则状态。
var fast: bool = false
var low_effects: bool = false
var volume: float = 0.7
var tutorial_seen: bool = false
const SECTION: String = "rogue_matcher_presentation"

func load_values(config: CoreSystem.ConfigManager) -> void:
	var saved_fast: Variant = config.get_value(SECTION, "fast", false)
	var saved_low: Variant = config.get_value(SECTION, "low_effects", false)
	var saved_volume: Variant = config.get_value(SECTION, "volume", 0.7)
	var saved_tutorial: Variant = config.get_value(SECTION, "tutorial_seen", false)
	if saved_tutorial is bool: tutorial_seen = bool(saved_tutorial)
	if saved_fast is bool: fast = bool(saved_fast)
	if saved_low is bool: low_effects = bool(saved_low)
	if (saved_volume is float or saved_volume is int) and is_finite(float(saved_volume)):
		volume = clampf(float(saved_volume), 0.0, 1.0)

func save_values(config: CoreSystem.ConfigManager, path: String = "") -> bool:
	config.set_value(SECTION, "fast", fast)
	config.set_value(SECTION, "low_effects", low_effects)
	config.set_value(SECTION, "volume", volume)
	config.set_value(SECTION, "tutorial_seen", tutorial_seen)
	return config.save_config(path)
