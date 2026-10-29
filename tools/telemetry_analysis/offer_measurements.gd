extends RefCounted

## Keeps displayed/generated opportunities distinct from legal-pool diagnostics.
## Replaced groups share their reward opportunity; missing legacy explanations remain unknown.
static func summarize(events: Array[Dictionary], group_key: Callable, dimensions: Callable) -> Dictionary:
	var generated: Dictionary[String, Dictionary] = {}
	var presented: Dictionary[String, bool] = {}
	var acquired: Dictionary[String, String] = {}
	var rewards: Dictionary[String, Dictionary] = {}
	var failed: int = 0
	var replaced: int = 0
	for event: Dictionary in events:
		var data: Dictionary = event.payload
		var offer_key: String = event.run_id + ":" + str(data.get("offer_id", ""))
		var reward_key: String = String(group_key.call(event)) + ":" + _reward(event)
		match event.event_name:
			"offer_generated":
				generated[offer_key] = event
				if not rewards.has(reward_key): rewards[reward_key] = {"presented": false, "acquired": false, "human": event.source == "human"}
				if str(data.get("replaces_offer_id", "0")) != "0": replaced += 1
			"offer_presented": presented[offer_key] = true
			"skill_acquired": acquired[reward_key] = str(data.skill_id)
			"command_resolved":
				if data.type == "choose" and not data.accepted: failed += 1
	var skills: Dictionary = {}
	var eligibility: Dictionary = {}
	var seen_generated: Dictionary[String, bool] = {}
	var seen_opportunities: Dictionary[String, bool] = {}
	var seen_eligibility: Dictionary[String, bool] = {}
	var observed_eligible: Dictionary[String, bool] = {}
	var legacy_unknown: int = 0
	for offer_key: String in generated:
		var event: Dictionary = generated[offer_key]
		var data: Dictionary = event.payload
		var group: String = String(group_key.call(event))
		var reward_key: String = group + ":" + _reward(event)
		var opportunity: bool = event.source == "bot" or (event.source in ["human", "fixture"] and presented.has(offer_key))
		if presented.has(offer_key): rewards[reward_key].presented = true
		if acquired.has(reward_key): rewards[reward_key].acquired = true
		for id: String in data.choices:
			var key: String = group + "/" + id
			if not skills.has(key): skills[key] = {"skill_id": id, "group": group, "dimensions": dimensions.call(event), "generated": 0, "opportunities": 0, "acquired": 0}
			var unique: String = key + ":" + _reward(event)
			if not seen_generated.has(unique):
				seen_generated[unique] = true
				skills[key].generated += 1
			if opportunity and not seen_opportunities.has(unique):
				seen_opportunities[unique] = true
				skills[key].opportunities += 1
				if acquired.get(reward_key) == id: skills[key].acquired += 1
		var explanations: Dictionary = data.get("explanations", {})
		if explanations.is_empty(): legacy_unknown += 1
		for id: String in explanations:
			var key: String = group + "/" + id
			if not eligibility.has(key): eligibility[key] = {"skill_id": id, "group": group, "dimensions": dimensions.call(event), "observed_rewards": 0, "legal_rewards": 0, "rejections": {}}
			var unique: String = key + ":" + _reward(event)
			if not seen_eligibility.has(unique):
				seen_eligibility[unique] = true
				eligibility[key].observed_rewards += 1
			var row: Dictionary = explanations[id]
			if row.H == "1" and not observed_eligible.has(unique):
				observed_eligible[unique] = true
				eligibility[key].legal_rewards += 1
			if row.H == "0": eligibility[key].rejections[row.rejection] = true
	for key: String in skills:
		var row: Dictionary = skills[key]
		row["conditional_selection_rate"] = float(row.acquired) / row.opportunities if row.opportunities > 0 else null
		row["legal_pool_rewards"] = eligibility[key].legal_rewards if eligibility.has(key) else null
		row["eligibility_rate"] = float(eligibility[key].legal_rewards) / eligibility[key].observed_rewards if eligibility.has(key) else null
	var unseen: int = 0
	var unconsumed: int = 0
	for row: Dictionary in rewards.values():
		if row.human and not row.presented: unseen += 1
		if row.presented and not row.acquired: unconsumed += 1
	return {"skills": skills, "eligibility": eligibility, "human_generated_not_presented": unseen,
		"presented_not_consumed": unconsumed, "failed_choices": failed, "replaced_groups": replaced,
		"legacy_groups_without_explanations": legacy_unknown, "eligibility_rate": null, "opportunity_protocol": "parent-run-reward-v1", "eligibility_scope": "generated_pool_diagnostics"}

static func _reward(event: Dictionary) -> String:
	var parent: String = str(event.get("parent_run_id")) if event.get("parent_run_id") != null else String(event.run_id)
	var reward: Variant = event.payload.get("reward_id", event.get("reward_id"))
	return parent + ":" + (str(reward) if reward != null else "offer:" + str(event.payload.get("offer_id", "")))
