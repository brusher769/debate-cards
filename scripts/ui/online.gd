extends Control
## Jugar en línea: conectarse a un servidor, crear una sala o unirse con su código, y la sala de
## espera (jugadores, chat, micrófono) hasta que el anfitrión empieza la partida. La partida en sí
## se juega en la mesa de siempre (table.tscn), que en línea dibuja el motor espejo de Net.

const TABLE_SCENE := "res://scenes/table.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _connect_box: VBoxContainer = %ConnectBox
@onready var _room_box: VBoxContainer = %RoomBox
@onready var _name_edit: LineEdit = %NameEdit
@onready var _address_edit: LineEdit = %AddressEdit
@onready var _host_check: CheckBox = %HostCheck
@onready var _host_info: Label = %HostInfo
@onready var _mode: OptionButton = %ModeOption
@onready var _create: Button = %CreateButton
@onready var _code_edit: LineEdit = %CodeEdit
@onready var _join: Button = %JoinButton
@onready var _code_label: Label = %CodeLabel
@onready var _mode_label: Label = %ModeLabel
@onready var _players_label: Label = %PlayersLabel
@onready var _data_warning: Label = %DataWarning
@onready var _chat_holder: VBoxContainer = %ChatHolder
@onready var _start: Button = %StartButton
@onready var _leave: Button = %LeaveButton
@onready var _status: Label = %StatusLabel
@onready var _back: Button = %BackButton

## Qué hacer cuando la conexión con el servidor esté lista: "create" o "join".
var _pending := ""
var _starting := false


func _ready() -> void:
	_name_edit.placeholder_text = tr("ONLINE_NAME_PLACEHOLDER")
	_address_edit.placeholder_text = tr("ONLINE_ADDRESS_PLACEHOLDER")
	_code_edit.placeholder_text = tr("ONLINE_CODE_PLACEHOLDER")
	_mode.add_item(tr("LOBBY_MODE_NORMAL"), 0)
	_mode.add_item(tr("LOBBY_MODE_INDEFENDIBLE"), 1)
	_create.pressed.connect(_on_create)
	_join.pressed.connect(_on_join)
	_start.pressed.connect(Net.start_game)
	_leave.pressed.connect(_on_leave)
	_back.pressed.connect(_go_back)
	_host_check.toggled.connect(_on_host_toggled)
	Net.connected.connect(_on_connected)
	Net.connection_failed.connect(_on_connection_failed)
	Net.disconnected.connect(_on_disconnected)
	Net.joined.connect(_on_joined)
	Net.room_updated.connect(_refresh_room)
	Net.error_received.connect(_on_error)
	Net.game_started.connect(_on_game_started)
	Net.room_closed.connect(_reset_to_connect)
	# El chat (con el micrófono) vive en la sala de espera, siempre visible.
	var chat := ChatPanel.new()
	chat.collapsible = false
	chat.with_mic = true
	_chat_holder.add_child(chat)
	_show_room(false)
	_name_edit.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _room_box.visible:
		_go_back()


func _on_host_toggled(on: bool) -> void:
	_address_edit.editable = not on
	_join.disabled = on
	_code_edit.editable = not on
	if on:
		var addresses: Array[String] = []
		for ip in IP.get_local_addresses():
			# Solo direcciones IPv4 de red local (las de otras redes no sirven para jugar).
			if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
				addresses.append("%s:%d" % [ip, Net.DEFAULT_PORT])
		_host_info.text = tr("ONLINE_HOST_ADDRESSES") % ", ".join(addresses)
	_host_info.visible = on


func _player_name() -> String:
	var t := _name_edit.text.strip_edges()
	return t if t != "" else tr("DEFAULT_PLAYER_NAME") % 1


## Separa "dirección:puerto" (el puerto es opcional). Una URL ("wss://algo.onrender.com") se deja
## entera: Net.connect_to la usa tal cual.
func _parse_address() -> Array:
	var text := _address_edit.text.strip_edges()
	var port := Net.DEFAULT_PORT
	if text.contains("://"):
		return [text, port]
	if text.contains(":"):
		port = int(text.get_slice(":", 1))
		text = text.get_slice(":", 0)
	return [text if text != "" else "127.0.0.1", port if port > 0 else Net.DEFAULT_PORT]


