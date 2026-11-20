class_name OfferRarityStep
extends Resource

## Read-only step in the successful-choice-index curve. Unconfigured curves stay flat.
@export var first_choice: int = 1
@export var weights: Array[float] = [1.0, 0.65, 0.35, 0.15, 0.06]
