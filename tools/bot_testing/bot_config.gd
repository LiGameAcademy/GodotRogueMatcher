class_name BotConfig
extends Resource

@export var move_limit: int = 300
@export var command_limit: int = 3000
@export var timeout_ms: int = 60000
@export var match_priority: float = 10000.0
@export var line_potential_weight: float = 10.0
@export var congestion_penalty: float = 1.0
@export var dense_threshold: float = 0.65
@export var starter_weight: float = 100.0
@export var dense_thin_weight: float = 90.0
@export var skill_weights: Dictionary[StringName, float] = {&"blast_reward": 20.0, &"blast_radius": 18.0, &"score_multiplier": 12.0, &"match_extra": 10.0, &"assign_fuse": 15.0, &"core_drop": 16.0, &"blast_extra": 10.0, &"instant_thin": 5.0}
