class_name ChatPanel
extends PanelContainer
## Chat de texto de la sala en línea (fase 4). Se arma por código y sirve tanto en la sala de espera
## como en la mesa. Los mensajes viajan por Net (el servidor los reenvía a los 3 jugadores).
##
## Con `collapsible = true` (la mesa) empieza plegado, mostrando solo un botón «Chat (n)» con los
## mensajes sin leer; con false (la sala de espera) siempre se ve completo. Con `with_mic = true`
## agrega el interruptor del micrófono (fase 5, ver scripts/voice/voice_chat.gd) y un aviso de
## quién está hablando.

## Cuántos mensajes se guardan en pantalla.
const MAX_LINES := 100

var collapsible := true
var with_mic := false

var _body: VBoxContainer
var _log: RichTextLabel
var _input: LineEdit
var _toggle: Button
var _mic: CheckButton
var _speaking: Label
var _speaking_timer: Timer
var _unread := 0
var _lines := 0


func _ready() -> void:
	custom_minimum_size = Vector2(300, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)
	_toggle = Button.new()
	_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toggle.pressed.connect(_on_toggle)
	header.add_child(_toggle)
	if with_mic:
		_mic = CheckButton.new()
		_mic.text = tr("VOICE_MIC")
		_mic.toggled.connect(_on_mic_toggled)
		header.add_child(_mic)
		_speaking = Label.new()
		_speaking.custom_minimum_size = Vector2(200, 0)
		_speaking.add_theme_font_size_override("font_size", 13)
		_speaking.visible = false
		box.add_child(_speaking)
		_speaking_timer = Timer.new()
		_speaking_timer.one_shot = true
		_speaking_timer.wait_time = 0.6
		_speaking_timer.timeout.connect(func() -> void: _speaking.visible = false)
		add_child(_speaking_timer)
		Voice.speaking.connect(_on_speaking)
		_mic.set_pressed_no_signal(Voice.mic_open)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 4)
	box.add_child(_body)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.custom_minimum_size = Vector2(0, 150)
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(_log)

	var row := HBoxContainer.new()
	_body.add_child(row)
	_input = LineEdit.new()
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.max_length = Net.MAX_CHAT
	_input.placeholder_text = tr("CHAT_PLACEHOLDER")
	_input.text_submitted.connect(func(_t: String) -> void: _send())
	row.add_child(_input)
	var send := Button.new()
	send.text = tr("CHAT_SEND")
	send.pressed.connect(_send)
	row.add_child(send)

	_toggle.visible = collapsible
	_body.visible = not collapsible
	_refresh_toggle()
	Net.chat_received.connect(_on_chat)


## Agrega una línea de sistema (gris) al chat, por ejemplo «Ana entró a la sala».
func add_system_line(text: String) -> void:
	_append("[color=#8a94a8][i]%s[/i][/color]" % _escape(text))


func _on_chat(sender: String, text: String) -> void:
	_append("[b]%s:[/b] %s" % [_escape(sender), _escape(text)])
	if collapsible and not _body.visible:
		_unread += 1
		_refresh_toggle()


func _send() -> void:
	var text := _input.text.strip_edges()
	if text == "":
		return
	Net.send_chat(text)
	_input.clear()
	_input.grab_focus()


func _on_mic_toggled(on: bool) -> void:
	if on and not Voice.set_mic(true):
		_mic.set_pressed_no_signal(false)
		add_system_line(tr(Voice.last_error))
		if collapsible and not _body.visible:
			_on_toggle() # se abre el chat para que se lea el motivo
	elif not on:
		Voice.set_mic(false)


func _on_speaking(slot: int) -> void:
	if not is_inside_tree():
		return # el panel ya salió de la pantalla (cambio de escena)
	var names: Array = Net.room_info.get("names", [])
	if slot < 0 or slot >= names.size():
		return
	_speaking.text = tr("VOICE_SPEAKING") % names[slot]
	_speaking.visible = true
	_speaking_timer.start()


func _on_toggle() -> void:
	_body.visible = not _body.visible
	if _body.visible:
		_unread = 0
		_input.grab_focus()
	_refresh_toggle()


func _refresh_toggle() -> void:
	if _unread > 0:
		_toggle.text = tr("CHAT_BUTTON_UNREAD") % _unread
	else:
		_toggle.text = tr("CHAT_BUTTON")


func _append(bbcode: String) -> void:
	_log.append_text(bbcode + "\n")
	_lines += 1
	if _lines > MAX_LINES:
		_log.remove_paragraph(0)
		_lines -= 1


## Evita que un nombre o mensaje con corchetes rompa el BBCode.
func _escape(text: String) -> String:
	return text.replace("[", "[lb]")
