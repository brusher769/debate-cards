extends Node
## Prueba de humo de la mesa 3D: juega una partida entera pulsando botones y haciendo clic con
## el mouse sobre las cartas 3D (proyección del rayo incluida): posturas (incluido el caso de dos
## posturas iguales), turnos, comodines con parámetros, respuestas, interrupciones, soborno privado,
## Apelación, decisiones del juez y el final.
## Necesita render real: NO sirve con --headless (ese modo no crea mallas 3D). En Windows basta
## abrir esta escena en el editor y darle a F6. En Linux sin pantalla:
##   xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/ui_smoke.tscn
## Imprime "UI OK" si todo pasó. Con la variable de entorno SHOT_DIR guarda una captura de
## cada estado. Con TEST_LANG=en juega la partida en inglés (por defecto, español), con
## TEST_ASPECT=4:3 (o 16:10, 21:9...) con esa relación de aspecto y con TEST_MODE=indefendible en
## el modo Lo Indefendible.

const Phase := DebateEngine.Phase
## Turno -> comodín que se le da al jugador de ese turno, para probar en pantalla los que piden
## parámetros (Soborno, Lupa) y una respuesta compatible.
const FORCED_WILDS := {1: "soborno", 2: "lupa", 3: "cautela", 4: "robar_carta", 5: "inocente"}
## Turno -> carta normal que ese jugador debe jugar (se le agrega a la mano si no la tiene): así se
## recorren en pantalla la Apelación, una pregunta con respuesta y una decisión del juez.
const FORCED_CARDS := {2: "apelacion", 3: "interrogar", 4: "incriminacion"}

var _lang := "es"
var _mode := "normal"
var _failures := 0
var _table: Node3D
var _stage: Stage3D
var _engine: DebateEngine
var _shot_dir := ""
var _shot_n := 0
var _clash_seen := false ## la primera vez los dos eligen lo mismo para probar la pregunta nueva
var _forced := {}
var _coverage := {} ## fases de la interfaz que se llegaron a ver
var _bribe_note_for := -1 ## jugador que debe ver el aviso privado del juez en su próxima mano


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FALLO: ", msg)


func _ready() -> void:
	_shot_dir = OS.get_environment("SHOT_DIR")
	_run.call_deferred()


func _run() -> void:
	if OS.get_environment("TEST_LANG") != "":
		_lang = OS.get_environment("TEST_LANG")
	if OS.get_environment("TEST_MODE") != "":
		_mode = OS.get_environment("TEST_MODE")
	Settings.reset_to_defaults(false) # sin escribir tus ajustes guardados
	Settings.set_language(_lang)
	if OS.get_environment("TEST_ASPECT") != "": # por ejemplo TEST_ASPECT=4:3
		Settings.set_aspect(OS.get_environment("TEST_ASPECT"))
		await _frames(4)
	var names: Array[String] = ["Ana", "Beto", "Caro"]
	GameState.new_room(names, _mode)
	GameState.start_game()
	_engine = GameState.engine
	_table = load("res://scenes/table.tscn").instantiate()
	add_child(_table)
	_stage = _table.get_node("%Stage")
	await _frames(2)
	await _play()
	if _mode == "normal":
		_check(_clash_seen, "se probó el caso de dos posturas iguales (pregunta nueva)")
	for phase_name in ["STANCE_RESULT", "PLAY", "RESPONSE", "BRIBE", "APPEAL", "ANSWER", "SPEECH", "RESOLVE"]:
		_check(_coverage.has(phase_name), "la prueba pasó por la fase %s" % phase_name)
	if _failures == 0:
		print("UI OK (fases vistas: %s)" % ", ".join(_coverage.keys()))
	else:
		printerr("UI CON FALLOS: ", _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _btn(node_name: String) -> Button:
	return _table.get_node("%" + node_name)


func _press(b: Button) -> void:
	_check(b.visible and not b.disabled, "botón '%s' debe estar activo (texto: %s)" % [b.name, b.text])
	b.pressed.emit()


func _shot(label: String) -> void:
	if _shot_dir == "":
		return
	await _wait(1.1) # deja terminar el movimiento de cámara y las animaciones
	await RenderingServer.frame_post_draw
	_shot_n += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [_shot_dir, _shot_n, label])


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


## Hace clic (con el mouse simulado) sobre una carta 3D de la mano y comprueba que se seleccionó.
func _click_card(c: CardData) -> void:
	var pos := _stage.card_screen_position(c)
	_check(_stage.pick_card_at(pos) == c, "el rayo desde %s encuentra la carta '%s'" % [pos, c.title])
	await _click(pos)
	_check(_table._selected_card == c, "el clic selecciona la carta '%s'" % c.title)
	_check(not _btn("ActionButton").disabled, "al elegir carta se activa el botón")


