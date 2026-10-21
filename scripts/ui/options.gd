extends Control
## Opciones: idioma, relación de aspecto, pantalla completa y volumen. Cada cambio se aplica al
## instante y se guarda en user://settings.cfg (ver scripts/core/settings.gd).

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

@onready var _language: OptionButton = %LanguageOption
@onready var _aspect: OptionButton = %AspectOption
@onready var _fullscreen: Button = %FullscreenCheck
@onready var _volume: HSlider = %VolumeSlider
@onready var _volume_label: Label = %VolumeValue
@onready var _back: Button = %BackButton

var _preview_timer: Timer


func _ready() -> void:
	for code in Settings.LANGUAGES:
		_language.add_item(Settings.LANGUAGES[code])
		_language.set_item_metadata(_language.item_count - 1, code)
		if code == Settings.language:
			_language.select(_language.item_count - 1)
	_populate_aspects()
	_fullscreen.button_pressed = Settings.fullscreen
	_update_fullscreen_text()
	_volume.value = Settings.volume * 100.0
	_update_volume_label()

	# El tono de prueba y el guardado del volumen esperan a que dejes de mover el control.
	_preview_timer = Timer.new()
	_preview_timer.one_shot = true
	_preview_timer.wait_time = 0.25
	_preview_timer.timeout.connect(_commit_volume)
	add_child(_preview_timer)

	_language.item_selected.connect(_on_language_selected)
	_aspect.item_selected.connect(_on_aspect_selected)
	_fullscreen.toggled.connect(_on_fullscreen_toggled)
	_volume.value_changed.connect(_on_volume_changed)
	_back.pressed.connect(_go_back)
	Settings.language_changed.connect(_populate_aspects)
	Settings.language_changed.connect(_update_fullscreen_text)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_back()


## El texto de "Automática" cambia con el idioma, así que la lista se rearma al cambiarlo.
func _populate_aspects() -> void:
	_aspect.clear()
	for ratio in Settings.ASPECT_WIDTHS:
		_aspect.add_item(tr("OPT_ASPECT_AUTO") if ratio == "auto" else ratio)
		_aspect.set_item_metadata(_aspect.item_count - 1, ratio)
		if ratio == Settings.aspect:
			_aspect.select(_aspect.item_count - 1)


func _on_language_selected(index: int) -> void:
	Settings.set_language(_language.get_item_metadata(index))


func _on_aspect_selected(index: int) -> void:
	Settings.set_aspect(_aspect.get_item_metadata(index))


func _on_fullscreen_toggled(on: bool) -> void:
	Settings.set_fullscreen(on)
	_update_fullscreen_text()


func _update_fullscreen_text() -> void:
	_fullscreen.text = tr("OPT_ON") if _fullscreen.button_pressed else tr("OPT_OFF")


func _on_volume_changed(value: float) -> void:
	Settings.set_volume(value / 100.0, false)
	_update_volume_label()
	_preview_timer.start()


func _commit_volume() -> void:
	Settings.save()
	Settings.play_preview_tone()


func _update_volume_label() -> void:
	_volume_label.text = "%d%%" % int(round(_volume.value))


func _go_back() -> void:
	Settings.save()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
