class_name RunAnalysis
extends RefCounted

var runs: Array[Dictionary] = []
var turns: Array[Dictionary] = []
var rewards: Array[Dictionary] = []
var error: String = ""

func add(records: Array[Dictionary], replay_error: String = "") -> void:
	if records.is_empty(): return
	var header: Dictionary = records[0]
	var base: Dictionary = {"run_id": header.run_id, "source": header.source, "rules_version": header.rules_version, "strategy": header.get("metadata", {}).get("strategy", "human"), "config_hash": header.config_hash}
	base["mode_id"] = header.get("config", {}).get("mode_id", "unknown")
	base.merge({"seed": header.seed, "content_version": header.content_version, "offer_version": header.offer_version, "build": header.build, "bot_config_hash": RunSnapshot.digest(header.get("metadata", {}).get("bot_config", {}))})
	var reward_rows: Dictionary = {}
	var choices: Dictionary = {}
	var last_reward_move: int = 0
	var move_before: Dictionary = {}
	var last_move_command: Dictionary = {}
	for record: Dictionary in records:
		match record.kind:
			"CommandAttempt":
				if record.accepted and record.command.type in ["move", "detonate"]: last_move_command = record.command
			"Offer":
				for id: String in record.offer.choices:
					var row: Dictionary = base.duplicate()
					row.merge({"offer_id": record.offer.offer_id, "reward_id": record.offer.reward_id, "skill_id": id, "selected": false, "score": "", "move": "", "moves_since_reward": "", "immediate_score": "", "net_empty": ""})
					rewards.append(row)
					reward_rows[record.offer.offer_id + ":" + id] = row
			"SkillAcquired": choices[record.command_id] = record
			"Checkpoint":
				var offer: Dictionary = record.state.get("offer", {})
				if not offer.is_empty():
					for id: String in offer.choices:
						var key: String = offer.offer_id + ":" + id
						if reward_rows.has(key) and reward_rows[key].score == "":
							reward_rows[key].score = record.state.total
							reward_rows[key].move = record.state.moves
			"RuleResult":
				if record.has("before"):
					if record.has("command_id") and choices.has(record.command_id):
						var acquisition: Dictionary = choices[record.command_id]
						var key: String = acquisition.offer_id + ":" + acquisition.skill_id
						if reward_rows.has(key):
							var row: Dictionary = reward_rows[key]
							var move_number: int = record.after.moves.to_int()
							row.merge({"selected": true, "score": record.after.total, "move": record.after.moves, "moves_since_reward": str(move_number - last_reward_move), "immediate_score": str(record.after.total.to_int() - record.before.total.to_int()), "net_empty": str(record.before.pieces.size() - record.after.pieces.size())}, true)
							last_reward_move = move_number
					elif _actions(record.after) > _actions(record.before): move_before = record.before
				elif record.get("stage") == "input" and not move_before.is_empty():
					_add_turn(base, move_before, record.after, last_move_command)
					move_before = {}
			"Footer":
				if not move_before.is_empty(): _add_turn(base, move_before, record.final, last_move_command)
				var row: Dictionary = base.duplicate()
				row.merge({"status": record.status, "reason": record.reason, "score": record.score, "moves": record.moves, "activations": record.get("activations", "0"), "actions": record.get("actions", record.moves), "choices": record.choices, "replay_error": replay_error, "record_complete": record.record_complete, "robot_compute_ms": record.times.robot_compute})
				for bucket: String in ["pause", "choice", "busy", "input", "buffer_wait"]: row[bucket + "_ms"] = record.times.get(bucket, "")
				runs.append(row)

func _add_turn(base: Dictionary, before: Dictionary, after: Dictionary, command: Dictionary) -> void:
	var row: Dictionary = base.duplicate()
	row.merge({"command_id": command.get("command_id", ""), "move": after.moves, "actions": str(_actions(after)), "command_type": command.get("type", "move"), "score_before": before.total, "score_after": after.total, "occupied_before": str(before.pieces.size()), "occupied_after": str(after.pieces.size()), "choices_after": after.consumed})
	turns.append(row)

