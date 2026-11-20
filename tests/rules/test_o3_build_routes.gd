extends GutTest
## Guards the #122 route registry against catalog drift. Not a natural sampler or balance verdict.

func test_six_routes_keep_author_order_and_four_measures() -> void:
	assert_eq(O3BuildRoutes.ORDER, [&"B1", &"L1", &"B2", &"L2", &"M1", &"M2"])
	assert_eq(O3BuildRoutes.MEASURES, [&"startup", &"sustain", &"synergy", &"upgrade"])
	var table: Dictionary = O3BuildRoutes.routes()
	assert_eq(table.size(), O3BuildRoutes.ORDER.size())
	for route_id: StringName in O3BuildRoutes.ORDER:
		assert_true(table.has(route_id), String(route_id))
		var route: Dictionary = table[route_id]
		assert_false(String(route.title).is_empty(), String(route_id))
		assert_gt((route.engines as Array).size(), 0, String(route_id))
		assert_gt((route.growth as Array).size(), 0, String(route_id))
		assert_false(String(route.focus).is_empty(), String(route_id))
		assert_true(route.fixture in ["none", "partial", "line_clear_score", "fuse_chain", "cross_pair", "blast_starts_line", "line_starts_blast"], String(route_id))

func test_route_skills_exist_in_formal_catalog() -> void:
	var missing: Array[StringName] = O3BuildRoutes.catalog_missing()
	assert_eq(missing, [] as Array[StringName], "missing=%s" % str(missing))
	assert_eq(O3BuildRoutes.all_skill_ids().size(), 17)

func test_baseline_identity_matches_current_rules_and_offer() -> void:
	assert_eq(RunSnapshot.RULES_VERSION, "run-commands-v46-unified-offer-audit")
	assert_eq(SkillOfferGenerator.CONFIG.rules_version, "offer-unified-trial-v2")
	assert_eq(SkillOfferGenerator.CONFIG.related_gain, 0.25)
	assert_eq(SkillOfferGenerator.CONFIG.gap_gain, 0.25)
	assert_eq(SkillOfferGenerator.CONFIG.situational_gain, 0.0)
	assert_eq(SkillOfferGenerator.CONFIG.parameter_status, "trial_unvalidated")
	assert_eq(SkillOfferGenerator.CATALOG.size(), 52)
