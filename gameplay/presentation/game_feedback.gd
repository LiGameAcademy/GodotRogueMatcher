class_name GameFeedback
extends Node

## 项目提示音适配器；播放使用插件池，音效长尾不加入演出屏障。
signal cue_played(cue: StringName)
const SOUNDS: Dictionary[StringName, String] = {
	&"select": "res://gameplay/presentation/audio/select.tres",
	&"match": "res://gameplay/presentation/audio/match.tres",
	&"blast": "res://gameplay/presentation/audio/blast.tres",
	&"reward": "res://gameplay/presentation/audio/reward.tres",
	&"finish": "res://gameplay/presentation/audio/finish.tres",
}
var _players: Array[AudioStreamPlayer] = []
var _original_modes: Dictionary[AudioStreamPlayer, int] = {}
var _last_played: Dictionary[StringName, int] = {}
var volume: float = 0.7

func _exit_tree() -> void:
	cancel()

func play(cue: StringName) -> void:
	if volume <= 0.0 or not SOUNDS.has(cue): return
	var now: int = Time.get_ticks_msec()
	if now - _last_played.get(cue, -1000) < 70: return
	_last_played[cue] = now
	var player: AudioStreamPlayer = CoreSystem.audio_manager.play_sound(SOUNDS[cue], 0.5)
	if player == null: return
	# 插件池可能在finished信号派发前复用已停止播放器，保留首次借用模式。
	if not _original_modes.has(player): _original_modes[player] = player.process_mode
	player.process_mode = Node.PROCESS_MODE_ALWAYS if cue in [&"reward", &"finish"] else Node.PROCESS_MODE_PAUSABLE
	if not _players.has(player): _players.append(player)
	var finished: Callable = _on_sound_finished.bind(player)
	if not player.finished.is_connected(finished):
		player.finished.connect(finished, CONNECT_ONE_SHOT)
	cue_played.emit(cue)

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
	_players.clear()
	_original_modes.clear()
	_last_played.clear()

func _on_sound_finished(player: AudioStreamPlayer) -> void:
	player.process_mode = _original_modes.get(player, Node.PROCESS_MODE_INHERIT)
	_original_modes.erase(player)
	_players.erase(player)
