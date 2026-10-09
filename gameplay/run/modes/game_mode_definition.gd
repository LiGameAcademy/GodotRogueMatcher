class_name GameModeDefinition
extends Resource

## 本项目模式配置：只读规则选择，不保存本局状态。
@export var mode_id: StringName
@export var title: String
@export_multiline var description: String
@export var stage_config: StageConfig
