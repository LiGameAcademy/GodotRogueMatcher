extends GutTest

const FEEDBACK: PackedScene = preload("res://gameplay/presentation/game_feedback.tscn")
const MUSIC: PackedScene = preload("res://gameplay/presentation/game_music.tscn")
const TEST_MUSIC: String = "res://addons/godot_core_system/examples/audio_demo/assets/music/bgm.ogg"
var feedback: GameFeedback
var _prepared_voice: AudioStreamPlayer
var _pool_mode: int
var _pool_pitch: float

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	feedback = FEEDBACK.instantiate() as GameFeedback
	add_child_autofree(feedback)
	feedback.set_volume(0.7)
	# Own a known idle slot for this test; preserve the prior suite's pool defaults.
	_prepared_voice = CoreSystem.audio_manager.play_sound(feedback.config.cue_paths[&"match"])
	_pool_mode = _prepared_voice.process_mode
	_pool_pitch = _prepared_voice.pitch_scale
	_prepared_voice.stop()
	_prepared_voice.process_mode = Node.PROCESS_MODE_INHERIT
	_prepared_voice.pitch_scale = 1.0

func after_each() -> void:
	get_tree().paused = false
	if is_instance_valid(feedback): feedback.cancel()
	if is_instance_valid(_prepared_voice):
		_prepared_voice.process_mode = _pool_mode
		_prepared_voice.pitch_scale = _pool_pitch

func test_all_public_cues_resolve_to_real_wav_files() -> void:
	assert_eq(feedback.config.cue_paths.size(), 11)
	var paths: Array[String] = feedback.config.cue_paths.values()
	paths.append_array(feedback.config.match_variants)
	for path: String in paths:
		assert_true(ResourceLoader.exists(path), path)
		var stream: AudioStreamWAV = load(path) as AudioStreamWAV
		assert_not_null(stream)
		assert_gt(stream.get_length(), 0.0)
	assert_ne(feedback.config.cue_paths[&"blast"], feedback.config.cue_paths[&"sweep"])

func test_match_pitch_caps_and_variants_alternate_without_rule_rng() -> void:
	feedback.play_match(99)
	var first: AudioStreamPlayer = feedback._players.front()
	assert_almost_eq(first.pitch_scale, 1.09, 0.0001)
	assert_eq(first.stream.resource_path, feedback.config.match_variants[0])
	await first.finished
	assert_eq(first.pitch_scale, 1.0)
	feedback.play_match(0)
	var second: AudioStreamPlayer = feedback._players.front()
	assert_eq(second.stream.resource_path, feedback.config.match_variants[1])
	assert_eq(second.pitch_scale, 1.0)
	feedback.cancel()
	assert_eq(second.pitch_scale, 1.0)
	assert_true(feedback._original_pitch.is_empty())

func test_paused_ui_cues_and_cancel_restore_pool_ownership() -> void:
	feedback.play(&"acquire")
	var player: AudioStreamPlayer = feedback._players.front()
	assert_eq(player.process_mode, Node.PROCESS_MODE_ALWAYS)
	feedback.cancel()
	assert_false(player.playing)
	assert_eq(player.process_mode, Node.PROCESS_MODE_INHERIT)
	assert_eq(player.pitch_scale, 1.0)

func test_missing_optional_music_is_silent_and_valid() -> void:
	var music: GameMusic = MUSIC.instantiate() as GameMusic
	music.local_path = "res://local_audio/does_not_exist.mp3"
	add_child_autofree(music)
	assert_false(music.start_optional())
	assert_null(music.stream)
	assert_false(music.playing)

