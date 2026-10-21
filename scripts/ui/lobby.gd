extends Control
## La sala: nombres de los 3 jugadores y modo de juego (Normal o Lo Indefendible). Al empezar reparte
## los roles al azar y pasa a la mesa 3D.

const TABLE_SCENE := "res://scenes/table.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

@onready var _name_edits: Array = [%Name1, %Name2, %Name3]
@onready var _mode: OptionButton = %ModeOption
@onready var _start: Button = %StartButton
@onready var _back: Button = %BackButton


func _ready() -> void:
	for i in _name_edits.size():
		(_name_edits[i] as LineEdit).placeholder_text = tr("LOBBY_NAME_PLACEHOLDER") % (i + 1)
	_mode.add_item(tr("LOBBY_MODE_NORMAL"), 0)
	_mode.add_item(tr("LOBBY_MODE_INDEFENDIBLE"), 1)
	_mode.select(0)
	_start.pressed.connect(_on_start)
	_back.pressed.connect(_go_back)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_back()


func _on_start() -> void:
	var names: Array[String] = []
	for i in _name_edits.size():
		var t: String = (_name_edits[i] as LineEdit).text.strip_edges()
		if t == "":
			t = tr("DEFAULT_PLAYER_NAME") % (i + 1)
		# Evita nombres repetidos: se confundirían en el marcador.
		var unique := t
		var n := 2
		while names.has(unique):
			unique = "%s (%d)" % [t, n]
			n += 1
		names.append(unique)
	GameState.new_room(names, GameState.MODES[_mode.get_selected_id()])
	GameState.start_game()
	get_tree().change_scene_to_file(TABLE_SCENE)


func _go_back() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
