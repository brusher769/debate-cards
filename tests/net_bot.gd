extends Node
## Cliente automático (bot) para probar el juego en línea SIN pantalla. Se conecta a un servidor,
## crea una sala o entra a una, y juega con acciones legales al azar usando solo lo que ve su motor
## espejo (igual que un jugador real). Lo lanza tests/run_online_test.sh; no se usa a mano.
##
## Opciones (después de "--"):
##   --address=127.0.0.1 --port=7777   servidor
##   --name=Ana                        nombre del jugador
##   --create                          crea la sala (si no, entra a la que diga --code-file)
##   --code-file=ruta                  el que crea escribe ahí el código; los demás lo leen
##   --games=N                         partidas seguidas que juega la sala (el anfitrión pide las nuevas)
##   --mode=normal|indefendible        modo de la sala
##   --leave-at-turn=N                 se sale de la sala al llegar al turno N (prueba de desconexión)
##   --timeout=S                       aborta a los S segundos
##   --verbose                         imprime cada acción que manda
##   --forge                           a veces manda acciones haciéndose pasar por el juez (el servidor debe rechazarlas)
##   --abuse                           prueba mensajes inválidos contra el servidor y termina
##   --host                            este bot aloja el servidor y juega a la vez (con --create)
## Imprime "BOT_DONE ..." si terminó bien.

var _address := "127.0.0.1"
var _port := Net.DEFAULT_PORT
var _name := "Bot"
var _create := false
var _code_file := ""
var _games := 1
var _mode := "normal"
var _leave_at := 0
var _timeout := 120.0
var _verbose := false
var _forge := false
var _abuse := false
var _host := false
var _forged := 0
var _abuse_errors: Array[String] = []

var _rng := RandomNumberGenerator.new()
var _games_done := 0
var _over_counted := false
var _last_sig := ""
var _chat_seen := 0
var _voice_seen := 0
var _rejected: Array[String] = []
var _elapsed := 0.0
var _joined_once := false
var _started_once := false
var _finish_timer := -1.0
var _stances_forced_same := false
var _stance_round := -1 ## en qué ronda de preguntas ya mandó su postura (para no mandarla dos veces)


func _ready() -> void:
	Settings.reset_to_defaults(false)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--address="):
			_address = arg.get_slice("=", 1)
		elif arg.begins_with("--port="):
			_port = int(arg.get_slice("=", 1))
		elif arg.begins_with("--name="):
			_name = arg.get_slice("=", 1)
		elif arg == "--create":
			_create = true
		elif arg.begins_with("--code-file="):
			_code_file = arg.get_slice("=", 1)
		elif arg.begins_with("--games="):
			_games = int(arg.get_slice("=", 1))
		elif arg.begins_with("--mode="):
			_mode = arg.get_slice("=", 1)
		elif arg.begins_with("--leave-at-turn="):
			_leave_at = int(arg.get_slice("=", 1))
		elif arg.begins_with("--timeout="):
			_timeout = float(arg.get_slice("=", 1))
		elif arg == "--verbose":
			_verbose = true
		elif arg == "--forge":
			_forge = true
		elif arg == "--abuse":
			_abuse = true
		elif arg == "--host":
			_host = true
	_rng.seed = hash(_name)
	Net.connected.connect(_on_connected)
	Net.connection_failed.connect(func() -> void: _fail("no pude conectar con el servidor"))
	Net.disconnected.connect(func() -> void: _finish("BOT_DISCONNECTED %s" % _name, 0))
	Net.joined.connect(_on_joined)
	Net.room_updated.connect(_on_room_updated)
	Net.error_received.connect(func(m: String) -> void: _rejected.append(m))
	Net.game_started.connect(_on_game_started)
	Net.state_received.connect(_on_state)
	Net.chat_received.connect(func(_who: String, _text: String) -> void: _chat_seen += 1)
	Net.voice_received.connect(func(_slot: int, data: PackedByteArray) -> void: _voice_seen += data.size())
	Net.room_closed.connect(_on_room_closed)
	var err := Net.host_here(_port) if _host else Net.connect_to(_address, _port)
	if err != OK:
		_fail("connect_to devolvió el error %d" % err)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed > _timeout:
		_fail("tiempo agotado (fase %s, partidas %d)" % [_phase_name(), _games_done])
	if _finish_timer >= 0.0:
		_finish_timer -= delta
		if _finish_timer < 0.0:
			# Todo intento de hacerse pasar por el juez debe haber recibido un rechazo (no es el turno del juez, o ya terminó).
			var refused := _rejected.filter(func(m: String) -> bool: return m.contains("juez") or m.contains("terminó")).size()
			if refused < _forged:
				_fail("el servidor aceptó %d acción(es) falsificada(s) como si fueran del juez" % (_forged - refused))
				return
			_finish("BOT_DONE %s games=%d chat=%d voice_bytes=%d rejected=%d forged=%d" % [_name, _games_done, _chat_seen, _voice_seen, _rejected.size(), _forged], 0)


