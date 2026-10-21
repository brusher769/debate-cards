extends Node
## Prueba de humo de los menús: navegación del menú principal, opciones (idioma, relación de
## aspecto, volumen, pantalla completa), guía por páginas y la sala (nombres, modo de juego, paso
## a la mesa 3D). Necesita render real (ver tests/ui_smoke.gd):
##   godot --path . res://tests/menu_smoke.tscn
## Imprime "MENU OK" si todo pasó. No toca tus ajustes guardados (Settings.persist = false).
## Con SHOT_DIR guarda capturas (menú principal, opciones y guía, en español e inglés).

const MAIN_MENU := "res://scenes/main_menu.tscn"
const OPTIONS := "res://scenes/options.tscn"
const TUTORIAL := "res://scenes/tutorial.tscn"
const LOBBY := "res://scenes/lobby.tscn"
const ONLINE := "res://scenes/online.tscn"

var _failures := 0
var _shot_dir := ""
var _shot_n := 0


func _ready() -> void:
	_shot_dir = OS.get_environment("SHOT_DIR")
	# El árbol está ocupado montando hijos durante _ready: se ejecuta un instante después.
	_run.call_deferred()


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FALLO: ", msg)


func _frames(n := 2) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(label: String) -> void:
	if _shot_dir == "":
		return
	await _frames(6)
	await RenderingServer.frame_post_draw
	_shot_n += 1
	get_viewport().get_texture().get_image().save_png("%s/m%02d_%s.png" % [_shot_dir, _shot_n, label])


## change_scene_to_file libera la escena actual; que sea un señuelo y no esta prueba.
func _decoy() -> void:
	var decoy := Node.new()
	get_tree().root.add_child(decoy)
	get_tree().current_scene = decoy


