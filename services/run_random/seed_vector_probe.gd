extends Node

## Temporary Web/desktop probe for #161 portable vectors. Not a gameplay entry.
const VECTOR: Script = preload("res://services/run_random/seed_portable_vector.gd")

func _ready() -> void:
	var payload: Dictionary = VECTOR.build(42, 8)
	var text: String = JSON.stringify(payload)
	print("SEED_PORTABLE_VECTOR_BEGIN")
	print(text)
	print("SEED_PORTABLE_VECTOR_END")
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__SEED_PORTABLE_VECTOR__ = %s;" % text, true)
		JavaScriptBridge.eval("console.log('SEED_PORTABLE_VECTOR_READY');", true)
	else:
		get_tree().quit()
