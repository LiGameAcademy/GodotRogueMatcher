class_name HudStatusMessages
extends RefCounted

## Resolves status IDs from the imported CSV catalog without cross-language fallback.
## Owns diagnostic deduplication only; never reads or advances a game run.
signal diagnostic(message_id: StringName, locale: String, reason: String, parameters: Dictionary)

const LOCALES: Array[String] = ["zh_CN", "en_US"]
const IDS: Array[StringName] = [
	&"preparing", &"ready", &"paused", &"resolving", &"awaiting_skill", &"unavailable",
	&"counting_score", &"skip_requested", &"settings_failed", &"theme_invalid",
	&"challenge_completed", &"board_full", &"piece_queued", &"move_queued",
	&"queued_piece_missing", &"queued_target_invalid", &"playback_failed", &"playback_aligned",
	&"debug_classic_required", &"demo_dye", &"demo_limit", &"demo_score", &"demo_cross",
	&"demo_span", &"demo_line", &"demo_transform", &"capture_detonate", &"capture_chain",
	&"capture_refill_ready", &"capture_refill_used", &"capture_refill_done", &"spawn_progress",
	&"checkpoint_loading", &"checkpoint_saving", &"checkpoint_failed", &"checkpoint_fallback", &"checkpoint_restored",
	&"checkpoint_waiting",
]
const PARAMETER_TYPES: Dictionary = {
	&"hud.status.spawn_progress": {"current": TYPE_INT, "total": TYPE_INT},
	&"hud.status.capture_refill_used": {"count": TYPE_INT},
}

var _reported: Dictionary[String, bool] = {}
var _lookup: Callable

## Optional reader supports validating corrupt catalogs without mutating shared resources.
func _init(catalog_lookup: Callable = Callable()) -> void:
	_lookup = catalog_lookup

## Uses the exact supported locale. A missing translation never silently selects Chinese.
func render(message_id: StringName, parameters: Dictionary, locale: String) -> String:
	var template: String = _read_template(message_id, locale)
	var error: String = _validate(message_id, parameters, template)
	if error.is_empty(): return template.format(parameters)
	report(message_id, locale, error, parameters)
	var fallback: String = _read_template(&"hud.status.unavailable", locale)
	if not fallback.is_empty() and fallback != "hud.status.unavailable" and _placeholders(fallback).is_empty(): return fallback
	report(&"hud.status.unavailable", locale, "fallback_missing_or_invalid", {})
	return "—"

## Reports an internal reason separately from the localized player-facing message.
func report(message_id: StringName, locale: String, reason: String, parameters: Dictionary) -> void:
	var key: String = String(message_id) + "|" + locale + "|" + reason
	if _reported.has(key): return
	# Bound diagnostic memory even when malformed external IDs keep arriving.
	if _reported.size() >= 128: return
	_reported[key] = true
	diagnostic.emit(message_id, locale, reason, parameters.duplicate(true))
	push_warning("HUD status: id=%s locale=%s reason=%s parameters=%s" % [message_id, locale, reason, parameters])

## Release validation checks every declared ID in both actual imported catalogs.
static func catalog_errors() -> PackedStringArray:
	var errors: PackedStringArray = []
	for suffix: StringName in IDS:
		var id: StringName = StringName("hud.status." + String(suffix))
		for locale: String in LOCALES:
			var template: String = _template(id, locale)
			if template.is_empty() or template == String(id):
				errors.append("%s:%s:missing_translation" % [locale, id])
			elif _placeholders(template) != _expected_names(id):
				errors.append("%s:%s:placeholder_mismatch" % [locale, id])
	return errors

static func _template(message_id: StringName, locale: String) -> String:
	if not LOCALES.has(locale): return ""
	# Load the CSV-generated resource explicitly: the server can otherwise fall back
	# to another language or select a different catalog with the same locale.
	var path: String = "res://localization/game.%s.translation" % locale
	if not ResourceLoader.exists(path): return ""
	var catalog: Translation = load(path) as Translation
	return "" if catalog == null else String(catalog.get_message(message_id))

func _read_template(message_id: StringName, locale: String) -> String:
	return String(_lookup.call(message_id, locale)) if _lookup.is_valid() else _template(message_id, locale)

static func _validate(message_id: StringName, parameters: Dictionary, template: String) -> String:
	if not IDS.has(StringName(String(message_id).trim_prefix("hud.status."))) or not String(message_id).begins_with("hud.status."):
		return "unknown_id"
	if template.is_empty() or template == String(message_id): return "missing_translation"
	var expected: PackedStringArray = _expected_names(message_id)
	if _placeholders(template) != expected: return "placeholder_mismatch"
	if parameters.size() != expected.size(): return "parameter_names"
	var types: Dictionary = PARAMETER_TYPES.get(message_id, {})
	for name: String in expected:
		if not parameters.has(name): return "missing_parameter:" + name
		if typeof(parameters[name]) != types[name]: return "parameter_type:" + name
		if int(parameters[name]) < 0: return "parameter_range:" + name
	if message_id == &"hud.status.spawn_progress" and parameters.current > parameters.total: return "parameter_range:current"
	return ""

static func _expected_names(message_id: StringName) -> PackedStringArray:
	var names: PackedStringArray = []
	for name: String in PARAMETER_TYPES.get(message_id, {}): names.append(name)
	names.sort()
	return names

static func _placeholders(template: String) -> PackedStringArray:
	var names: PackedStringArray = []
	var expression: RegEx = RegEx.create_from_string("\\{([^{}]+)\\}")
	var remaining: String = template
	for match_result: RegExMatch in expression.search_all(template):
		var name: String = match_result.get_string(1)
		if not names.has(name): names.append(name)
		remaining = remaining.replace(match_result.get_string(), "")
	if remaining.contains("{") or remaining.contains("}"): names.append("!invalid_braces")
	names.sort()
	return names
