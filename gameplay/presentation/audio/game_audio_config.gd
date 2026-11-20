class_name GameAudioConfig
extends Resource

## Read-only sound paths and presentation parameters; no gameplay state.
@export var cue_paths: Dictionary[StringName, String] = {}
@export var match_variants: Array[String] = []
@export var match_pitch: PackedFloat32Array = PackedFloat32Array([1.0, 1.03, 1.06, 1.09])
@export_range(0.0, 1.0) var sfx_gain: float = 0.65
@export_range(1, 16) var max_voices: int = 6
@export var dedup_ms: int = 70
