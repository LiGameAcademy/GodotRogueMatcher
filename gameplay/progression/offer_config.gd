class_name OfferConfig
extends Resource

## Read-only trial configuration. Parameters are not calibrated acceptance results.
@export var rarity_weights: Array[float] = [1.0, 0.65, 0.35, 0.15, 0.06]
@export var rarity_steps: Array[OfferRarityStep] = []
@export var related_gain: float = 0.25
@export var gap_gain: float = 0.25
@export var factor_min: float = 1.0
@export var factor_max: float = 2.0
## -1 disables the quota; zero excludes utilities. No fallback bypasses this quota.
@export var maximum_utility_picks: int = 1
@export var rules_version: String = "offer-unified-trial-v2"
@export var profile_id: StringName = &"gentle_guidance_trial"
@export var parameter_status: String = "trial_unvalidated"
## Diagnostic occupancy/fragmentation proxy only; contributes zero to the trial weight.
@export var occupancy_weight: float = 0.7

func validation_error() -> String:
	if rules_version.is_empty() or profile_id.is_empty(): return "offer configuration lacks version identity"
	if maximum_utility_picks < -1: return "invalid utility quota"
	for value: float in [related_gain, gap_gain, factor_min, factor_max, occupancy_weight]:
		if not is_finite(value): return "nonfinite offer parameter"
	if related_gain < 0.0 or gap_gain < 0.0 or factor_min <= 0.0 or factor_max < factor_min:
		return "invalid offer factor bounds"
	if occupancy_weight < 0.0 or occupancy_weight > 1.0: return "invalid diagnostic occupancy weight"
	if not _valid_weights(rarity_weights): return "invalid rarity weights"
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

func data() -> Dictionary:
	return {"related_gain": related_gain, "gap_gain": gap_gain, "factor_min": factor_min,
		"factor_max": factor_max, "maximum_utility_picks": maximum_utility_picks,
		"parameter_status": parameter_status, "situational_enabled": false, "history_enabled": false,
		"startup_guarantee": false, "rescue_early_opening": false}

## Restores only the registered a/d trial grid; callers must still compare the complete config hash.
static func restore_trial(value: Variant, metadata: Variant, baseline: OfferConfig) -> OfferConfig:
	if not value is Dictionary or not metadata is Dictionary or baseline == null: return null
	var trial: Variant = metadata.get("offer_trial")
	if not trial is Dictionary or trial.size() != 4: return null
	for key: String in ["related_gain", "gap_gain"]:
		if typeof(value.get(key)) not in [TYPE_FLOAT, TYPE_INT] or value[key] not in [0.0, 0.25, 0.5]: return null
		if typeof(trial.get(key)) not in [TYPE_FLOAT, TYPE_INT] or trial[key] != value[key]: return null
	if trial.get("parameter_status") != "trial_unvalidated" or not trial.has("acceptance") or trial.acceptance != null: return null
	if not valid_trial_identity(metadata.get("experiment_id")) or not valid_trial_identity(metadata.get("variant_id")): return null
	var result: OfferConfig = baseline.duplicate(true) as OfferConfig
	result.related_gain = float(value.related_gain)
	result.gap_gain = float(value.gap_gain)
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
