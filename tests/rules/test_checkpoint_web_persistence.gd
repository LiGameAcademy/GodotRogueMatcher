extends GutTest

const PERSISTENCE: Script = preload("res://services/run_checkpoint/checkpoint_web_persistence.gd")

func test_callback_keeps_opaque_text_and_explicit_failure_without_json_envelope() -> void:
	var backend: PERSISTENCE = PERSISTENCE.new()
	var received: Array[Dictionary] = []
	backend.completed.connect(func(result: Dictionary) -> void: received.append(result))
	var text: String = "中文\"\\\n".repeat(20000)
	backend._receive([true, "", text])
	assert_eq(received.back(), {"ok": true, "reason": "", "data": text})
	backend._receive([false, "web_storage_conflict", ""])
	assert_eq(received.back(), {"ok": false, "reason": "web_storage_conflict", "data": ""})

func test_callback_rejects_wrong_arity_types_and_legacy_json_envelopes() -> void:
	var backend: PERSISTENCE = PERSISTENCE.new()
	var received: Array[Dictionary] = []
	backend.completed.connect(func(result: Dictionary) -> void: received.append(result))
	var cases: Array[Array] = [[], [true, ""], [true, "", "", "extra"], ["true", "", ""], [true, false, ""], [true, "", null], [JSON.stringify({"ok": true, "reason": "", "data": ""})]]
	for arguments: Array in cases:
		backend._receive(arguments)
		assert_false(received.back().ok)
		assert_eq(received.back().reason, "web_backend_response_invalid")