func write(directory: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		error = "cannot_create_report_directory"
		return false
	if not _csv(directory.path_join("runs.csv"), runs) or not _csv(directory.path_join("turns.csv"), turns) or not _csv(directory.path_join("rewards.csv"), rewards, ["run_id", "source", "strategy", "offer_id", "reward_id", "skill_id", "selected", "score", "move"]): return false
	var groups: Dictionary = {}
	for row: Dictionary in runs:
		var key: String = "%s/%s/%s/%s/%s" % [row.source, row.strategy, row.bot_config_hash, row.config_hash, row.status]
		if not groups.has(key): groups[key] = []
		groups[key].append(row)
	var summary: Dictionary = {"schema": "bot-report-v1", "runs": runs.size(), "groups": {}}
	for key: String in groups:
		var scores: Array[int] = []
		var moves: Array[int] = []
		var reached: Array[int] = [0, 0, 0]
		var reasons: Dictionary = {}
		var replay_failures: int = 0
		var extremes: Array[Dictionary] = []
		for row: Dictionary in groups[key]:
			scores.append(row.score.to_int())
			moves.append(row.moves.to_int())
			reasons[row.reason] = reasons.get(row.reason, 0) + 1
			if not row.replay_error.is_empty(): replay_failures += 1
			extremes.append({"run_id": row.run_id, "score": row.score.to_int(), "moves": row.moves.to_int()})
			for index: int in range(3):
				if row.choices.to_int() >= index + 8: reached[index] += 1
		scores.sort()
		moves.sort()
		extremes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score < b.score)
		var rates: Array[float] = []
		for count: int in reached: rates.append(float(count) / scores.size())
		summary.groups[key] = {"count": scores.size(), "score_p10_p50_p90": _quantiles(scores), "moves_p10_p50_p90": _quantiles(moves), "reached_8_9_10": reached, "reached_8_9_10_rates": rates, "reasons": reasons, "replay_failures": replay_failures, "lowest": extremes.front(), "highest": extremes.back()}
	var skill_counts: Dictionary = {}
	for row: Dictionary in rewards:
		var key: String = "%s/%s/%s/%s" % [row.source, row.strategy, row.config_hash, row.skill_id]
		if not skill_counts.has(key): skill_counts[key] = {"offered": 0, "selected": 0}
		skill_counts[key].offered += 1
		if row.selected: skill_counts[key].selected += 1
	for key: String in skill_counts:
		skill_counts[key]["conditional_selection_rate"] = float(skill_counts[key].selected) / skill_counts[key].offered
	summary["skills"] = skill_counts
	var file: FileAccess = FileAccess.open(directory.path_join("summary.json"), FileAccess.WRITE)
	if file == null:
		error = "cannot_write_summary"
		return false
	file.store_string(JSON.stringify(summary, "\t", true))
	file.flush()
	return file.get_error() == OK

func _quantiles(values: Array[int]) -> Array[int]:
	var result: Array[int] = []
	for fraction: float in [0.1, 0.5, 0.9]: result.append(values[mini(values.size() - 1, int(floor(fraction * (values.size() - 1))))])
	return result

func _csv(path: String, rows: Array[Dictionary], empty_keys: PackedStringArray = ["run_id"]) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		error = "cannot_write_csv: " + path
		return false
	if not rows.is_empty():
		var keys: PackedStringArray = PackedStringArray(rows[0].keys())
		file.store_csv_line(keys)
		for row: Dictionary in rows:
			var values: PackedStringArray = []
			for key: String in keys: values.append(str(row.get(key, "")))
			file.store_csv_line(values)
	else: file.store_csv_line(empty_keys)
	file.flush()
	return file.get_error() == OK

func _actions(snapshot: Dictionary) -> int:
	return snapshot.moves.to_int() + str(snapshot.get("demolition", {}).get("activations", "0")).to_int()
