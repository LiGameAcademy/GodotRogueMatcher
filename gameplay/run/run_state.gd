class_name RunState
extends RefCounted

enum Phase { INITIALIZING, INPUT, MOVING, REWARDS, TURN_END, SPAWNING, FINISHED, ERROR }

var rules: BoardRules
var ledger: ScoreLedger = ScoreLedger.new()
var random: RandomNumberGenerator = RandomNumberGenerator.new()
var phase: Phase = Phase.INITIALIZING
var turn_count: int = 0
var action_id: int = 0
var rule_action_id: int = -1
var activations: int = 0
var is_game_over: bool = false
var pending_rewards: int = 0
var rewards: RewardState
var spawn_history: Array[SpawnResult] = []
var explosion: ExplosionState = ExplosionState.new()
var rule_error: String = ""
var run_id: String = ""
var valid_moves: int = 0
var progression: ProgressionState
var spawning: SpawnState
var _initial_seed: int

func _init(board_rules: BoardRules, run_seed: int) -> void:
	rules = board_rules
	_initial_seed = run_seed
	random.seed = run_seed
	rewards = RewardState.new(run_seed)
	progression = ProgressionState.new(RunController.PROGRESSION)
	spawning = SpawnState.new(RunController.SPAWN_CONFIG, run_seed)

func reset_counters() -> void:
	ledger = ScoreLedger.new()
	turn_count = 0
	action_id = 0
	rule_action_id = -1
	activations = 0
	is_game_over = false
	pending_rewards = 0
	rewards = RewardState.new(_initial_seed)
	progression = ProgressionState.new(RunController.PROGRESSION)
	valid_moves = 0
	spawning = SpawnState.new(RunController.SPAWN_CONFIG, _initial_seed)
	spawn_history.clear()
	explosion = ExplosionState.new()
	rule_error = ""
	random.seed = _initial_seed
	phase = Phase.INITIALIZING
