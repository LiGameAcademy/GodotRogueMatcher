class_name StageState
extends RefCounted

## 唯一阶段状态；不依赖界面、时间或随机数。
const SCORE_REASONS: Array[StringName] = [&"match", &"explosion", &"chain_reward", &"marked_reward"]
var config: StageConfig
var index: int = 0
var carry_in: int = 0
var action_score: int = 0
var used_actions: int = 0
var awaiting_reward: bool = false
var root_action_id: int = 0
var settled_root_id: int = 0
var entry_offset: int = 0
var history: Array[StageResult] = []

func _init(stage_config: StageConfig = null) -> void:
	config = stage_config

func enabled() -> bool:
	return config != null

func target() -> int:
	return config.targets[index]

func action_limit() -> int:
	return config.action_limits[index]

func remaining_actions() -> int:
	return maxi(0, action_limit() - used_actions)

func missing_score() -> int:
	return maxi(0, target() - carry_in - action_score)

func can_act() -> bool:
	return not awaiting_reward and remaining_actions() > 0 and (history.is_empty() or history.back().stage_id <= index)

func begin_action(root_id: int, offset: int) -> void:
	if not enabled() or root_id == root_action_id: return
	root_action_id = root_id
	entry_offset = offset
	used_actions += 1

## 只归因当前已接受根行动，初始化/即时选卡/调试注分均不计阶段分。
func settle(entries: Array[ScoreEntry], board_full: bool, next_reward_id: int) -> StageResult:
	if not enabled() or root_action_id == 0 or root_action_id == settled_root_id: return null
	settled_root_id = root_action_id
	for offset: int in range(entry_offset, entries.size()):
		var entry: ScoreEntry = entries[offset]
		if entry.root_action_id == root_action_id and entry.reason in SCORE_REASONS: action_score += entry.final_score
	var reason: StringName = &""
	if board_full: reason = &"board_full"
	elif missing_score() == 0: reason = &"challenge_completed" if index == config.targets.size() - 1 else &"stage_passed"
	elif remaining_actions() == 0: reason = &"stage_target_missed"
	if reason.is_empty(): return null
	var result: StageResult = StageResult.new()
	result.stage_id = index + 1
	result.target = target()
	result.action_limit = action_limit()
	result.carry_in = carry_in
	result.action_score = action_score
	result.used_actions = used_actions
	result.root_action_id = root_action_id
	result.reason = reason
	if reason in [&"stage_passed", &"challenge_completed"]:
		result.carry_out = maxi(0, carry_in + action_score - target())
		result.passed_by = &"carry" if carry_in >= target() else &"action"
	if reason == &"stage_passed":
		result.reward_id = next_reward_id
		awaiting_reward = true
	history.append(result)
	return result

func start_next() -> void:
	if not awaiting_reward: return
	carry_in = history.back().carry_out
	index += 1
	action_score = 0
	used_actions = 0
	awaiting_reward = false

func data() -> Dictionary:
	var results: Array[Dictionary] = []
	for result: StageResult in history: results.append(result.data())
	return {"enabled": enabled(), "index": index, "carry_in": carry_in, "action_score": action_score, "used_actions": used_actions, "awaiting_reward": awaiting_reward, "root_action_id": root_action_id, "settled_root_id": settled_root_id, "entry_offset": entry_offset, "history": results}