func _phase_name() -> String:
	return DebateEngine.Phase.keys()[Net.mirror.phase] if Net.mirror != null else "sin partida"


func _fail(msg: String) -> void:
	printerr("BOT_FAIL %s: %s" % [_name, msg])
	for r in _rejected:
		printerr("  rechazada: ", r)
	get_tree().quit(1)


func _finish(msg: String, code: int) -> void:
	print(msg)
	for r in _rejected:
		print("  (acción rechazada: %s)" % r)
	get_tree().quit(code)


func _on_connected() -> void:
	if _abuse:
		_run_abuse()
		return
	if _create:
		Net.create_room(_name, _mode)
	else:
		_join_when_code_ready()


func _join_when_code_ready() -> void:
	for i in 200:
		if FileAccess.file_exists(_code_file):
			var code := FileAccess.get_file_as_string(_code_file).strip_edges()
			if code.length() == Net.CODE_LENGTH:
				Net.join_room(code, _name)
				return
		await get_tree().create_timer(0.1).timeout
	_fail("no apareció el código de la sala")


func _on_joined(info: Dictionary) -> void:
	if _create and not _joined_once:
		var f := FileAccess.open(_code_file, FileAccess.WRITE)
		f.store_string(str(info["code"]))
		f.close()
	_joined_once = true
	_on_room_updated(info)


func _on_room_updated(info: Dictionary) -> void:
	# El anfitrión empieza la partida cuando están los tres.
	if Net.is_host() and (info["names"] as Array).size() == Net.ROOM_SIZE and not _started_once:
		_started_once = true
		Net.start_game()


func _on_game_started() -> void:
	_over_counted = false
	_last_sig = ""
	_stance_round = -1
	if _games_done == 0:
		Net.send_chat("hola, soy %s" % _name) # ya estamos los tres en la sala
	# Un par de trozos de "voz" de mentira para probar el reenvío.
	var chunk := PackedByteArray()
	chunk.resize(320)
	Net.send_voice(chunk)


func _on_room_closed(reason: String) -> void:
	_finish("BOT_CLOSED %s: %s" % [_name, reason], 0)


func _on_state() -> void:
	var e := Net.mirror
	if e == null:
		return
	if e.phase == DebateEngine.Phase.OVER:
		if not _over_counted:
			_over_counted = true
			_games_done += 1
			_check_result(e)
			if _games_done >= _games:
				_finish_timer = 1.0 # deja que los demás también vean el final
			elif Net.is_host():
				await get_tree().create_timer(0.5).timeout
				Net.start_game()
		return
	if _leave_at > 0 and e.turn_index >= _leave_at:
		Net.leave_room()
		_finish("BOT_LEFT %s" % _name, 0)
		return
	# Se actúa una vez por situación distinta (la misma foto puede llegar repetida por la resincronización).
	var me := e.player_by_index(Net.my_slot)
	var unit := e.current_unit()
	var sig := "%d/%d/%s/%d/%d/%d/%d" % [e.phase, e.turn_index, str(unit["card"].id) + str(unit["stage"]) if not unit.is_empty() else "-",
		e.stance_choices.size(), me.hand.size(), me.wilds.size(), me.coins]
	if sig == _last_sig:
		return
	_last_sig = sig
	_act(e)


