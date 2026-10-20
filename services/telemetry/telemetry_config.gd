class_name TelemetryConfig
extends Resource

@export var local_directory: String = "user://telemetry"
@export var tool_roles: Dictionary[String, String] = {}
@export var heartbeat_seconds: float = 2.0
@export var maximum_queue_bytes: int = 4194304
@export var occupancy_weight: float = 0.7
@export var pressure_version: String = "pressure-observation-v1-alpha-0.7-trial"