func _on_create() -> void:
	_start_connection("create")


func _on_join() -> void:
	if _code_edit.text.strip_edges() == "":
		_status.text = tr("ONLINE_NEED_CODE")
		return
	_start_connection("join")


func _start_connection(what: String) -> void:
	_pending = what
	_status.text = tr("ONLINE_CONNECTING")
	_set_buttons_disabled(true)
	Net.shutdown()
	var address := _parse_address()
	var err := Net.host_here(address[1]) if _host_check.button_pressed and what == "create" else Net.connect_to(address[0], address[1])
	if err != OK:
		_reset_to_connect(tr("ONLINE_CONNECT_FAILED"))


func _on_connection_failed() -> void:
	_reset_to_connect(tr("ONLINE_CONNECT_FAILED"))


func _on_disconnected() -> void:
	_reset_to_connect(tr("ONLINE_DISCONNECTED"))


func _on_error(message: String) -> void:
	_status.text = message


func _on_connected() -> void:
	if _pending == "create":
		Net.create_room(_player_name(), GameState.MODES[_mode.get_selected_id()])
	elif _pending == "join":
		Net.join_room(_code_edit.text, _player_name())
	_pending = ""


func _on_joined(info: Dictionary) -> void:
	_status.text = ""
	_set_buttons_disabled(false)
	_show_room(true)
	_refresh_room(info)


## Muestra quién está en la sala y si el anfitrión ya puede empezar.
func _refresh_room(info: Dictionary) -> void:
	_code_label.text = tr("ONLINE_ROOM_CODE") % info["code"]
	var mode_text := tr("LOBBY_MODE_INDEFENDIBLE") if info["mode"] == "indefendible" else tr("LOBBY_MODE_NORMAL")
	_mode_label.text = tr("ONLINE_ROOM_MODE") % mode_text
	var names: Array = info["names"]
	var lines := tr("ONLINE_PLAYERS") % names.size()
	for i in names.size():
		var tag := ""
		if i == int(info["host_slot"]):
			tag += tr("ONLINE_HOST_TAG")
		if i == Net.my_slot:
			tag += tr("ONLINE_YOU_TAG")
		lines += "\n%d. %s%s" % [i + 1, names[i], tag]
	if names.size() < Net.ROOM_SIZE:
		lines += "\n" + tr("ONLINE_WAITING_PLAYERS")
	_players_label.text = lines
	_data_warning.visible = Net.data_mismatch
	var host_name: String = names[int(info["host_slot"])]
	_start.visible = Net.is_host()
	_start.disabled = names.size() < Net.ROOM_SIZE
	if not Net.is_host():
		_status.text = tr("ONLINE_WAIT_HOST_START") % host_name


func _show_room(in_room: bool) -> void:
	# Dentro de la sala se ocultan el título y la explicación para que quepan el chat y los botones.
	_title.visible = not in_room
	_subtitle.visible = not in_room
	_room_box.visible = in_room
	_connect_box.visible = not in_room
	_back.visible = not in_room


func _reset_to_connect(message: String) -> void:
	_pending = ""
	_starting = false
	Voice.set_mic(false)
	_show_room(false)
	_set_buttons_disabled(false)
	_status.text = message


func _set_buttons_disabled(disabled: bool) -> void:
	_create.disabled = disabled
	_join.disabled = disabled or _host_check.button_pressed


## El servidor empezó la partida: se espera la primera foto del estado y se pasa a la mesa.
func _on_game_started() -> void:
	if _starting:
		return
	_starting = true
	await Net.state_received
	get_tree().change_scene_to_file(TABLE_SCENE)


func _on_leave() -> void:
	Net.leave_room()
	Net.shutdown()
	Voice.set_mic(false)
	_reset_to_connect("")


func _go_back() -> void:
	Net.shutdown()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
