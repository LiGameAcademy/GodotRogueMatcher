class_name DyeDemo
extends RefCounted

## 红五连下方放置差一枚的异色横线；一次移动可明确观察染色接续。
static func populate(run: RunController) -> void:
	var rules: BoardRules = run.state.rules
	run.state.dye.upgrades[&"match_dye_echo"] = 1
	run.state.dye.upgrades[&"dye_mark_reward"] = 1
	run.state.rewards.acquired[&"match_dye_echo"] = 1
	run.state.rewards.acquired[&"dye_mark_reward"] = 1
	for x: int in range(4): rules.place_piece(Vector2i(x, 4), 0)
	rules.place_piece(Vector2i(4, 6), 0)
	rules.place_piece(Vector2i(0, 3), 2)
	for x: int in range(1, 5): rules.place_piece(Vector2i(x, 3), 0)
	rules.place_piece(Vector2i(8, 8), 1)

