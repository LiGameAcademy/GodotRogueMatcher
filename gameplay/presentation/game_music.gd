class_name GameMusic
extends AudioStreamPlayer

## Owns optional music outside the public project; missing files leave the game silent.
const PRIVATE_MUSIC_RELATIVE: String = "../local_audio/gameplay.mp3"
## Empty selects the sibling private file; res:// permits imported test audio.
@export var local_path: String = ""
@export_range(0.0, 1.0) var music_gain: float = 0.5

func _ready() -> void:
	start_optional()

## Loading never changes the shared imported stream's loop setting.
func start_optional() -> bool:
	stop()
	stream = null
	var path: String = _resolve_music_path()
	var loaded: AudioStream = _load_optional_stream(path)
	if loaded == null:
		return false
	if not loaded is AudioStreamMP3 and not loaded is AudioStreamOggVorbis:
		push_warning("Optional music requires MP3 or Ogg Vorbis: " + path)
		return false
	stream = loaded.duplicate() as AudioStream
	if stream is AudioStreamMP3: (stream as AudioStreamMP3).loop = true
	else: (stream as AudioStreamOggVorbis).loop = true
	bus = &"Music"
	volume_db = linear_to_db(music_gain)
	play()
	return true

func _resolve_music_path() -> String:
	if local_path.is_empty():
		return ProjectSettings.globalize_path("res://").path_join(PRIVATE_MUSIC_RELATIVE).simplify_path()
	if local_path.begins_with("res://") or local_path.is_absolute_path():
		return local_path
	return ProjectSettings.globalize_path("res://").path_join(local_path).simplify_path()

func _load_optional_stream(path: String) -> AudioStream:
	if path.begins_with("res://"):
		if not ResourceLoader.exists(path):
			return null
		var imported: AudioStream = load(path) as AudioStream
		if imported == null:
			push_warning("Optional music is not an AudioStream: " + path)
		return imported
	if not FileAccess.file_exists(path):
		return null
	var extension: String = path.get_extension().to_lower()
	if extension == "mp3":
		return AudioStreamMP3.load_from_file(path)
	if extension == "ogg":
		return AudioStreamOggVorbis.load_from_file(path)
	push_warning("Optional music requires MP3 or Ogg Vorbis: " + path)
	return null
