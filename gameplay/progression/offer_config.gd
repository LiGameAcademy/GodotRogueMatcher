class_name OfferConfig
extends Resource

## Read-only trial configuration. Parameters are not calibrated acceptance results.
@export var rarity_weights: Array[float] = [1.0, 0.65, 0.35, 0.15, 0.06]
@export var rarity_steps: Array[OfferRarityStep] = []
@export var related_gain: float = 0.25
@export var gap_gain: float = 0.25
## Board-pressure term s in clamp(1 + a×related + d×fills_gap + s). Default 0 keeps current trial weights.
@export var situational_gain: float = 0.0
## Multiplies situational_gain × P/100 by rarity (common→legendary). Uncommon+ feel pressure first.
@export var rarity_pressure_weights: Array[float] = [0.0, 0.35, 0.65, 0.85, 1.0]
@export var factor_min: float = 1.0
@export var factor_max: float = 2.0
## -1 disables the quota; zero excludes utilities. No fallback bypasses this quota.
@export var maximum_utility_picks: int = 1
@export var rules_version: String = "offer-unified-trial-v2"
@export var profile_id: StringName = &"gentle_guidance_trial"
@export var parameter_status: String = "trial_unvalidated"
## Occupancy/fragmentation mix for BoardPressure P; also feeds situational s when gain > 0.
@export var occupancy_weight: float = 0.7

func validation_error() -> String:
	if rules_version.is_empty() or profile_id.is_empty(): return "offer configuration lacks version identity"
	if maximum_utility_picks < -1: return "invalid utility quota"
	for value: float in [related_gain, gap_gain, situational_gain, factor_min, factor_max, occupancy_weight]:
		if not is_finite(value): return "nonfinite offer parameter"
	if related_gain < 0.0 or gap_gain < 0.0 or situational_gain < 0.0 or factor_min <= 0.0 or factor_max < factor_min:
		return "invalid offer factor bounds"
	if occupancy_weight < 0.0 or occupancy_weight > 1.0: return "invalid diagnostic occupancy weight"
	if not _valid_weights(rarity_weights): return "invalid rarity weights"
	if rarity_pressure_weights.size() != 5: return "invalid rarity pressure curve"
	for value: float in rarity_pressure_weights:
		if not is_finite(value) or value < 0.0 or value > 1.0: return "invalid rarity pressure curve"
	var previous: int = 0
	for step: OfferRarityStep in rarity_steps:
		if step == null or step.first_choice <= previous or not _valid_weights(step.weights):
			return "invalid or unordered rarity curve"
		previous = step.first_choice
	return ""

func base_weight(rarity: int, successful_choice_index: int) -> float:
	var values: Array[float] = rarity_weights
	for step: OfferRarityStep in rarity_steps:
		if successful_choice_index < step.first_choice: break
		values = step.weights
	return values[rarity]

## Situational rescue term s; common stays 0 on the default curve, rarer cards scale with P.
func situational_term(rarity: int, pressure: float) -> float:
	if situational_gain <= 0.0 or rarity < 0 or rarity >= rarity_pressure_weights.size(): return 0.0
	if not is_finite(pressure): return 0.0
	return situational_gain * clampf(pressure / 100.0, 0.0, 1.0) * rarity_pressure_weights[rarity]

func data() -> Dictionary:
	return {"related_gain": related_gain, "gap_gain": gap_gain, "situational_gain": situational_gain,
		"factor_min": factor_min, "factor_max": factor_max, "maximum_utility_picks": maximum_utility_picks,
		"parameter_status": parameter_status, "situational_enabled": situational_gain > 0.0, "history_enabled": false,
		"startup_guarantee": false, "rescue_early_opening": false}

## Restores registered a/d (and optional s) trial grid; callers must still compare the complete config hash.
static func restore_trial(value: Variant, metadata: Variant, baseline: OfferConfig) -> OfferConfig:
	if not value is Dictionary or not metadata is Dictionary or baseline == null: return null
	var trial: Variant = metadata.get("offer_trial")
	if not trial is Dictionary or trial.size() not in [4, 5]: return null
	for key: String in ["related_gain", "gap_gain"]:
		if typeof(value.get(key)) not in [TYPE_FLOAT, TYPE_INT] or value[key] not in [0.0, 0.25, 0.5]: return null
		if typeof(trial.get(key)) not in [TYPE_FLOAT, TYPE_INT] or trial[key] != value[key]: return null
	var has_s: bool = trial.has("situational_gain")
	if has_s != (trial.size() == 5): return null
	if has_s:
		if typeof(value.get("situational_gain")) not in [TYPE_FLOAT, TYPE_INT] or value.situational_gain not in [0.0, 0.25, 0.5]: return null
		if typeof(trial.get("situational_gain")) not in [TYPE_FLOAT, TYPE_INT] or trial.situational_gain != value.situational_gain: return null
	if trial.get("parameter_status") != "trial_unvalidated" or not trial.has("acceptance") or trial.acceptance != null: return null
	if not valid_trial_identity(metadata.get("experiment_id")) or not valid_trial_identity(metadata.get("variant_id")): return null
	var result: OfferConfig = baseline.duplicate(true) as OfferConfig
	result.related_gain = float(value.related_gain)
	result.gap_gain = float(value.gap_gain)
	result.situational_gain = float(value.situational_gain) if has_s else baseline.situational_gain
	return result if result.validation_error().is_empty() else null

static func valid_trial_identity(value: Variant) -> bool:
	if not value is String: return false
	var pattern: RegEx = RegEx.new()
	pattern.compile("^[A-Za-z0-9_-][A-Za-z0-9_.-]{0,63}\\z")
	return pattern.search(value) != null

static func _valid_weights(values: Array[float]) -> bool:
	if values.size() != 5: return false
	for value: float in values:
		if not is_finite(value) or value <= 0.0: return false
	return true
