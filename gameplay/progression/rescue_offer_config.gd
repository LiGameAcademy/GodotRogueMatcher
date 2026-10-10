class_name RescueOfferConfig
extends Resource

@export var occupancy_weight: float = 0.7
@export var pressure_start: float = 40.0
@export var maximum_gain: float = 1.2
@export var early_pressure: float = 70.0
@export var rules_version: String = "offer-pressure-trial-v2-percent-clear"

func validation_error() -> String:
	if not is_finite(occupancy_weight) or occupancy_weight < 0.0 or occupancy_weight > 1.0: return "Invalid pressure occupancy weight"
	if not is_finite(pressure_start) or pressure_start < 0.0 or pressure_start >= 100.0: return "Invalid rescue pressure start"
	if not is_finite(maximum_gain) or maximum_gain < 0.0: return "Invalid rescue maximum gain"
	if not is_finite(early_pressure) or early_pressure < 0.0 or early_pressure > 100.0: return "Invalid early rescue pressure"
	return ""
