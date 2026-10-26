extends GutTest

const FEEDBACK: PackedScene = preload("res://gameplay/presentation/game_feedback.tscn")
const MUSIC: PackedScene = preload("res://gameplay/presentation/game_music.tscn")
const TEST_MUSIC: String = "res://addons/godot_core_system/examples/audio_demo/assets/music/bgm.ogg"
var feedback: GameFeedback

func before_each() -> void:
	get_tree().paused = false
	feedback = FEEDBACK.instantiate() as GameFeedback
	add_child_autofree(feedback)
	feedback.set_volume(0.7)

func after_each() -> void:
	get_tree().paused = false
	feedback.cancel()

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