## Lo que el espejo debe tener al terminar una partida.
func _check_result(e: DebateEngine) -> void:
	if e.result.is_empty() or not e.result.has("reason"):
		_fail("el espejo no recibió el resultado final")
	var me := e.player_by_index(Net.my_slot)
	if me != e.judge and me.hand.size() > Config.hand_normals + 10:
		_fail("mano rara al terminar")
	for p in e.players:
		if p != me and (not p.hand.is_empty() or not p.wilds.is_empty()):
			_fail("el espejo tiene la mano del rival: ¡se filtró información!")


func _act(e: DebateEngine) -> void:
	var me := e.player_by_index(Net.my_slot)
	var judge := e.judge
	match e.phase:
		DebateEngine.Phase.STANCE:
			if me != judge and not e.stance_choices.has(me) and _stance_round != e.topics_rejected:
				_stance_round = e.topics_rejected
				# La primera vez los dos eligen lo mismo (pregunta descartada), después opuestas.
				var agree := _rng.randf() < 0.5
				if not _stances_forced_same and e.topics_rejected == 0:
					agree = true
					_stances_forced_same = true
				elif e.stance_choices.size() == 1 and e.topics_rejected > 0:
					agree = _rng.randf() < 0.5
				_send("stance", {"agree": agree})
		DebateEngine.Phase.STANCE_RESULT:
			if me == judge:
				_send("continue")
		DebateEngine.Phase.PLAY:
			if e.active == me:
				_play_turn(e, me)
		DebateEngine.Phase.RESPONSE:
			if e.pending_wild_owner() != me and me != judge:
				var options := e.response_options(me)
				if not options.is_empty() and _rng.randf() < 0.6:
					_send("respond", {"card": options[_rng.randi() % options.size()].id})
				else:
					_send("pass_response")
		DebateEngine.Phase.BRIBE:
			if me == judge:
				_send("bribe_decision", {"accept": _rng.randf() < 0.5})
		DebateEngine.Phase.APPEAL:
			if me == judge:
				_send("appeal_time", {"seconds": Config.appeal_options[_rng.randi() % Config.appeal_options.size()]})
		DebateEngine.Phase.SPEECH:
			_speech(e, me)
		DebateEngine.Phase.ANSWER:
			if me != judge and e.current_unit()["player"] != me:
				_send("end_answer")
		DebateEngine.Phase.RESOLVE:
			if _forge and me != judge and _rng.randf() < 0.5:
				# Me hago pasar por el juez: el servidor pone mi lugar y el motor lo rechaza.
				_forged += 1
				_send("score", {"points": 5, "player": judge.index})
			if me == judge:
				var card: CardData = e.current_unit()["card"]
				if card.scoring == CardData.Scoring.DECISION:
					_send("decide", {"passes": _rng.randf() < 0.5})
				else:
					_send("score", {"points": Config.judge_points[_rng.randi() % Config.judge_points.size()]})


func _play_turn(e: DebateEngine, me: PlayerData) -> void:
	if e.can_swap_wild(me) and _rng.randf() < 0.15:
		_send("swap_wild")
		return # llegará una foto nueva con el comodín nuevo y se decide entonces
	if _rng.randf() < 0.5:
		var options: Array[Dictionary] = []
		for w in me.wilds:
			var params := {}
			if w.effect == "bribe":
				params["amount"] = _rng.randi_range(1, maxi(me.coins, 1))
			if w.effect == "peek":
				params["buy_extra"] = _rng.randf() < 0.5
			if e.check_wild(me, w, params) == "":
				params["card"] = w.id
				options.append(params)
		if not options.is_empty():
			_send("play_wild", options[_rng.randi() % options.size()])
			return
	var playable := e.playable_cards(me)
	if not playable.is_empty():
		_send("play_card", {"card": playable[_rng.randi() % playable.size()].id})


