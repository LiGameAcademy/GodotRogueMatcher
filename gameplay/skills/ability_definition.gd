class_name AbilityDefinition
extends Resource

## Unique ability id.
@export var ability_id: StringName = &""
## Explicit timing; conditions only query value context and never own run counts.
@export var event_type: StringName = &""
## Extra trigger conditions; an empty array means no additional limits.
@export var conditions: Array[TriggerCondition] = []
## Maximum trigger count; 0 means unlimited.
@export var max_triggers: int = 0
## Whether a legal empty result consumes a charge; removal blasts keep the existing policy.
@export var consume_on_empty: bool = true
## Effect root (ChoiceEffect, ExplodeEffect, or CompositeEffect). Load-time type checks apply.
@export var effect: Resource
