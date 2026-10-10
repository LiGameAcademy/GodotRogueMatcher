class_name RescueOfferRules
extends RefCounted

const CONFIG: RescueOfferConfig = preload("res://gameplay/progression/content/rescue_offer_config.tres")

static func pressure(state: RunState) -> Dictionary:
	var coordinates: Array[Vector2i] = []
	for piece: PieceState in state.rules.state.get_snapshot(): coordinates.append(piece.coordinate)
	return BoardPressure.evaluate(state.rules.state.columns, state.rules.state.rows, coordinates, CONFIG.occupancy_weight)

static func early_allowed(state: RunState, skill: SkillDefinition, frozen_pressure: float = -1.0) -> bool:
	if not state.stage.enabled() or not skill.rescue_offer or not CONFIG.validation_error().is_empty(): return false
	var value: float = frozen_pressure if frozen_pressure >= 0.0 else float(pressure(state).get("P", 0.0))
	return value >= CONFIG.early_pressure

static func factor(state: RunState, skill: SkillDefinition, frozen_pressure: float = -1.0) -> float:
	if not state.stage.enabled() or not skill.rescue_offer: return 1.0
	var value: float = frozen_pressure if frozen_pressure >= 0.0 else float(pressure(state).get("P", 0.0))
	return multiplier(value, CONFIG)

static func multiplier(pressure_value: float, config: RescueOfferConfig) -> float:
	if not config.validation_error().is_empty() or not is_finite(pressure_value): return NAN
	return 1.0 + config.maximum_gain * clampf((pressure_value - config.pressure_start) / (100.0 - config.pressure_start), 0.0, 1.0)
