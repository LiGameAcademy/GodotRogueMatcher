extends Node

## Reuse real Game fixtures; only observe audio cues and committed run results.
const FIXTURE: Script = preload("res://tools/aesthetic_acceptance/aesthetic_acceptance.gd")
const OUTPUT: String = "res://.godot/issue130-audio-validation/captures"
const SCORES: Dictionary[String, int] = {"match": 50, "blast_row": 61, "row_blast": 16}
@onready var fixture: FIXTURE = $AestheticAcceptance

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().title = "技能连珠 · 音效接入验收（#130）"
	while fixture.loading: await get_tree().process_frame
	if "--capture-audio" in OS.get_cmdline_user_args(): await _capture_suite()

func _observe(cue: StringName, cues: Array[StringName]) -> void:
	cues.append(cue)

func _capture_suite() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var baseline: Dictionary[String, String] = {}
	var records: Array[Dictionary] = []
	var passed: bool = true
	for reduced: bool in [false, true]:
		for accelerated: bool in [false, true]:
			fixture.low = reduced
			fixture.fast = accelerated
			for key: String in SCORES:
				await fixture.load_case(key)
				var cues: Array[StringName] = []
				var feedback: GameFeedback = fixture.game.get_node("GameFeedback") as GameFeedback
				feedback.cue_played.connect(_observe.bind(cues))
				await fixture.play_case()
				var digest: String = RunSnapshot.digest(RunSnapshot.capture(fixture.board.run))
				if not baseline.has(key): baseline[key] = digest
				var required: Array[StringName] = [&"land", &"match"]
				if key != "match": required.assign([&"blast", &"sweep"])
				var cues_valid: bool = true
				for cue: StringName in required: cues_valid = cues_valid and cues.has(cue)
				var valid: bool = cues_valid and GameManager.score == SCORES[key] and fixture.board.run.state.rule_error.is_empty() and digest == baseline[key]
				passed = passed and valid
				var record: Dictionary = {"case": key, "low": reduced, "fast": accelerated, "score": GameManager.score, "rule_error": fixture.board.run.state.rule_error, "snapshot": digest, "cues": cues, "cues_valid": cues_valid, "valid": valid}
				records.append(record)
				print("AUDIO_CASE ", JSON.stringify(record))
				fixture.panel.hide()
				for frame: int in range(3): await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var capture_error: Error = get_viewport().get_texture().get_image().save_png(OUTPUT.path_join("%s_low%d_fast%d.png" % [key, int(reduced), int(accelerated)]))
				if capture_error != OK:
					push_error(error_string(capture_error))
					passed = false
	var file: FileAccess = FileAccess.open(OUTPUT.path_join("results.json"), FileAccess.WRITE)
	if file == null:
		push_error("Cannot write audio acceptance results")
		passed = false
	else:
		file.store_string(JSON.stringify(records, "  ") + "\n")
		file.flush()
		if file.get_error() != OK:
			push_error("Cannot finish audio acceptance results")
			passed = false
	get_tree().paused = false
	UIManager.close_popup()
	get_tree().quit(0 if passed else 1)
