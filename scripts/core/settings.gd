extends Node
## Autoload "Settings": idioma, relación de aspecto, pantalla completa y volumen.
## Se guardan en user://settings.cfg (fuera del proyecto) y se aplican al arrancar.
## También carga los textos de data/i18n.json y los registra en TranslationServer, así que
## tr("CLAVE") funciona en todo el juego y los Label de las escenas se traducen solos.

signal language_changed

const SETTINGS_PATH := "user://settings.cfg"
const I18N_PATH := "res://data/i18n.json"
## Alto de referencia de la ventana; el ancho sale de la relación de aspecto elegida.
const BASE_HEIGHT := 720
const BASE_WIDTH := 1280
## Idiomas disponibles: código -> nombre que se muestra (siempre en su propio idioma).
const LANGUAGES := {"es": "Español", "en": "English"}
## Relaciones de aspecto: nombre -> ancho de referencia. "auto" no fuerza ninguna.
const ASPECT_WIDTHS := {"auto": 0, "16:9": 1280, "16:10": 1152, "4:3": 960, "21:9": 1680}

var language := "es"
var aspect := "auto"
var fullscreen := false
## Volumen general de 0.0 a 1.0.
var volume := 1.0
## false = no escribe user://settings.cfg (lo usan las pruebas para no tocar tus ajustes).
var persist := true

var _preview: AudioStreamPlayer


func _ready() -> void:
	_load_translations()
	_load_settings()
	TranslationServer.set_locale(language)
	apply_video()
	_apply_volume()


func set_language(code: String) -> void:
	if not LANGUAGES.has(code):
		return
	language = code
	TranslationServer.set_locale(code)
	language_changed.emit()
	save()


func set_aspect(ratio: String) -> void:
	if not ASPECT_WIDTHS.has(ratio):
		return
	aspect = ratio
	apply_video()
	save()


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	apply_video()
	save()


## `save_now` = false sirve para mover el control de volumen sin escribir el archivo en cada paso.
func set_volume(value: float, save_now := true) -> void:
	volume = clampf(value, 0.0, 1.0)
	_apply_volume()
	if save_now:
		save()


func reset_to_defaults(save_to_disk: bool) -> void:
	persist = save_to_disk
	set_language("es")
	set_aspect("auto")
	set_fullscreen(false)
	set_volume(1.0)


## Aplica relación de aspecto y pantalla completa a la ventana del juego.
func apply_video() -> void:
	var win := get_window()
	var width: int = ASPECT_WIDTHS.get(aspect, 0)
	if width == 0:
		win.content_scale_size = Vector2i(BASE_WIDTH, BASE_HEIGHT)
		win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	else:
		win.content_scale_size = Vector2i(width, BASE_HEIGHT)
		win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	if fullscreen:
		win.mode = Window.MODE_FULLSCREEN
		return
	if win.mode == Window.MODE_FULLSCREEN:
		win.mode = Window.MODE_WINDOWED
	if width > 0:
		_fit_window(Vector2i(width, BASE_HEIGHT))


## Suena un tono corto para que se note el volumen al mover el control.
func play_preview_tone() -> void:
	if _preview == null:
		_preview = AudioStreamPlayer.new()
		_preview.stream = _make_tone()
		add_child(_preview)
	_preview.play()


func save() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("game", "language", language)
	cfg.set_value("video", "aspect", aspect)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("audio", "volume", volume)
	cfg.save(SETTINGS_PATH)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	var lang := str(cfg.get_value("game", "language", language))
	if LANGUAGES.has(lang):
		language = lang
	var asp := str(cfg.get_value("video", "aspect", aspect))
	if ASPECT_WIDTHS.has(asp):
		aspect = asp
	fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))
	volume = clampf(float(cfg.get_value("audio", "volume", volume)), 0.0, 1.0)


func _load_translations() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(I18N_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Settings: no pude leer los textos de %s" % I18N_PATH)
		return
	for code in parsed:
		if not LANGUAGES.has(code) or typeof(parsed[code]) != TYPE_DICTIONARY:
			continue
		var t := Translation.new()
		t.locale = code
		for key in parsed[code]:
			t.add_message(key, str(parsed[code][key]))
		TranslationServer.add_translation(t)


func _apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(0, volume <= 0.001)


## Ajusta la ventana a la relación elegida, sin pasarse del tamaño útil de la pantalla.
func _fit_window(size: Vector2i) -> void:
	var win := get_window()
	var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
	var factor := minf(1.0, minf(usable.size.x * 0.95 / size.x, usable.size.y * 0.95 / size.y))
	var target := Vector2i(int(size.x * factor), int(size.y * factor))
	win.size = target
	win.position = usable.position + (usable.size - target) / 2


func _make_tone() -> AudioStreamWAV:
	var rate := 22050
	var count := int(rate * 0.18)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var fade := 1.0 - float(i) / count
		data.encode_s16(i * 2, int(sin(TAU * 660.0 * i / rate) * fade * 0.5 * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav
