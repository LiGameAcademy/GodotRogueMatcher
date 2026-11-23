extends GutTest

## Probes the pinned AudioManager on successful application handoffs with temporary tones.
const FADE_SECONDS: float = 2.0
const TIMEOUT_SECONDS: float = 10.0

var _host: Node
var _directory: String
var _tracks: Dictionary[String, String] = {}
var _arrivals: Array[String] = []
var _voices_at_arrival: Array[int] = []
var _old_master: float
var _music: CoreSystem.AudioManager

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_host = get_tree().current_scene
	_directory = "user://music-probe-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	assert_eq(DirAccess.make_dir_recursive_absolute(_directory), OK)
	_tracks = {GameFlow.ROOM: _directory.path_join("room.res"), GameFlow.GAME: _directory.path_join("play.res")}
	_write_track(_tracks[GameFlow.ROOM], 220.0)
	_write_track(_tracks[GameFlow.GAME], 330.0)
	_arrivals.clear()
	_voices_at_arrival.clear()
	_music = CoreSystem.audio_manager
	_old_master = _music.get_master_volume()
	get_tree().paused = false
	GameFlow.machine = CoreStateMachine.new(GameFlow.Page.BOOT, [0, 1, 2, 3], GameFlow._allowed)
	CoreSystem.scene_manager.scene_changed.connect(_scene_arrived)

func after_each() -> void:
	CoreSystem.scene_manager.scene_changed.disconnect(_scene_arrived)
	_music.stop_all()
	_music.set_master_volume(_old_master)
	var active: Node = get_tree().current_scene
	get_tree().current_scene = _host
	if active != _host and is_instance_valid(active): active.queue_free()
	UIManager.close_popup()
	get_tree().paused = false
	# Let the plugin release pending tweens before reusing its player pool.
	await get_tree().create_timer(FADE_SECONDS + 0.1).timeout
	var cache: Dictionary = _music.get("_audio_cache")
	for path: String in _tracks.values():
		cache.erase(path)
		DirAccess.remove_absolute(path)
	var slot: String = _directory.path_join("slot")
	for file: String in DirAccess.get_files_at(slot):
		DirAccess.remove_absolute(slot.path_join(file))
	if DirAccess.dir_exists_absolute(slot): DirAccess.remove_absolute(slot)
	DirAccess.remove_absolute(_directory)

func test_fast_real_round_trip_releases_old_music_players() -> void:
	var room: Node = await _enter_room()
	if room == null: return
	await _wait_for_solo(GameFlow.ROOM)
	_start_classic(room)
	await wait_until(_is_playing, TIMEOUT_SECONDS)
	if not _is_playing(): return
	assert_eq(_music_stream_path(), _tracks[GameFlow.GAME])
	get_tree().current_scene.call("_return_to_room")
	await wait_until(_is_room_ready, TIMEOUT_SECONDS)
	if not _is_room_ready(): return
	room = get_tree().current_scene
	_press(room, "Continue")
	await wait_until(_is_playing, TIMEOUT_SECONDS)
	if not _is_playing(): return
	assert_eq(_arrivals, [GameFlow.ROOM, GameFlow.GAME, GameFlow.ROOM, GameFlow.GAME])
	assert_true(_voices_at_arrival.size() == 4 and _voices_at_arrival[2] > 1, "returned while at least one prior track was still playing")
	await _wait_for_solo(GameFlow.GAME)
	assert_eq(_playing_music_paths(), [_tracks[GameFlow.GAME]])
	gut.p("Music players by handoff: %s" % [_voices_at_arrival])

