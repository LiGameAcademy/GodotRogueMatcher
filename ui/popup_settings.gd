extends UIPopup

@onready var btn_audio: TextureButton = %btn_audio
@onready var slider_audio: HSlider = %slider_audio
@onready var btn_music: TextureButton = %btn_music
@onready var slider_music: HSlider = %slider_music

var t_audioOff = preload("res://assets/textures/widgets/icons/audioOff.png")
var t_audioOn = preload("res://assets/textures/widgets/icons/audioOn.png")
var t_musicOff = preload("res://assets/textures/widgets/icons/musicOff.png")
var t_musicOn = preload("res://assets/textures/widgets/icons/musicOn.png")

var is_open_audio : bool :
	get:
		return AudioManager.is_open_audio

var is_open_music : bool :
	get:
		return AudioManager.is_open_music

#signal confirm_pressed

func _ready() -> void:
	slider_audio.value_changed.connect(_on_slider_audio_value_changed)
	slider_music.value_changed.connect(_on_slider_music_value_changed)
	btn_audio.pressed.connect(_on_btn_audio_pressed)
	btn_music.pressed.connect(_on_btn_music_pressed)
	slider_audio.value = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))
	slider_music.value = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("BGM"))
	set_audio()
	set_music()

func set_audio() -> void:
	btn_audio.texture_normal = t_audioOn if is_open_audio == true else t_audioOff
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), !is_open_audio)

func set_music() -> void:
	btn_music.texture_normal = t_musicOn if is_open_music == true else t_musicOff
	AudioServer.set_bus_mute(AudioServer.get_bus_index("BGM"), !is_open_music)

func _on_slider_audio_value_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), value)

func _on_slider_music_value_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("BGM"), value)

func _on_btn_audio_pressed() -> void:
	is_open_audio = not is_open_audio
	set_audio()
	
func _on_btn_music_pressed() -> void:
	is_open_music = not is_open_music
	set_music()

func _on_btn_confirm_pressed() -> void:
	ui_manager.close_current_interface()
