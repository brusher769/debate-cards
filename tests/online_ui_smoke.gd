extends Node
## Prueba de la INTERFAZ del juego en línea con render real (no sirve con --headless). Esta ventana
## hace de un jugador humano: entra a la pantalla «Jugar en línea», crea la sala, espera a que
## entren los otros dos jugadores (bots sin pantalla), empieza la partida y la juega con clics
## sobre la mesa 3D. La lanza tests/run_online_ui_test.sh junto con el servidor y los bots.
##
## Opciones (después de "--"): --address=127.0.0.1 --port=N --code-file=ruta [--host]
## Con SHOT_DIR guarda capturas. Imprime "ONLINE UI OK" si todo pasó.

const Phase := DebateEngine.Phase

var _address := "127.0.0.1"
var _port := Net.DEFAULT_PORT
var _code_file := ""
var _failures := 0
var _shot_dir := ""
var _shot_n := 0
var _table: Node3D
var _stage: Stage3D
var _last_sig := ""
var _coverage := {}
var _chats := 0
var _waited_views := 0 ## veces que se comprobó la pantalla de espera (no era mi turno)
var _my_turns := 0
var _judge_actions := 0 ## veces que actué como juez
var _last_change_msec := 0
var _i_was_judge := false ## mi rol en esta partida (al final la sala ya puede haberse cerrado)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FALLO: ", msg)


func _ready() -> void:
	_shot_dir = OS.get_environment("SHOT_DIR")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--address="):
			_address = arg.get_slice("=", 1)
		elif arg.begins_with("--port="):
			_port = int(arg.get_slice("=", 1))
		elif arg.begins_with("--code-file="):
			_code_file = arg.get_slice("=", 1)
	_run.call_deferred()


func _log(text: String) -> void:
	if OS.get_environment("NET_DEBUG") != "":
		print("[ui %6d ms] %s" % [Time.get_ticks_msec(), text])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(label: String) -> void:
	if _shot_dir == "":
		return
	await _wait(0.9)
	await RenderingServer.frame_post_draw
	_shot_n += 1
	get_viewport().get_texture().get_image().save_png("%s/o%02d_%s.png" % [_shot_dir, _shot_n, label])


func _btn(node_name: String) -> Button:
	return _table.get_node("%" + node_name)


func _press(b: Button) -> void:
	var e := Net.mirror
	_check(b.visible and not b.disabled, "botón '%s' debe estar activo (texto: %s, visible %s, desactivado %s; fase %s, turno %d, activo %s, carta elegida %s)" % [
		b.name, b.text, b.visible, b.disabled, Phase.keys()[e.phase], e.turn_index, e.active.display_name if e.active != null else "-",
		_table._selected_card.id if _table._selected_card != null else "ninguna"])
	b.pressed.emit()


## change_scene_to_file libera la escena actual; que sea un señuelo y no esta prueba.
func _decoy() -> void:
	var decoy := Node.new()
	get_tree().root.add_child(decoy)
	get_tree().current_scene = decoy


func _until(condition: Callable, seconds: float, what: String) -> bool:
	var t := 0.0
	while not condition.call():
		await get_tree().process_frame
		t += get_process_delta_time()
		if t > seconds:
			_check(false, "se esperó %.0f s: %s" % [seconds, what])
			return false
	return true


func _run() -> void:
	Settings.reset_to_defaults(false)
	Net.chat_received.connect(func(_who: String, _text: String) -> void: _chats += 1)
	# La pantalla «Jugar en línea» es la escena actual (como en el juego): al empezar la partida se
	# reemplaza por la mesa.
	var online: Control = load("res://scenes/online.tscn").instantiate()
	get_tree().root.add_child(online)
	get_tree().current_scene = online
	await _frames(3)
	await _shot("pantalla_en_linea")

	# --- Sala de espera ---
	online.get_node("%NameEdit").text = "Ana"
	online.get_node("%AddressEdit").text = "%s:%d" % [_address, _port]
	online.get_node("%CreateButton").pressed.emit()
	_log("crear sala pulsado")
	if not await _until(func() -> bool: return Net.my_slot >= 0, 10.0, "entrar a la sala"):
		return _end()
	_log("dentro de la sala %s" % Net.room_code)
	await _frames(3)
	_check(online.get_node("%RoomBox").visible and not online.get_node("%ConnectBox").visible, "se ve la sala de espera")
	_check(online.get_node("%CodeLabel").text.contains(Net.room_code), "se ve el código de la sala")
	_check(online.get_node("%StartButton").visible and online.get_node("%StartButton").disabled, "el anfitrión ve «Empezar» desactivado hasta que estén los 3")
	var f := FileAccess.open(_code_file, FileAccess.WRITE)
	f.store_string(Net.room_code)
	f.close()
	if not await _until(func() -> bool: return (Net.room_info.get("names", []) as Array).size() == 3, 20.0, "que entren los otros dos jugadores"):
		return _end()
	await _frames(3)
	_check(not online.get_node("%StartButton").disabled, "con los 3 jugadores se puede empezar")
	_check(online.get_node("%PlayersLabel").text.contains("Beto") and online.get_node("%PlayersLabel").text.contains("Caro"), "la lista muestra a los otros jugadores")
	await _shot("sala_de_espera")
	_log("empezar pulsado")
	online.get_node("%StartButton").pressed.emit()

	# --- La mesa ---
	if not await _until(func() -> bool: return get_tree().current_scene != null and get_tree().current_scene.name == "Table", 10.0, "pasar a la mesa"):
		return _end()
	_table = get_tree().current_scene
	_stage = _table.get_node("%Stage")
	_log("mesa cargada; mirror=%s" % (Net.mirror != null))
	await _frames(3)
	await _play()
	_end()


func _end() -> void:
	_check(_chats >= 2, "se recibieron los saludos del chat (%d)" % _chats)
	# Los roles se reparten al azar: las comprobaciones dependen de si me tocó ser juez o debatiente.
	# (Los bots juegan al instante: esta ventana puede no alcanzar a ver todas las fases, así que solo se
	# exige lo que depende de mi rol y que la partida llegue al final.)
	_check(_coverage.has("OVER"), "la partida llegó al final")
	if _i_was_judge:
		_check(_judge_actions > 0, "como juez, puntué o decidí alguna intervención")
	else:
		_check(_my_turns > 0, "como debatiente, tuve algún turno")
	# (Los bots juegan al instante, así que las pantallas de espera duran poco: _waited_views es solo informativo.)
	if _failures == 0:
		print("ONLINE UI OK (fases vistas: %s)" % ", ".join(_coverage.keys()))
	else:
		printerr("ONLINE UI CON FALLOS: ", _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _click(pos: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = pos
	move.global_position = pos
	Input.parse_input_event(move)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		Input.parse_input_event(ev)
	await _frames(2)


func _judge_buttons() -> Array[Button]:
	var out: Array[Button] = []
	var panel: VBoxContainer = _table.get_node("%JudgePanel")
	for row in panel.get_children():
		for b in row.get_children():
			if b is Button:
				out.append(b)
	return out


func _play() -> void:
	var e := Net.mirror
	var me := e.player_by_index(Net.my_slot)
	var guard := 0
	while guard < 3000:
		guard += 1
		await _frames(3)
		e = Net.mirror
		if e == null:
			_check(false, "se perdió la partida")
			return
		me = e.player_by_index(Net.my_slot)
		_i_was_judge = e.judge == me
		_coverage[Phase.keys()[e.phase]] = true
		if guard < 6 or guard % 200 == 0:
			_log("iteración %d: fase %s, turno %d" % [guard, Phase.keys()[e.phase], e.turn_index])
		# Privacidad: mi motor espejo nunca tiene la mano del rival.
		for p in e.players:
			if p != me and (not p.hand.is_empty() or not p.wilds.is_empty()):
				_check(false, "el espejo tiene la mano de %s" % p.display_name)
		if e.phase == Phase.OVER:
			await _final_step(e)
			return
		var unit := e.current_unit()
		var sig := "%d/%d/%s/%d/%d/%d/%d" % [e.phase, e.turn_index, str(unit["card"].id) + str(unit["stage"]) if not unit.is_empty() else "-",
			e.stance_choices.size(), me.hand.size(), me.coins, e.topics_rejected]
		if sig == _last_sig:
			# Si nada cambia en 25 s la partida se atascó: se avisa con lo que se ve en pantalla.
			if Time.get_ticks_msec() - _last_change_msec > 25000:
				_check(false, "atascado 25 s en fase %s (turno %d, activo %s, yo %s, juez %s). Pantalla: «%s» | «%s»" % [
					Phase.keys()[e.phase], e.turn_index, e.active.display_name if e.active != null else "-", me.display_name, e.judge.display_name,
					_table.get_node("%InstructionLabel").text, _table.get_node("%HintLabel").text])
				return
			continue
		_last_sig = sig
		_last_change_msec = Time.get_ticks_msec()
		await _act(e, me)
	_check(false, "la partida no terminó (posible bucle) en fase %s" % Phase.keys()[Net.mirror.phase])


## Un paso de la interfaz según la fase y mi rol.
func _act(e: DebateEngine, me: PlayerData) -> void:
	var judge := e.judge
	var hint: String = _table.get_node("%HintLabel").text
	match e.phase:
		Phase.STANCE:
			if me == judge:
				_check(not _btn("AgreeButton").visible, "el juez no elige postura")
				_check(hint != "", "el juez ve un aviso de espera")
				_waited_views += 1
			elif not e.stance_choices.has(me):
				_check(_btn("AgreeButton").visible and _btn("DisagreeButton").visible, "botones de postura visibles para el debatiente")
				_check(not _table.get_node("%Overlay").visible, "en línea no hay pantalla de relevo")
				await _shot("elegir_postura")
				_press(_btn("AgreeButton") if randf() < 0.5 else _btn("DisagreeButton"))
			else:
				_check(not _btn("AgreeButton").visible, "ya elegí: sin botones de postura")
				_waited_views += 1
		Phase.STANCE_RESULT:
			await _shot("posturas")
			# El juez (bot) también pulsa «continuar»: solo lo hago si la pantalla sigue ahí.
			await _wait(0.3)
			if Net.mirror.phase == Phase.STANCE_RESULT:
				_check(_btn("ActionButton").visible, "botón «continuar» visible tras revelar las posturas (instrucción: %s | pista: %s | me=%s juez=%s)" % [
					_table.get_node("%InstructionLabel").text, hint, me.display_name, judge.display_name])
				if _btn("ActionButton").visible:
					_press(_btn("ActionButton"))
		Phase.PLAY:
			if e.active == me:
				_my_turns += 1
				await _wait(0.6) # la mano se reparte con animación
				_check(not _table.get_node("%Overlay").visible, "mi turno: la mano se ve directo, sin relevo")
				_check(_stage.hand_card_count() == me.hand.size() + me.wilds.size(), "mi mano 3D tiene mis %d cartas (hay %d)" % [me.hand.size() + me.wilds.size(), _stage.hand_card_count()])
				await _shot("mi_turno")
				var playable := e.playable_cards(me)
				var c: CardData = playable[randi() % playable.size()]
				var pos := _stage.card_screen_position(c)
				_check(_stage.pick_card_at(pos) == c, "el rayo encuentra la carta '%s'" % c.title)
				await _click(pos)
				_check(_table._selected_card == c, "el clic selecciona la carta")
				_press(_btn("ActionButton"))
			else:
				_check(_stage.hand_card_count() == 0, "no es mi turno: no veo ninguna mano")
				_check(not _btn("ActionButton").visible, "no es mi turno: sin botón de acción")
				_check(hint.contains(e.active.display_name), "aviso de a quién se espera: %s" % hint)
				_waited_views += 1
				await _shot("espero_turno")
		Phase.RESPONSE:
			var responder := e.other(e.pending_wild_owner())
			if responder == me:
				await _wait(0.6)
				await _shot("respondo")
				_press(_btn("SkipButton"))
			else:
				_check(_stage.hand_card_count() == 0, "espero la respuesta del rival: sin mano")
				_waited_views += 1
		Phase.BRIBE:
			if me == judge:
				await _wait(0.3)
				var buttons := _judge_buttons()
				_check(buttons.size() == 2, "el juez ve aceptar / rechazar")
				_press(buttons[randi() % 2])
			else:
				_check(_table.get_node("%JudgePanel").get_child_count() == 0, "el soborno no se ve en la pantalla de los demás")
		Phase.APPEAL:
			if me == judge:
				_press(_judge_buttons()[0])
		Phase.SPEECH:
			var speaker := e.speaker()
			if speaker == me:
				await _wait(0.4)
				_check(_btn("ActionButton").visible, "quien habla ve «Terminar intervención»")
				_check(not _btn("InterruptButton").visible, "quien habla no puede interrumpirse")
				await _shot("hablo")
				_press(_btn("ActionButton"))
			elif me == judge:
				_check(not _btn("ActionButton").visible and not _btn("InterruptButton").visible, "el juez solo escucha")
			else:
				_check(_btn("InterruptButton").visible, "el rival puede interrumpir")
				_check(not _btn("ActionButton").visible, "el rival no puede terminar la intervención de otro")
		Phase.ANSWER:
			if e.current_unit()["player"] != me and me != judge:
				_press(_btn("ActionButton"))
		Phase.RESOLVE:
			if me == judge:
				await _wait(0.3)
				var buttons := _judge_buttons()
				_check(buttons.size() >= 2, "el juez ve los botones de puntaje o decisión")
				await _shot("juez")
				_judge_actions += 1
				_press(buttons[randi() % buttons.size()])
			else:
				_check(_table.get_node("%JudgePanel").get_child_count() == 0, "solo el juez ve los botones del juez")


func _final_step(e: DebateEngine) -> void:
	await _wait(0.5)
	var overlay: ColorRect = _table.get_node("%Overlay")
	_check(overlay.visible, "overlay final")
	var body: String = _table.get_node("%OverlayBody").text
	_check(body.contains(e.judge.display_name), "el final dice quién fue el juez")
	_check(_btn("OverlayButton").visible, "el anfitrión ve «Otra partida»")
	await _shot("final")
	await _wait(2.5) # los bots esperan 1 s tras el final antes de salir: que no vean cerrarse la sala antes
