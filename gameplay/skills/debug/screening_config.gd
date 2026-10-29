class_name ScreeningConfig
extends Resource

## Read-only screening configuration type required by the runtime fixture parser.
## Tool-only profiles remain outside the production catalog and Web export.

@export var config_id: StringName
@export var title: String
@export var template: MatchShapeTemplate
@export var seed_value: int = 119
@export var action_limit: int = 15
@export var time_limit_seconds: int = 480
