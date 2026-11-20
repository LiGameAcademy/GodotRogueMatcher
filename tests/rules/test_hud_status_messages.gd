extends GutTest

## Verifies exact-language catalog failures and named parameter formatting without UI.
var messages: HudStatusMessages
var diagnostics: Array[Dictionary] = []

func before_each() -> void:
	messages = HudStatusMessages.new()
	diagnostics.clear()
	messages.diagnostic.connect(_diagnostic)

func test_actual_imported_catalog_is_complete_in_both_languages() -> void:
	assert_eq(HudStatusMessages.catalog_errors(), PackedStringArray())
	for suffix: StringName in HudStatusMessages.IDS:
		var id: StringName = StringName("hud.status." + String(suffix))
		var parameters: Dictionary = {}
		if suffix == &"spawn_progress": parameters = {"current": 1, "total": 3}
		if suffix == &"capture_refill_used": parameters = {"count": 1}
		var english: String = messages.render(id, parameters, "en_US")
		assert_false(english.contains("hud.status."), id)
		assert_false(english.contains("{"), id)
		assert_null(RegEx.create_from_string("[\\x{4e00}-\\x{9fff}]").search(english), id)
		assert_false(messages.render(id, parameters, "zh_CN").is_empty(), id)
	assert_eq(diagnostics.size(), 0)

func test_numbers_boundaries_and_locale_specific_punctuation() -> void:
	for count: int in [0, 1, 3, 9223372036854775807]:
		assert_eq(messages.render(&"hud.status.spawn_progress", {"current": count, "total": count}, "en_US"), "Spawning pieces: %d/%d" % [count, count])
	assert_eq(messages.render(&"hud.status.spawn_progress", {"current": 1, "total": 3}, "zh_CN"), "正在补棋：1/3")
	assert_eq(messages.render(&"hud.status.preparing", {}, "en_US"), "Preparing board…")

func test_unknown_id_missing_wrong_extra_and_invalid_parameters_fail_closed() -> void:
	for parameters: Dictionary in [{}, {"current": 1}, {"current": "1", "total": 3}, {"current": 1.0, "total": 3}, {"current": -1, "total": 3}, {"current": 4, "total": 3}, {"current": 1, "total": 3, "extra": 0}]:
		assert_eq(messages.render(&"hud.status.spawn_progress", parameters, "en_US"), "Status message unavailable")
	assert_eq(messages.render(&"unknown", {}, "en_US"), "Status message unavailable")
	assert_eq(messages.render(&"已暂停", {}, "en_US"), "Status message unavailable")
	assert_gt(diagnostics.size(), 0)
	var count: int = diagnostics.size()
	messages.render(&"unknown", {}, "en_US")
	assert_eq(diagnostics.size(), count, "same diagnostic is deduplicated")

func test_missing_translation_does_not_fall_back_to_chinese_or_raw_id() -> void:
	var corrupt: HudStatusMessages = HudStatusMessages.new(func(id: StringName, locale: String) -> String:
		if locale == "zh_CN": return "中文"
		return "Status message unavailable" if id == &"hud.status.unavailable" else ""
	)
	assert_eq(corrupt.render(&"hud.status.ready", {}, "en_US"), "Status message unavailable")
	assert_eq(messages.render(&"hud.status.ready", {}, "fr_FR"), "—")
	assert_eq(diagnostics.size(), 2, "missing current translation and missing fallback are distinct")
	var raw_keys: HudStatusMessages = HudStatusMessages.new(func(id: StringName, _locale: String) -> String: return String(id))
	assert_eq(raw_keys.render(&"hud.status.ready", {}, "en_US"), "—", "raw ID is not a translated template or fallback")

func test_reordered_repeated_placeholders_and_special_characters() -> void:
	var custom: HudStatusMessages = HudStatusMessages.new(func(_id: StringName, _locale: String) -> String:
		return "100% … {total}/{current} · {current}"
	)
	assert_eq(custom.render(&"hud.status.spawn_progress", {"current": 1, "total": 3}, "en_US"), "100% … 3/1 · 1")
	for template: String in ["{current}", "{current}/{total}/{other}", "{current}/{total} {", "{current}/{total} }"]:
		var corrupt: HudStatusMessages = HudStatusMessages.new(func(id: StringName, _locale: String) -> String:
			return "Unavailable" if id == &"hud.status.unavailable" else template
		)
		assert_eq(corrupt.render(&"hud.status.spawn_progress", {"current": 1, "total": 3}, "en_US"), "Unavailable")

func _diagnostic(id: StringName, locale: String, reason: String, parameters: Dictionary) -> void:
	diagnostics.append({"id": id, "locale": locale, "reason": reason, "parameters": parameters})