func _run() -> void:
	Settings.reset_to_defaults(false)
	await _test_navigation()
	await _test_options()
	await _test_tutorial()
	await _test_lobby()
	await _test_online_screen()
	Settings.reset_to_defaults(false)
	print("MENU OK" if _failures == 0 else "MENU CON FALLOS: %d" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _test_navigation() -> void:
	for pair in [["PlayButton", "Lobby"], ["OnlineButton", "Online"], ["HowToButton", "Tutorial"], ["OptionsButton", "Options"]]:
		_decoy()
		var menu: Control = load(MAIN_MENU).instantiate()
		add_child(menu)
		await _frames()
		if pair[0] == "PlayButton":
			await _shot("menu_principal_es")
			_check(menu.get_node("%QuitButton") != null, "hay botón de salir")
		menu.get_node("%" + pair[0]).pressed.emit()
		await _frames()
		var scene := get_tree().current_scene
		_check(scene != null and scene.name == pair[1], "%s lleva a %s (escena: %s)" % [pair[0], pair[1], scene])
		menu.queue_free()
		if scene != null and scene != self:
			scene.queue_free()
		await _frames()


func _test_options() -> void:
	var opt: Control = load(OPTIONS).instantiate()
	add_child(opt)
	await _frames()
	await _shot("opciones_es")

	# Idioma.
	var lang: OptionButton = opt.get_node("%LanguageOption")
	_check(lang.item_count == Settings.LANGUAGES.size(), "una entrada por idioma")
	lang.select(1)
	lang.item_selected.emit(1)
	await _frames()
	_check(Settings.language == "en", "el idioma pasa a inglés")
	_check(TranslationServer.get_locale() == "en", "el locale pasa a inglés")
	_check(tr("MENU_PLAY") == "Enter the room", "tr() en inglés")
	var aspect: OptionButton = opt.get_node("%AspectOption")
	_check(aspect.get_item_text(0).begins_with("Automatic"), "la lista de aspectos se traduce (%s)" % aspect.get_item_text(0))
	await _shot("opciones_en")

	# Relación de aspecto.
	for i in aspect.item_count:
		var ratio: String = aspect.get_item_metadata(i)
		if ratio == "auto":
			continue
		aspect.select(i)
		aspect.item_selected.emit(i)
		await _frames(3)
		var want := Vector2i(Settings.ASPECT_WIDTHS[ratio], Settings.BASE_HEIGHT)
		_check(Settings.aspect == ratio, "aspecto %s guardado en Settings" % ratio)
		_check(get_window().content_scale_size == want, "aspecto %s: tamaño base %s (fue %s)" % [ratio, want, get_window().content_scale_size])
		_check(get_window().content_scale_aspect == Window.CONTENT_SCALE_ASPECT_KEEP, "aspecto %s: se mantiene la proporción" % ratio)
		if ratio == "4:3":
			await _shot("opciones_4_3")

	# Volumen.
	var slider: HSlider = opt.get_node("%VolumeSlider")
	slider.value = 50
	_check(absf(AudioServer.get_bus_volume_db(0) - linear_to_db(0.5)) < 0.01, "volumen 50%% aplicado al bus (db = %s)" % AudioServer.get_bus_volume_db(0))
	_check(opt.get_node("%VolumeValue").text == "50%", "texto del volumen")
	_check(not AudioServer.is_bus_mute(0), "50%% no silencia")
	slider.value = 0
	_check(AudioServer.is_bus_mute(0), "volumen 0 silencia el bus")
	slider.value = 100
	_check(not AudioServer.is_bus_mute(0) and absf(AudioServer.get_bus_volume_db(0)) < 0.01, "volumen 100%% = 0 dB")

	# Pantalla completa (se enciende y se apaga de inmediato).
	var full: Button = opt.get_node("%FullscreenCheck")
	full.button_pressed = true
	await _frames(3)
	_check(Settings.fullscreen and get_window().mode == Window.MODE_FULLSCREEN, "pantalla completa activa")
	full.button_pressed = false
	await _frames(3)
	_check(not Settings.fullscreen and get_window().mode != Window.MODE_FULLSCREEN, "pantalla completa apagada")

	opt.queue_free()
	Settings.reset_to_defaults(false)
	await _frames(3)


func _test_tutorial() -> void:
	for lang in ["es", "en"]:
		Settings.set_language(lang)
		var tut: Control = load(TUTORIAL).instantiate()
		add_child(tut)
		await _frames()
		var title: Label = tut.get_node("%PageTitle")
		var body: Label = tut.get_node("%PageBody")
		var counter: Label = tut.get_node("%CounterLabel")
		var next: Button = tut.get_node("%NextButton")
		var prev: Button = tut.get_node("%PrevButton")
		var cards: HBoxContainer = tut.get_node("%CardsRow")
		_check(prev.disabled, "en la primera página no hay 'anterior'")
		var seen := {}
		for page in range(1, tut.PAGES + 1):
			_check(counter.text == "%d / %d" % [page, tut.PAGES], "contador de página (%s)" % counter.text)
			_check(not title.text.begins_with("HELP_") and not body.text.begins_with("HELP_"), "página %d con texto en %s" % [page, lang])
			_check(not body.text.contains("{"), "página %d sin marcadores sin reemplazar: %s" % [page, body.text])
			_check(not seen.has(title.text), "títulos de página distintos")
			seen[title.text] = true
			_check(cards.visible == (page == tut.CARDS_PAGE), "las cartas de ejemplo solo en la página %d" % tut.CARDS_PAGE)
			if page == tut.CARDS_PAGE:
				_check(cards.get_child_count() == 3, "3 cartas de ejemplo (hay %d)" % cards.get_child_count())
				await _shot("guia_cartas_" + lang)
			elif page == 5:
				await _shot("guia_puntos_" + lang)
			if page < tut.PAGES:
				next.pressed.emit()
				await _frames()
		_check(next.disabled, "en la última página no hay 'siguiente'")
		tut.queue_free()
		await _frames()
	Settings.set_language("es")


func _test_lobby() -> void:
	_decoy()
	var lobby: Control = load(LOBBY).instantiate()
	add_child(lobby)
	await _frames()

	lobby.get_node("%Name1").text = "Ana"
	lobby.get_node("%Name2").text = "Ana"
	lobby.get_node("%Name3").text = ""
	var mode: OptionButton = lobby.get_node("%ModeOption")
	_check(mode.item_count == 2, "dos modos de juego")
	mode.select(1) # Lo Indefendible
	await _shot("sala_es")
	lobby.get_node("%StartButton").pressed.emit()
	await _frames()

	var got: Array = []
	for p in GameState.players:
		got.append(p.display_name)
	_check(got == ["Ana", "Ana (2)", "Jugador 3"], "nombres = %s" % [got])
	_check(GameState.mode == "indefendible", "modo = %s" % GameState.mode)
	_check(GameState.engine != null and GameState.engine.mode == "indefendible", "la partida se creó con el modo elegido")
	_check(GameState.engine.debaters.size() == 2 and GameState.engine.judge != null, "roles repartidos: 2 debatientes y 1 juez")
	var scene := get_tree().current_scene
	_check(scene != null and scene.name == "Table", "no pasó a la mesa (escena: %s)" % scene)
	lobby.queue_free()
	if scene != null and scene != self:
		scene.queue_free()
	await _frames()

	# El botón Volver de la sala regresa al menú principal.
	_decoy()
	lobby = load(LOBBY).instantiate()
	add_child(lobby)
	await _frames()
	lobby.get_node("%BackButton").pressed.emit()
	await _frames()
	scene = get_tree().current_scene
	_check(scene != null and scene.name == "MainMenu", "Volver lleva al menú principal (escena: %s)" % scene)
	lobby.queue_free()
	if scene != null and scene != self:
		scene.queue_free()


## La pantalla «Jugar en línea»: se ve y responde sin necesidad de un servidor.
func _test_online_screen() -> void:
	_decoy()
	var online: Control = load(ONLINE).instantiate()
	add_child(online)
	await _frames()
	await _shot("en_linea_es")
	_check(online.get_node("%ConnectBox").visible and not online.get_node("%RoomBox").visible, "al entrar se ve la conexión, no la sala")
	_check(online.get_node("%NameEdit").placeholder_text == tr("ONLINE_NAME_PLACEHOLDER"), "los textos se traducen")
	_check(online.get_node("%ModeOption").item_count == 2, "dos modos de juego")
	# «Unirse» sin código avisa.
	online.get_node("%JoinButton").pressed.emit()
	await _frames()
	_check(online.get_node("%StatusLabel").text == tr("ONLINE_NEED_CODE"), "unirse sin código avisa (%s)" % online.get_node("%StatusLabel").text)
	# Alojar aquí muestra a qué dirección se conectan los demás y apaga «Unirse».
	var host: CheckBox = online.get_node("%HostCheck")
	host.button_pressed = true
	await _frames()
	_check(online.get_node("%HostInfo").visible and online.get_node("%JoinButton").disabled, "alojar en este PC muestra las direcciones y apaga «Unirse»")
	host.button_pressed = false
	# Conectar a un puerto donde no hay servidor termina con un mensaje, sin colgarse.
	online.get_node("%AddressEdit").text = "127.0.0.1:1"
	online.get_node("%CreateButton").pressed.emit()
	for i in 200:
		await _frames(3)
		if online.get_node("%StatusLabel").text == tr("ONLINE_CONNECT_FAILED"):
			break
	_check(online.get_node("%StatusLabel").text == tr("ONLINE_CONNECT_FAILED"), "sin servidor: aviso de que no se pudo conectar (%s)" % online.get_node("%StatusLabel").text)
	_check(not online.get_node("%CreateButton").disabled, "y se puede volver a intentar")
	Net.shutdown()
	online.queue_free()
	await _frames()
	# Volver regresa al menú principal.
	_decoy()
	online = load(ONLINE).instantiate()
	add_child(online)
	await _frames()
	online.get_node("%BackButton").pressed.emit()
	await _frames()
	var scene := get_tree().current_scene
	_check(scene != null and scene.name == "MainMenu", "Volver lleva al menú principal (escena: %s)" % scene)
	online.queue_free()
	if scene != null and scene != self:
		scene.queue_free()
