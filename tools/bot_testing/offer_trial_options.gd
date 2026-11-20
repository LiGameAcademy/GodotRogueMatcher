class_name OfferTrialOptions
extends RefCounted

## Explicit batch-only trial parameters; never changes the shared resource or accepts balance values.
var config: OfferConfig
var experiment_id: String = ""
var variant_id: String = ""
var error: String = ""
var _include_situational: bool = false

static func from_args(args: PackedStringArray) -> OfferTrialOptions:
	var result: OfferTrialOptions = OfferTrialOptions.new()
	var values: Dictionary[String, String] = {}
	for arg: String in args:
		var key: String = arg.get_slice("=", 0)
		if key not in ["--offer-a", "--offer-d", "--offer-s", "--experiment", "--variant"]:
			if arg.begins_with("--offer-"): result.error = "unknown offer trial option"
			continue
		if not arg.contains("=") or values.has(key):
			result.error = "missing or duplicate offer trial option"
			return result
		values[key] = arg.substr(key.length() + 1)
	if not result.error.is_empty() or values.is_empty(): return result
	if not values.has("--offer-a") or not values.has("--offer-d") or not values.has("--experiment") or not values.has("--variant"):
		result.error = "offer trial requires explicit a, d, experiment and variant"
		return result
	if values.size() not in [4, 5] or (values.has("--offer-s") != (values.size() == 5)):
		result.error = "offer trial requires explicit a, d, experiment and variant"
		return result
	for key: String in ["--offer-a", "--offer-d"]:
		if values[key] not in ["0", "0.0", "0.25", "0.5"]:
			result.error = "offer trial coefficient must be 0, 0.25 or 0.5"
			return result
	if values.has("--offer-s") and values["--offer-s"] not in ["0", "0.0", "0.25", "0.5"]:
		result.error = "offer trial coefficient must be 0, 0.25 or 0.5"
		return result
	if not OfferConfig.valid_trial_identity(values["--experiment"]) or not OfferConfig.valid_trial_identity(values["--variant"]):
		result.error = "invalid offer experiment or variant identity"
		return result
	result.experiment_id = values["--experiment"]
	result.variant_id = values["--variant"]
	result.config = SkillOfferGenerator.CONFIG.duplicate(true) as OfferConfig
	result.config.related_gain = values["--offer-a"].to_float()
	result.config.gap_gain = values["--offer-d"].to_float()
	if values.has("--offer-s"):
		result._include_situational = true
		result.config.situational_gain = values["--offer-s"].to_float()
	result.error = result.config.validation_error()
	return result

func metadata() -> Dictionary:
	if config == null or not error.is_empty(): return {}
	var trial: Dictionary = {"related_gain": config.related_gain, "gap_gain": config.gap_gain,
		"parameter_status": config.parameter_status, "acceptance": null}
	if _include_situational:
		trial["situational_gain"] = config.situational_gain
	return {"experiment_id": experiment_id, "variant_id": variant_id, "offer_trial": trial}

## Programmatic callers receive the same strict boundary before a run or file is created.
func validation_error() -> String:
	if not error.is_empty(): return error
	if config == null: return "" if experiment_id.is_empty() and variant_id.is_empty() else "missing offer trial configuration"
	var fields: Dictionary = RunSnapshot.resource_fields(config)
	var restored: OfferConfig = OfferConfig.restore_trial(fields, metadata(), SkillOfferGenerator.CONFIG)
	if restored == null: return "invalid offer trial binding"
	if RunSnapshot.digest(fields) != RunSnapshot.digest(RunSnapshot.resource_fields(restored)): return "unsupported offer trial field change"
	return ""
