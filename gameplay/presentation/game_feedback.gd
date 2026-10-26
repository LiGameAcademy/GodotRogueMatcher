class_name GameFeedback
extends Node

## 项目提示音适配器；播放使用插件池，音效长尾不加入演出屏障。
signal cue_played(cue: StringName)
@export var config: GameAudioConfig = preload("res://gameplay/presentation/audio/nut_audio.tres")
var _match_index: int = 0
var _original_pitch: Dictionary[AudioStreamPlayer, float] = {}
var _players: Array[AudioStreamPlayer] = []
var _original_modes: Dictionary[AudioStreamPlayer, int] = {}
var _last_played: Dictionary[StringName, int] = {}
var volume: float = 0.7

func _exit_tree() -> void:
	cancel()

func play(cue: StringName) -> void:
	_play(cue, 0)

func play_match(generation: int) -> void:
	_play(&"match", generation)

func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0)
	CoreSystem.audio_manager.set_master_volume(volume)

## 本场景仅停止自身借用的播放器，不停止插件中的其他类别音频。
func cancel() -> void:
	for player: AudioStreamPlayer in _players:
		if not is_instance_valid(player): continue
		var finished: Callable = _on_sound_finished.bind(player)
		if player.finished.is_connected(finished): player.finished.disconnect(finished)
		player.stop()
		player.process_mode = _original_modes.get(player, Node.PROCESS_MODE_INHERIT)
		player.pitch_scale = _original_pitch.get(player, 1.0)
	_players.clear()
	_original_modes.clear()
	_last_played.clear()
	_original_pitch.clear()
	_match_index = 0

func _play(cue: StringName, generation: int) -> void:
	if volume <= 0.0 or config == null or not config.cue_paths.has(cue): return
	var now: int = Time.get_ticks_msec()
	if now - _last_played.get(cue, -1000) < config.dedup_ms: return
	if _players.size() >= config.max_voices: return
	_last_played[cue] = now
	var path: String = config.cue_paths[cue]
	var pitch: float = 1.0
	if cue == &"match":
		if not config.match_variants.is_empty():
			path = config.match_variants[_match_index % config.match_variants.size()]
			_match_index += 1
		if not config.match_pitch.is_empty():
			pitch = config.match_pitch[clampi(generation, 0, config.match_pitch.size() - 1)]
	var player: AudioStreamPlayer = CoreSystem.audio_manager.play_sound(path, config.sfx_gain)
	if player == null: return
	# 插件池可能在finished信号派发前复用已停止播放器，保留首次借用模式。
	if not _original_modes.has(player):
		_original_modes[player] = player.process_mode
		_original_pitch[player] = player.pitch_scale
	player.pitch_scale = pitch
	player.process_mode = Node.PROCESS_MODE_ALWAYS if cue in [&"reward", &"acquire", &"finish", &"confirm"] else Node.PROCESS_MODE_PAUSABLE
	if not _players.has(player): _players.append(player)
	var finished: Callable = _on_sound_finished.bind(player)
	if not player.finished.is_connected(finished):
		player.finished.connect(finished, CONNECT_ONE_SHOT)
	cue_played.emit(cue)

func _on_sound_finished(player: AudioStreamPlayer) -> void:
	player.pitch_scale = _original_pitch.get(player, 1.0)
	_original_pitch.erase(player)
	player.process_mode = _original_modes.get(player, Node.PROCESS_MODE_INHERIT)
	_original_modes.erase(player)
	_players.erase(player)
