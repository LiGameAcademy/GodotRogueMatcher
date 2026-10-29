extends GutTest

## Ensures retained resources parse without changing their historical configuration.
func test_retained_effects_match_original_serialized_intent() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/support/web_export_legacy_intent.json"))
	assert_true(parsed is Dictionary)
	var expected: Dictionary = parsed as Dictionary
	assert_eq(expected.size(), 8)
	for name: String in expected:
		var config: ItemEffectConfig = load("res://data/item/effects/%s.tres" % name) as ItemEffectConfig
		assert_not_null(config, name)
		if config == null: continue
		for category: String in ["effects", "conditions"]:
			var actual: Array = config.get(category)
			var entries: Array = expected[name][category]
			assert_eq(actual.size(), entries.size(), name + ":" + category)
			for index: int in range(mini(actual.size(), entries.size())):
				var resource: Resource = actual[index] as Resource
				assert_not_null(resource)
				if resource == null: continue
				assert_eq((resource.get_script() as Script).resource_path, entries[index].script)
				for key: String in entries[index].parameters:
					var actual_value: Variant = resource.get(key)
					var expected_value: Variant = entries[index].parameters[key]
					if actual_value is int or actual_value is float:
						assert_eq(float(actual_value), float(expected_value), name + ":" + key)
					else:
						assert_eq(actual_value, expected_value, name + ":" + key)

func test_screening_type_moved_with_same_identity_and_profiles_stay_tool_only() -> void:
	var script: Script = load("res://gameplay/skills/debug/screening_config.gd") as Script
	assert_eq(script.get_global_name(), &"ScreeningConfig")
	assert_eq(ResourceLoader.get_resource_uid(script.resource_path), ResourceUID.text_to_id("uid://c48mymffeh848"))
	assert_false(FileAccess.file_exists("res://tools/screening_playground/screening_config.gd"))
	for key: String in ScreeningDeck.CONFIGS:
		var config: ScreeningConfig = ScreeningDeck.config(key)
		assert_not_null(config)
		assert_eq((config.get_script() as Script).resource_path, script.resource_path)
		assert_eq(config.seed_value, 119)
		assert_eq(config.action_limit, 15)
		assert_eq(config.time_limit_seconds, 480)
		assert_true(config.resource_path.begins_with("res://tools/"))

func test_legacy_popup_and_real_game_scene_instantiate() -> void:
	var popup: Control = (load("res://ui/popup_level_up.tscn") as PackedScene).instantiate() as Control
	assert_not_null(popup)
	popup.free()
	var game: Node2D = (load("res://gameplay/game.tscn") as PackedScene).instantiate() as Node2D
	assert_not_null(game)
	game.free()
