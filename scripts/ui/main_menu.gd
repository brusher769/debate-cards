extends Control
## Menú principal: entrar a la sala (una pantalla), jugar en línea, guía de juego, opciones y salir.

const LOBBY_SCENE := "res://scenes/lobby.tscn"
const ONLINE_SCENE := "res://scenes/online.tscn"
const SERVER_SCENE := "res://scenes/server.tscn"
const TUTORIAL_SCENE := "res://scenes/tutorial.tscn"
const OPTIONS_SCENE := "res://scenes/options.tscn"

@onready var _play: Button = %PlayButton
@onready var _online: Button = %OnlineButton
@onready var _howto: Button = %HowToButton
@onready var _options: Button = %OptionsButton
@onready var _quit: Button = %QuitButton


func _ready() -> void:
	# Un juego exportado se puede arrancar como servidor: Debate.exe --headless -- --server
	if OS.get_cmdline_user_args().has("--server"):
		_go.call_deferred(SERVER_SCENE)
		return
	_play.pressed.connect(_go.bind(LOBBY_SCENE))
	_online.pressed.connect(_go.bind(ONLINE_SCENE))
	_howto.pressed.connect(_go.bind(TUTORIAL_SCENE))
	_options.pressed.connect(_go.bind(OPTIONS_SCENE))
	_quit.pressed.connect(get_tree().quit)
	_quit.visible = not OS.has_feature("web")
	_play.grab_focus()


func _go(scene: String) -> void:
	get_tree().change_scene_to_file(scene)