func test_failed_handoffs_keep_music_and_retry_respects_mute_and_cues() -> void:
	var room: Node = await _enter_room()
	if room == null: return
	await _wait_for_solo(GameFlow.ROOM)
	var old_player: AudioStreamPlayer = _music.get("_current_music") as AudioStreamPlayer
	var cached: Dictionary = CoreSystem.resource_manager.get("_resource_cache")
	var previous: Variant = cached.get(GameFlow.GAME)
	cached[GameFlow.GAME] = Resource.new()
	_start_classic(room)
	if previous == null: cached.erase(GameFlow.GAME)
	else: cached[GameFlow.GAME] = previous
	assert_push_error("Failed to load scene")
	assert_same(get_tree().current_scene, room)
	assert_false(bool(room.get("_departing")))
	assert_eq(_arrivals, [GameFlow.ROOM])
	assert_same(_music.get("_current_music"), old_player)
	assert_eq(_playing_music_paths(), [_tracks[GameFlow.ROOM]])

	_start_classic(room)
	await wait_until(_is_playing, TIMEOUT_SECONDS)
	if not _is_playing(): return
	var game: Node = get_tree().current_scene
	var settings: PlaybackSettings = game.get_node("PlaybackSettings") as PlaybackSettings
	var feedback: GameFeedback = game.get_node("GameFeedback") as GameFeedback
	var current: AudioStreamPlayer = _music.get("_current_music") as AudioStreamPlayer
	var master_bus: int = AudioServer.get_bus_index(&"Master")
	settings.volume_requested.emit(0.0)
	assert_eq(_music.get_master_volume(), 0.0)
	assert_eq(db_to_linear(AudioServer.get_bus_volume_db(master_bus)), 0.0)
	assert_true(current.playing)
	watch_signals(feedback)
	feedback.play(&"select")
	assert_signal_not_emitted(feedback, "cue_played")
	await _wait_for_solo(GameFlow.GAME)
	assert_eq(db_to_linear(AudioServer.get_bus_volume_db(master_bus)), 0.0)
	settings.volume_requested.emit(0.35)
	assert_almost_eq(db_to_linear(AudioServer.get_bus_volume_db(master_bus)), 0.35, 0.0001)
	feedback.play(&"select")
	assert_signal_emitted_with_parameters(feedback, "cue_played", [&"select"])
	assert_same(_music.get("_current_music"), current)
	assert_eq(_playing_music_paths(), [_tracks[GameFlow.GAME]])

	previous = cached.get(GameFlow.ROOM)
	cached[GameFlow.ROOM] = Resource.new()
	game.call("_return_to_room")
	if previous == null: cached.erase(GameFlow.ROOM)
	else: cached[GameFlow.ROOM] = previous
	assert_push_error("Failed to load scene")
	assert_same(get_tree().current_scene, game)
	assert_eq(_arrivals, [GameFlow.ROOM, GameFlow.GAME])
	assert_same(_music.get("_current_music"), current)
	var checkpoint: GameCheckpointFlow = game.get_node("GameCheckpointFlow") as GameCheckpointFlow
	checkpoint.prompt.action_requested.emit(&"retry")
	await wait_until(_is_room_ready, TIMEOUT_SECONDS)
	await _wait_for_solo(GameFlow.ROOM)
	assert_eq(_arrivals, [GameFlow.ROOM, GameFlow.GAME, GameFlow.ROOM])

func _enter_room() -> Node:
	var placeholder: Node = Node.new()
	get_tree().root.add_child(placeholder)
	get_tree().current_scene = placeholder
	assert_true(GameFlow.travel(GameFlow.Page.ROOM, {"directory": _directory.path_join("slot")}))
	await wait_until(_is_room_ready, TIMEOUT_SECONDS)
	return get_tree().current_scene if _is_room_ready() else null

func _start_classic(room: Node) -> void:
	var mode: OptionButton = room.get_node("%Mode") as OptionButton
	mode.select(GameModes.ALL.find(GameModes.CLASSIC))
	_press(room, "New")

func _press(room: Node, button: String) -> void:
	(room.get_node("%" + button) as Button).pressed.emit()

func _is_room_ready() -> bool:
	var active: Node = get_tree().current_scene
	return is_instance_valid(active) and active.scene_file_path == GameFlow.ROOM and active.get("_loaded") == true

func _is_playing() -> bool:
	var active: Node = get_tree().current_scene
	return is_instance_valid(active) and active.scene_file_path == GameFlow.GAME and active.get("_has_played") == true

func _scene_arrived(_old: Node, scene: Node) -> void:
	if not _tracks.has(scene.scene_file_path): return
	_arrivals.append(scene.scene_file_path)
	_music.play_music(_tracks[scene.scene_file_path], FADE_SECONDS)
	var player: AudioStreamPlayer = _music.get("_current_music") as AudioStreamPlayer
	assert_not_null(player)
	if player != null: assert_eq(player.volume_db, -80.0, "incoming music starts at the fade floor")
	_voices_at_arrival.append(_playing_music_paths().size())

func _wait_for_solo(scene_path: String) -> void:
	await wait_until(_is_solo.bind(scene_path), TIMEOUT_SECONDS)

func _is_solo(scene_path: String) -> bool:
	var player: AudioStreamPlayer = _music.get("_current_music") as AudioStreamPlayer
	return player != null and is_zero_approx(player.volume_db) and _playing_music_paths() == [_tracks[scene_path]]

func _music_stream_path() -> String:
	var player: AudioStreamPlayer = _music.get("_current_music") as AudioStreamPlayer
	return player.stream.resource_path if is_instance_valid(player) and player.stream != null else ""

func _playing_music_paths() -> Array[String]:
	var paths: Array[String] = []
	for child: Node in _music.get_children():
		var player: AudioStreamPlayer = child as AudioStreamPlayer
		if player != null and player.bus == &"Music" and player.playing and player.stream != null:
			paths.append(player.stream.resource_path)
	return paths

func _write_track(path: String, frequency: float) -> void:
	var track: AudioStreamWAV = AudioStreamWAV.new()
	track.format = AudioStreamWAV.FORMAT_8_BITS
	track.mix_rate = 8000
	track.loop_mode = AudioStreamWAV.LOOP_FORWARD
	track.loop_end = 2000
	var samples: PackedByteArray = PackedByteArray()
	samples.resize(track.loop_end)
	for index: int in range(samples.size()):
		var sample: int = roundi(sin(TAU * frequency * index / track.mix_rate) * 3.0)
		samples[index] = sample & 0xff
	track.data = samples
	assert_eq(ResourceSaver.save(track, path), OK)