func _speech(e: DebateEngine, me: PlayerData) -> void:
	var speaker := e.speaker()
	if speaker == me:
		# Habla un ratito y termina (así el rival tiene tiempo de interrumpir).
		var sig := _last_sig
		await get_tree().create_timer(0.25).timeout
		if sig == _last_sig and Net.mirror != null and Net.mirror.phase == DebateEngine.Phase.SPEECH:
			_send("end_speech")
	elif me != e.judge:
		var options := e.interrupt_cards(me)
		if not options.is_empty() and _rng.randf() < 0.3:
			var c := options[_rng.randi() % options.size()]
			_send("play_wild" if c.is_wild() else "play_card", {"card": c.id})


func _send(type: String, extra := {}) -> void:
	var action := {"type": type}
	action.merge(extra)
	if _verbose:
		print("[%s] %s  (fase %s, turno %d)" % [_name, action, _phase_name(), Net.mirror.turn_index])
	Net.send_action(action)


## Manda mensajes que un cliente honesto nunca mandaría y comprueba que el servidor los rechaza.
func _run_abuse() -> void:
	var errors: Array[String] = []
	Net.error_received.connect(func(m: String) -> void: errors.append(m))
	var chats: Array[String] = []
	Net.chat_received.connect(func(_who: String, text: String) -> void: chats.append(text))

	Net.join_room("ZZZZ", "Abusón")
	await get_tree().create_timer(0.4).timeout
	_expect(errors, "No existe la sala", "unirse a una sala que no existe")
	Net.send_action({"type": "stance", "agree": true, "player": 2})
	await get_tree().create_timer(0.4).timeout
	_expect(errors, "No hay una partida en curso", "actuar sin estar en una sala")
	Net.create_room("Abusón", "normal")
	await get_tree().create_timer(0.4).timeout
	Net.create_room("Abusón otra vez", "normal")
	await get_tree().create_timer(0.4).timeout
	_expect(errors, "Ya estás en una sala", "crear otra sala estando dentro de una")
	Net.start_game()
	await get_tree().create_timer(0.4).timeout
	_expect(errors, "Hacen falta 3 jugadores", "empezar sin los 3 jugadores")
	Net.send_action({"type": "play_card", "card": "argumentar", "player": 1})
	await get_tree().create_timer(0.4).timeout
	_expect(errors, "No hay una partida en curso", "actuar antes de que empiece la partida")
	Net.send_chat("x".repeat(600))
	await get_tree().create_timer(0.4).timeout
	if chats.is_empty() or chats[0].length() > Net.MAX_CHAT:
		_abuse_errors.append("un chat de 600 letras debía cortarse a %d" % Net.MAX_CHAT)
	Net.send_chat("     ")
	await get_tree().create_timer(0.3).timeout
	if chats.size() != 1:
		_abuse_errors.append("un chat vacío no debe reenviarse")
	Net.send_action({"a": 1, "b": 2, "c": 3, "d": 4, "e": 5, "f": 6, "g": 7, "h": 8, "i": 9, "j": 10, "k": 11, "l": 12, "m": 13})
	await get_tree().create_timer(0.4).timeout
	Net.leave_room()
	Net.join_room("ZZZZ", "Abusón") # ya fuera de la sala: sigue pudiendo pedir cosas sin romper nada
	await get_tree().create_timer(0.4).timeout
	if _abuse_errors.is_empty():
		_finish("BOT_ABUSE_OK", 0)
	else:
		for m in _abuse_errors:
			printerr("  fallo: ", m)
		_fail("el servidor no rechazó algo que debía")


func _expect(errors: Array[String], fragment: String, what: String) -> void:
	if not errors.any(func(m: String) -> bool: return m.contains(fragment)):
		_abuse_errors.append("%s: se esperaba un error con «%s» y llegó %s" % [what, fragment, str(errors)])