func _handoff(label: String) -> void:
	var overlay: ColorRect = _table.get_node("%Overlay")
	_check(overlay.visible, "overlay de relevo (%s)" % label)
	await _shot("relevo_" + label)
	_press(_btn("OverlayButton"))
	await _wait(0.6) # las cartas de la mano se reparten con animación
	_check(not overlay.visible, "el overlay se oculta (%s)" % label)


## Botones que el juez tiene delante (los arma el HUD en %JudgePanel).
func _judge_buttons() -> Array[Button]:
	var out: Array[Button] = []
	var panel: VBoxContainer = _table.get_node("%JudgePanel")
	_check(panel.visible, "el panel del juez está visible")
	for row in panel.get_children():
		for b in row.get_children():
			if b is Button:
				out.append(b)
	return out


func _pick(list: Array) -> Variant:
	return list[randi() % list.size()]


func _play() -> void:
	var overlay: ColorRect = _table.get_node("%Overlay")
	var guard := 0
	while guard < 400:
		guard += 1
		await _frames(2)
		var e := _engine
		_coverage[Phase.keys()[e.phase]] = true
		match e.phase:
			Phase.STANCE:
				await _stance_step()
			Phase.STANCE_RESULT:
				var text: String = _table.get_node("%InstructionLabel").text
				if e.stances_opposite:
					_check(text.contains(e.debaters[0].display_name) and text.contains(e.debaters[1].display_name), "el juez ve quién defiende qué")
					await _shot("posturas")
				else:
					_clash_seen = true
					await _shot("sin_debate")
				_press(_btn("ActionButton"))
			Phase.PLAY:
				await _play_turn()
			Phase.RESPONSE:
				await _response_step()
			Phase.BRIBE:
				await _bribe_step()
			Phase.APPEAL:
				var buttons := _judge_buttons()
				_check(buttons.size() == Config.appeal_options.size(), "un botón por cada tiempo que puede conceder el juez")
				await _shot("apelacion")
				_press(_pick(buttons))
			Phase.SPEECH:
				if await _speech_step():
					pass
			Phase.ANSWER:
				_check(_table.get_node("%TimerLabel").text != "", "el cronómetro de la respuesta corre")
				_press(_btn("ActionButton"))
			Phase.RESOLVE:
				var card: CardData = e.current_unit()["card"]
				var buttons := _judge_buttons()
				if card.scoring == CardData.Scoring.DECISION:
					_check(buttons.size() == 2, "una decisión tiene dos botones: procede / no procede")
					await _shot("juez_decision")
				else:
					_check(buttons.size() == Config.judge_points.size(), "un botón por cada puntaje del juez")
					_check(buttons.map(func(b: Button) -> String: return b.text) == Config.judge_points.map(func(n: int) -> String: return "%+d" % n), "los botones muestran +5 / -2 / -1")
					await _shot("juez_puntaje")
				_press(_pick(buttons))
			Phase.OVER:
				await _final_step(overlay)
				return
	_check(false, "la partida no terminó (posible bucle) en fase %s" % Phase.keys()[_engine.phase])


func _stance_step() -> void:
	var e := _engine
	if _table._topic_seen != e.topic:
		_check(_btn("ActionButton").visible, "botón para elegir postura")
		_check(_table.get_node("%TopicLabel").text.contains(e.topic), "se ve la pregunta")
		await _shot("pregunta")
		_press(_btn("ActionButton"))
		return
	await _handoff("postura")
	_check(_btn("AgreeButton").visible and _btn("DisagreeButton").visible, "botones De acuerdo / En desacuerdo")
	_check(not _btn("ActionButton").visible, "sin botón de acción mientras se elige postura")
	await _shot("elegir_postura")
	# La primera vez los dos eligen lo mismo (sin debate); después, posturas opuestas.
	var agree := true
	if _clash_seen:
		var first := e.debaters[0]
		agree = randf() < 0.5 if not e.stance_choices.has(first) else not e.stance_choices[first]
	_press(_btn("AgreeButton") if agree else _btn("DisagreeButton"))


