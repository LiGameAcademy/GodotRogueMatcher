class_name DemolitionDemo
extends RefCounted

## 主动爆破/供给/连锁的确定性回放盘面；不用于正常初始化。
static func populate(run: RunController) -> void:
	run.state.explosion.core_pool_unlocked = true
	run.state.explosion.fuse_unlocked = true
	run.state.rewards.acquired[&"core_drop"] = 1
	for id: StringName in [&"core_manual_detonation", &"core_fuse_payload", &"chain_reward", &"blast_aftershock", &"blast_chain_bonus", &"blast_refill_relief"]:
		run.state.explosion.upgrades[id] = 1
		run.state.rewards.acquired[id] = 1
	run.state.explosion.reward_level = 1
	run.state.explosion.radius_level = 1
	run.state.rewards.acquired[&"blast_reward"] = 1
	run.state.rewards.acquired[&"blast_radius"] = 1
	run.abilities.add_core(Vector2i(4, 4))
	for x: int in range(3, 6):
		for y: int in range(3, 6):
			if Vector2i(x, y) == Vector2i(4, 4): continue
			run.state.rules.place_piece(Vector2i(x, y), posmod(x + 2 * y, 5))
	var fuse: PieceState = run.state.rules.place_piece(Vector2i(6, 4), 0)
	run.abilities.assign_fuse(fuse.piece_id)
	run.state.rules.place_piece(Vector2i(7, 4), 2)
