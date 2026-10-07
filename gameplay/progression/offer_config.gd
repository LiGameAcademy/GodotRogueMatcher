class_name OfferConfig
extends Resource

@export var rarity_factors: Array[float] = [1.0, 0.65, 0.35, 0.15, 0.06]

@export var affinity_gain: float = 0.6
@export var need_factor: float = 1.4
@export var history_factor: float = 0.75
@export var repeat_factor: float = 0.8
@export var factor_min: float = 0.5
@export var factor_max: float = 4.0
@export var related_probability: float = 0.75
@export var explore_probability: float = 0.6
@export var rules_version: String = "offer-v0.1"
@export var profile_id: StringName = &"prototype_explosion"