func _play_turn() -> void:
	var e := _engine
	var p := e.active
	_check(_table.get_node("%RoundLabel").text.contains(str(e.turn_index)), "el marcador muestra el turno")
	# Comodines de prueba para los primeros turnos (una sola vez por turno).
	if FORCED_WILDS.has(e.turn_index) and not _forced.has(e.turn_index) and p.wilds.size() == 1 and not p.wild_played:
		_forced[e.turn_index] = true
		p.wilds.assign([e.catalog.by_id(FORCED_WILDS[e.turn_index])])
	if FORCED_CARDS.has(e.turn_index) and not p.hand.any(func(c: CardData) -> bool: return c.id == FORCED_CARDS[e.turn_index]):
		p.hand.append(e.catalog.by_id(FORCED_CARDS[e.turn_index]))
	var hand_before := p.hand.size()
	# Notas privadas del juez sobre un soborno: solo las ve quien sobornó, al ver su mano.
	var instr: Label = _table.get_node("%InstructionLabel")
	var hint: Label = _table.get_node("%HintLabel")
	if _bribe_note_for >= 0:
		_check(not instr.text.contains(tr("EV_BRIBE_REJECTED")) and not hint.text.contains(tr("EV_BRIBE_REJECTED")), "el aviso privado no se ve antes de pasar el control")
	await _handoff("turno")
	_check(_stage.hand_card_count() == p.hand.size() + p.wilds.size(), "la mano 3D tiene %d cartas (hay %d)" % [p.hand.size() + p.wilds.size(), _stage.hand_card_count()])
	_check(_btn("ActionButton").disabled, "no se puede jugar sin elegir carta")
	if _bribe_note_for == p.index:
		_bribe_note_for = -1
		var t := instr.text
		_check(t.contains("ACEPT") or t.contains("RECHAZ") or t.contains("ACCEPT") or t.contains("REFUS"), "quien sobornó ve la decisión del juez en privado (%s)" % t)
	await _shot("mano_turno")
	# Clic en una carta de interrupción (no jugable en tu turno): no debe seleccionarla.
	for c in p.hand:
		if c.is_interrupt():
			await _click(_stage.card_screen_position(c))
			_check(_table._selected_card == null, "una carta no jugable no se puede elegir")
			break
	# Cambiar el comodín cuesta una moneda (a veces).
	if _btn("SwapButton").visible and randf() < 0.3 and not FORCED_WILDS.has(e.turn_index):
		var coins := p.coins
		_press(_btn("SwapButton"))
		await _wait(0.6)
		_check(p.coins == coins - Config.swap_cost, "cambiar el comodín cuesta %d moneda" % Config.swap_cost)
		_check(_engine.active == p and _engine.phase == Phase.PLAY, "cambiar el comodín no cambia el turno")
		_check(not _table.get_node("%Overlay").visible, "tras cambiar el comodín la mano sigue a la vista")
	# ¿Juega el comodín antes de la carta normal?
	var wild: CardData = null
	if not p.wilds.is_empty() and randf() < 0.55 or FORCED_WILDS.has(e.turn_index) and not p.wilds.is_empty():
		var options := p.wilds.filter(func(w: CardData) -> bool: return e.check_wild(p, w, {"amount": 1}) == "")
		if not options.is_empty():
			wild = options[0]
	if wild != null:
		await _click_card(wild)
		var params: HBoxContainer = _table._param_row
		if wild.effect == "bribe":
			_check(params.visible, "el Soborno pide cuántas monedas ofrecer")
			_table._amount.value = 2
			await _shot("soborno_monto")
		elif wild.effect == "peek":
			_check(params.visible, "la Lupa ofrece comprar el comodín extra")
			_table._extra_check.button_pressed = true
		else:
			_check(not params.visible, "los demás comodines no piden parámetros")
		_press(_btn("ActionButton"))
		await _frames(2)
		return
	# Carta normal.
	var playable := e.playable_cards(p)
	_check(not playable.is_empty(), "hay una carta normal jugable")
	var chosen: CardData = _pick(playable)
	if FORCED_CARDS.has(e.turn_index):
		chosen = e.catalog.by_id(FORCED_CARDS[e.turn_index])
		for c in playable:
			if c.id == chosen.id:
				chosen = c
	await _click_card(chosen)
	await _shot("carta_elegida")
	_press(_btn("ActionButton"))
	await _frames(2)
	_check(p.hand.size() == hand_before - 1 or e.phase == Phase.OVER, "la carta jugada sale de la mano")


func _response_step() -> void:
	var e := _engine
	var responder := e.other(e.pending_wild_owner())
	var title: String = _table.get_node("%OverlayTitle").text
	_check(title.contains(responder.display_name), "el relevo es para quien responde (%s)" % title)
	_check(_table.get_node("%OverlayBody").text.contains(e.pending_wild().title), "el aviso dice qué comodín se jugó")
	# Mientras se pasa el control, el reloj de la ventana de respuesta no corre.
	var t0 := e.time_left()
	await _wait(0.5)
	_check(is_equal_approx(e.time_left(), t0), "el reloj se detiene mientras se pasa el control")
	await _handoff("respuesta")
	var options := e.response_options(responder)
	await _shot("respuesta")
	if not options.is_empty() and randf() < 0.6 and e.pending_wild().effect != "bribe":
		await _click_card(options[0])
		_press(_btn("ActionButton"))
	else:
		_press(_btn("SkipButton"))


