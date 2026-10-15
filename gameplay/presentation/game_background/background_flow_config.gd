class_name BackgroundFlowConfig
extends Resource

## Read-only visual tuning. No gameplay timing or random stream is consumed.
@export_range(0.0, 0.3) var contrast: float = 0.08
@export_range(0.0, 0.5) var speed: float = 0.10
@export_range(0.0, 0.1) var score_response: float = 0.025
@export_range(0.1, 5.0) var response_seconds: float = 1.6
@export_range(1.0, 1000.0) var reference_score: float = 150.0
