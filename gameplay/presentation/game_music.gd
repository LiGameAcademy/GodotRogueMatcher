class_name GameMusic
extends AudioStreamPlayer

## Optional locally supplied music. Missing files are a supported public build.
@export_file("*.mp3", "*.ogg") var local_path: String = "res://local_audio/gameplay.mp3"
@export_range(0.0, 1.0) var music_gain: float = 0.5

func _ready() -> void:
	start_optional()

## Loading never changes the shared imported stream's loop setting.
func start_optional() -> bool:
	stop()
	stream = null
	if local_path.is_empty() or not ResourceLoader.exists(local_path): return false
	var loaded: AudioStream = load(local_path) as AudioStream
	if loaded == null:
		push_warning("Optional music is not an AudioStream: " + local_path)
		return false
	if not loaded is AudioStreamMP3 and not loaded is AudioStreamOggVorbis:
		push_warning("Optional music requires MP3 or Ogg Vorbis: " + local_path)
		return false
	stream = loaded.duplicate() as AudioStream
	if stream is AudioStreamMP3: (stream as AudioStreamMP3).loop = true
	else: (stream as AudioStreamOggVorbis).loop = true
	bus = &"Music"
	volume_db = linear_to_db(music_gain)
	play()
	return true