func _bribe_step() -> void:
	var instr: String = _table.get_node("%InstructionLabel").text
	var amount: int = _engine.pending_bribe()["amount"]
	_check(not instr.contains(str(amount)) or amount == 0, "el monto del soborno no se ve antes del relevo")
	await _handoff("soborno")
	var buttons := _judge_buttons()
	_check(buttons.size() == 2, "el juez puede aceptar o rechazar")
	_check(_table.get_node("%JudgePanel").get_child(0).text.contains(str(amount)), "el juez sí ve el monto")
	await _shot("soborno_juez")
	_bribe_note_for = (_engine.pending_bribe()["player"] as PlayerData).index
	_press(buttons[randi() % 2])


## Devuelve true si interrumpió. Si no, termina la intervención.
func _speech_step() -> bool:
	var e := _engine
	var u := e.current_unit()
	var speaker: PlayerData = u["player"]
	_check(_table.get_node("%TimerLabel").text != "", "el cronómetro de la intervención corre")
	_check(_table.get_node("%InstructionLabel").text.contains(speaker.display_name), "se ve quién habla")
	_check(_btn("InterruptButton").visible, "el rival puede interrumpir")
	# Después de unos turnos el reloj de la partida pasa de 10 minutos: el juez puede terminarla.
	if e.turn_index >= 9:
		e.clock = 700.0
		_table._update_labels()
		_check(_btn("JudgeEndButton").visible, "el juez puede terminar la partida pasados 10 minutos")
		await _shot("juez_termina")
		_press(_btn("JudgeEndButton"))
		return false
	await _shot("discurso")
	# Interrupciones: en los turnos 5 y 6 se prueban a propósito una Objeción y una Refutar; antes
	# no hay ninguna (para que los turnos de prueba anteriores salgan siempre igual) y después son al azar.
	var forced_id := ""
	if e.turn_index == 5 and not _forced.has("i5"):
		forced_id = "objecion"
		_forced["i5"] = true
	elif e.turn_index == 6 and not _forced.has("i6"):
		forced_id = "refutar"
		_forced["i6"] = true
	if forced_id != "" or (e.turn_index > 6 and randf() < 0.35):
		if forced_id != "":
			var forced_rival := e.other(speaker)
			if not forced_rival.hand.any(func(c: CardData) -> bool: return c.id == forced_id):
				forced_rival.hand.append(e.catalog.by_id(forced_id))
		_press(_btn("InterruptButton"))
		await _wait(0.2)
		# Mientras el rival elige su carta para interrumpir, la intervención queda en pausa.
		var t0 := e.time_left()
		await _wait(0.4)
		_check(is_equal_approx(e.time_left(), t0), "la intervención queda en pausa mientras se elige interrumpir")
		var rival := e.other(speaker)
		_press(_btn("OverlayButton"))
		await _wait(0.6)
		var options := e.interrupt_cards(rival)
		if options.is_empty():
			_check(_btn("SkipButton").visible, "sin cartas para interrumpir se puede cancelar")
			_press(_btn("SkipButton"))
			await _frames(2)
			_check(e.phase == Phase.SPEECH and e.speaker() == speaker, "cancelar deja seguir la intervención")
			_press(_btn("ActionButton"))
		else:
			var pick_card: CardData = options[0]
			for c in options:
				if c.id == forced_id:
					pick_card = c
			await _click_card(pick_card)
			await _shot("interrumpir")
			_press(_btn("ActionButton"))
		return true
	_press(_btn("ActionButton"))
	return false


func _final_step(overlay: ColorRect) -> void:
	await _frames(2)
	_check(overlay.visible, "overlay final")
	var title: String = _table.get_node("%OverlayTitle").text
	_check(title.begins_with("¡Fin" if _lang == "es" else "Game over"), "título de fin de partida")
	var body: String = _table.get_node("%OverlayBody").text
	_check(body.contains(_engine.judge.display_name), "el final dice quién fue el juez")
	_check(body.contains("puntos" if _lang == "es" else "points"), "el final muestra los puntos")
	_check(_btn("OverlayButton").visible and _btn("OverlayButton2").visible, "botones: otra partida y volver al menú")
	await _shot("final")
