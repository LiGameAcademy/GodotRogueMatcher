class_name BoardSignalConfig
extends Resource

## Read-only board-only signal tuning; no coordinates or gameplay timing are changed.
@export_range(0.0, 0.1) var scan_strength: float = 0.03
@export_range(0.0, 0.5) var rim_strength: float = 0.2
@export_range(0.0, 0.2) var sweep_strength: float = 0.08
@export_range(0.0, 0.5) var sweep_speed: float = 0.1
@export_range(0.0, 0.2) var response_strength: float = 0.06
@export_range(0.1, 3.0) var response_seconds: float = 0.9