func test_optional_music_loop_is_instance_local_and_scene_owned() -> void:
	var original: AudioStreamOggVorbis = load(TEST_MUSIC) as AudioStreamOggVorbis
	var loop_before: bool = original.loop
	var music: GameMusic = MUSIC.instantiate() as GameMusic
	music.local_path = TEST_MUSIC
	add_child_autofree(music)
	assert_true(music.playing)
	assert_eq(music.bus, &"Music")
	assert_not_same(music.stream, original)
	assert_true((music.stream as AudioStreamOggVorbis).loop)
	assert_eq(original.loop, loop_before)
	music.stop()
	assert_false(music.playing)

func test_actual_tree_pause_freezes_board_voice_but_keeps_reward_voice_live() -> void:
	feedback.play_match(2)
	var board_voice: AudioStreamPlayer = feedback._players.front()
	# Keep a live board voice across device startup; never edit the shared WAV.
	var looping: AudioStreamWAV = board_voice.stream.duplicate() as AudioStreamWAV
	looping.loop_mode = AudioStreamWAV.LOOP_FORWARD
	looping.loop_end = roundi(looping.get_length() * looping.mix_rate)
	board_voice.stream = looping
	board_voice.play()
	assert_true(board_voice.playing)
	get_tree().paused = true
	await wait_process_frames(2)
	assert_true(board_voice.stream_paused)
	feedback.play(&"acquire")
	var ui_voice: AudioStreamPlayer = feedback._players.back()
	assert_not_same(ui_voice, board_voice)
	assert_false(ui_voice.stream_paused)
	assert_true(ui_voice.playing)
	get_tree().paused = false
	await wait_process_frames(2)
	assert_false(board_voice.stream_paused)
	feedback.cancel()
	for voice: AudioStreamPlayer in [board_voice, ui_voice]:
		assert_false(voice.playing)
		assert_eq(voice.process_mode, Node.PROCESS_MODE_INHERIT)
		assert_eq(voice.pitch_scale, 1.0)

func test_retiring_feedback_returns_borrowed_voice_before_next_scene() -> void:
	feedback.play_match(3)
	var voice: AudioStreamPlayer = feedback._players.front()
	assert_almost_eq(voice.pitch_scale, 1.09, 0.0001)
	feedback.queue_free()
	await wait_process_frames(2)
	assert_false(voice.playing)
	assert_eq(voice.process_mode, Node.PROCESS_MODE_INHERIT)
	assert_eq(voice.pitch_scale, 1.0)
	feedback = FEEDBACK.instantiate() as GameFeedback
	add_child_autofree(feedback)
	feedback.play_match(0)
	var next_voice: AudioStreamPlayer = feedback._players.front()
	assert_eq(next_voice.pitch_scale, 1.0)
	assert_eq(next_voice.stream.resource_path, feedback.config.match_variants[0])

func test_paused_scene_voice_is_freed_after_natural_finish() -> void:
	get_tree().paused = true
	feedback.play(&"acquire")
	var voice: AudioStreamPlayer = feedback._players.front()
	assert_true(feedback._paused_players.has(voice))
	await voice.finished
	await wait_process_frames(2)
	assert_false(is_instance_valid(voice))
	assert_true(feedback._paused_players.is_empty())
	assert_true(feedback._players.is_empty())

func test_external_ogg_path_plays_without_changing_imported_template() -> void:
	var original: AudioStreamOggVorbis = load(TEST_MUSIC) as AudioStreamOggVorbis
	var original_loop: bool = original.loop
	var destination: String = ProjectSettings.globalize_path("user://external_music_fixture.ogg")
	var file: FileAccess = FileAccess.open(destination, FileAccess.WRITE)
	assert_not_null(file)
	if file == null: return
	file.store_buffer(FileAccess.get_file_as_bytes(TEST_MUSIC))
	file.close()
	var music: GameMusic = MUSIC.instantiate() as GameMusic
	music.local_path = destination
	add_child_autofree(music)
	assert_true(music.playing)
	assert_true((music.stream as AudioStreamOggVorbis).loop)
	assert_eq(original.loop, original_loop)
	music.stop()
	assert_eq(DirAccess.remove_absolute(destination), OK)
