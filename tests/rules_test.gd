extends Node
## Pruebas del motor de reglas (DebateEngine): una comprobación por cada carta normal, cada comodín
## y cada condición de fin de REGLAS_DEBATE.md, más los casos límite. No necesita pantalla:
##   godot --headless --path . res://tests/rules_test.tscn
## Imprime "REGLAS OK (n comprobaciones)" si todo pasó.

var _failures := 0
var _checks := 0
var _seed := 100

var e: DebateEngine
var players: Array[PlayerData] = []
var judge: PlayerData
var pa: PlayerData ## el que tiene el primer turno
var pb: PlayerData


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FALLO: ", msg)


func _ready() -> void:
	Settings.reset_to_defaults(false)
	Settings.set_language("es")
	for t in get_method_list():
		var n: String = t["name"]
		if n.begins_with("test_"):
			call(n)
	if _failures == 0:
		print("REGLAS OK (%d comprobaciones)" % _checks)
	else:
		printerr("REGLAS CON FALLOS: %d" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


# ---------------------------------------------------------------------------
# Ayudas
# ---------------------------------------------------------------------------

## Crea una partida con posturas opuestas ya reveladas y el turno empezado. pa = quien empieza.
func _game(mode := "normal") -> void:
	players.clear()
	for i in 3:
		var p := PlayerData.new()
		p.display_name = "J%d" % i
		p.index = i
		players.append(p)
	judge = players[2]
	var rng := RandomNumberGenerator.new()
	_seed += 1
	rng.seed = _seed
	e = DebateEngine.create(CardCatalog.load_default(), players, judge, mode, func() -> String: return "Tema", rng)
	if mode == "normal":
		_do(_act("stance", players[0], {"agree": true}))
		_do(_act("stance", players[1], {"agree": false}))
	_do(_act("continue", judge))
	pa = e.active
	pb = e.other(pa)
	e.take_events()


func _act(type: String, p: PlayerData, extra := {}) -> Dictionary:
	var a := {"type": type, "player": p.index}
	a.merge(extra)
	return a


func _do(action: Dictionary) -> void:
	var r := e.apply(action)
	_check(r["ok"], "acción %s debe ser válida (%s)" % [action, r["error"]])


func _bad(action: Dictionary, msg: String) -> void:
	var before_phase := e.phase
	var r := e.apply(action)
	_check(not r["ok"], "%s debe rechazarse" % msg)
	_check(e.phase == before_phase, "una acción rechazada no cambia la fase (%s)" % msg)


func _hand(p: PlayerData, ids: Array) -> void:
	var list: Array[CardData] = []
	for id in ids:
		list.append(e.catalog.by_id(id))
	p.hand = list


func _wilds(p: PlayerData, ids: Array) -> void:
	var list: Array[CardData] = []
	for id in ids:
		list.append(e.catalog.by_id(id))
	p.wilds = list


func _play(p: PlayerData, id: String) -> void:
	_do(_act("play_card", p, {"card": id}))


func _wild(p: PlayerData, id: String, extra := {}) -> void:
	_do(_act("play_wild", p, extra.merged({"card": id})))


func _score(points: int) -> void:
	_do(_act("score", judge, {"points": points}))


## Juega una carta de puntaje libre completa: jugarla, hablar y que el juez puntúe.
func _speak(p: PlayerData, id: String, points: int) -> void:
	_play(p, id)
	_do(_act("end_speech", p))
	_score(points)


func _events_of(type: String) -> Array:
	return e.take_events().filter(func(ev: Dictionary) -> bool: return ev["type"] == type)


func _skip_response(responder: PlayerData) -> void:
	_do(_act("pass_response", responder))


# ---------------------------------------------------------------------------
# Preparación y posturas
# ---------------------------------------------------------------------------

func test_deal() -> void:
	_game()
	for p in [pa, pb]:
		var ids := {}
		for c: CardData in p.hand:
			ids[c.id] = true
		_check(p.hand.size() == 5 and ids.size() == 5, "5 cartas normales distintas por debatiente")
		_check(p.hand.all(func(c: CardData) -> bool: return not c.is_wild()), "la mano solo tiene cartas normales")
		_check(p.wilds.size() == 1 and p.wilds[0].is_wild(), "1 comodín por debatiente")
		_check(p.coins == 5, "5 monedas iniciales")
	_check(judge.hand.is_empty() and judge.wilds.is_empty(), "el juez no recibe cartas")
	# Monedas de sobornos no descubiertos: 5 + banco, máximo 10.
	var q := players[0]
	q.bank = 3
	var eng := DebateEngine.create(CardCatalog.load_default(), players, players[2], "normal", func() -> String: return "T")
	_check(players[0].coins == 8 and players[0].bank == 0, "5 + 3 monedas del banco")
	players[0].bank = 9
	eng = DebateEngine.create(CardCatalog.load_default(), players, players[2], "normal", func() -> String: return "T")
	_check(players[0].coins == 10, "tope de 10 monedas")
	_check(eng != null, "motor creado")


func test_stances() -> void:
	_game_no_start()
	_do(_act("stance", players[0], {"agree": true}))
	_bad(_act("stance", players[0], {"agree": false}), "elegir postura dos veces")
	_bad(_act("stance", judge, {"agree": true}), "el juez no elige postura")
	var v := e.view_for(players[1])
	_check(not v.has("stances"), "la postura de uno sigue oculta hasta que el otro elige")
	_do(_act("stance", players[1], {"agree": true})) # las dos iguales
	_check(e.phase == DebateEngine.Phase.STANCE_RESULT and not e.stances_opposite, "posturas iguales: sin debate")
	var first_topic := e.topic
	_do(_act("continue", judge))
	_check(e.phase == DebateEngine.Phase.STANCE and e.topics_rejected == 1 and e.topic != "", "posturas iguales: sale otra pregunta")
	_check(first_topic != "", "hay tema")
	_do(_act("stance", players[0], {"agree": true}))
	_do(_act("stance", players[1], {"agree": false}))
	_check(e.stances_opposite, "posturas opuestas: hay debate")
	_do(_act("continue", judge))
	_check(e.phase == DebateEngine.Phase.PLAY and e.turn_index == 1 and e.debaters.has(e.active), "empieza un debatiente")
	# Modo Indefendible: el juego asigna las posturas.
	_game("indefendible")
	_check(e.stance_choices[e.debaters[0]] != e.stance_choices[e.debaters[1]], "indefendible: posturas opuestas asignadas")


func _game_no_start() -> void:
	players.clear()
	for i in 3:
		var p := PlayerData.new()
		p.display_name = "J%d" % i
		p.index = i
		players.append(p)
	judge = players[2]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	e = DebateEngine.create(CardCatalog.load_default(), players, judge, "normal", func() -> String: return "Tema", rng)


# ---------------------------------------------------------------------------
# Turnos y las 13 cartas normales
# ---------------------------------------------------------------------------

func test_turn_rules() -> void:
	_game()
	_hand(pa, ["argumentar", "refutar", "objecion"])
	_hand(pb, ["argumentar"])
	_bad(_act("play_card", pb, {"card": "argumentar"}), "jugar fuera de turno")
	_bad(_act("end_speech", pa), "no se puede pasar el turno sin jugar carta")
	_bad(_act("play_card", pa, {"card": "refutar"}), "Refutar en tu propio turno")
	_bad(_act("play_card", pa, {"card": "objecion"}), "Objeción en tu propio turno")
	_bad(_act("play_card", pa, {"card": "ejemplo"}), "carta que no tienes")
	_play(pa, "argumentar")
	_check(pa.hand.size() == 2, "la carta jugada sale de la mano (sin reponer)")
	_check(e.phase == DebateEngine.Phase.SPEECH and e.time_left() == 60.0, "la intervención dura 60 s")
	_do(_act("end_speech", pa))
	_bad(_act("score", judge, {"points": 3}), "puntuar con un valor que no es +5/-2/-1")
	_bad(_act("score", pa, {"points": 5}), "solo el juez puntúa")
	_score(5)
	_check(pa.score == 5, "+5 del juez")
	_check(e.active == pb and e.phase == DebateEngine.Phase.PLAY and e.turn_index == 2, "los turnos se alternan")


func test_free_cards() -> void:
	for id in ["argumentar", "buscar_evidencia", "contraargumentar", "replanteamiento", "ejemplo"]:
		for pts in Config.judge_points:
			_game()
			_hand(pa, [id, "refutar"])
			_speak(pa, id, pts)
			_check(pa.score == pts, "%s: el juez puntúa %+d" % [id, pts])
			_check(pb.score == 0 and e.active == pb, "%s: turno del rival" % id)
	# Una carta de puntaje libre no se decide con procede/no procede.
	_game()
	_hand(pa, ["argumentar"])
	_play(pa, "argumentar")
	_do(_act("end_speech", pa))
	_bad(_act("decide", judge, {"passes": true}), "decidir una carta de puntaje libre")


func test_decision_cards() -> void:
	# id -> [procede: propio, rival] [no procede: propio, rival] (REGLAS_DEBATE.md sección 6)
	var table := {
		"incriminacion": [[0, -2], [-3, 0]],
		"interrogar": [[0, -1], [-1, 0]],
		"definicion": [[0, -1], [-1, 0]],
		"desafio": [[0, -1], [-1, 0]],
		"trampa_logica": [[0, -2], [-1, 0]],
	}
	for id in table:
		for passes in [true, false]:
			_game()
			_hand(pa, [id, "argumentar"])
			_play(pa, id)
			_do(_act("end_speech", pa))
			var card := e.catalog.by_id(id)
			if card.answer:
				_check(e.phase == DebateEngine.Phase.ANSWER and e.time_left() == 30.0, "%s: el rival responde 30 s" % id)
				_bad(_act("end_answer", pa), "%s: quien pregunta no cierra la respuesta" % id)
				_do(_act("end_answer", pb))
			else:
				_check(e.phase == DebateEngine.Phase.RESOLVE, "%s: pasa directo al juez" % id)
			_bad(_act("score", judge, {"points": 5}), "%s: una decisión no se puntúa con +5" % id)
			_do(_act("decide", judge, {"passes": passes}))
			var want: Array = table[id][0] if passes else table[id][1]
			_check(pa.score == want[0] and pb.score == want[1], "%s %s: propio %d, rival %d (fue %d y %d)" % [
				id, "procede" if passes else "no procede", want[0], want[1], pa.score, pb.score])
			_check(e.active == pb, "%s: sigue el rival" % id)


func test_refute() -> void:
	_game()
	_hand(pa, ["argumentar", "ejemplo"])
	_hand(pb, ["refutar", "replanteamiento"])
	_play(pa, "argumentar")
	_bad(_act("play_card", pb, {"card": "replanteamiento"}), "solo Refutar y Objeción interrumpen")
	_play(pb, "refutar") # interrumpe: termina de inmediato el turno de pa
	_check(e.phase == DebateEngine.Phase.RESOLVE, "Refutar termina la intervención rival de inmediato")
	_score(-1) # el juez puntúa lo que alcanzó a decir pa
	_check(pa.score == -1, "se puntúa lo dicho por quien fue interrumpido")
	_check(e.phase == DebateEngine.Phase.SPEECH and e.speaker() == pb and e.time_left() == 60.0, "quien refuta tiene 1 minuto")
	_do(_act("end_speech", pb))
	_score(5)
	_check(pb.score == 5, "la refutación la puntúa el juez")
	_check(e.active == pa, "tras la refutación sigue el turno del interrumpido (se alternan)")
	# Cadena de máximo 2: pa responde con su propia Refutar; una tercera no cabe.
	_game()
	_hand(pa, ["argumentar", "refutar", "ejemplo"])
	_hand(pb, ["refutar", "refutar", "ejemplo"])
	_play(pa, "argumentar")
	_play(pb, "refutar")
	_score(-1)
	_play(pa, "refutar") # respuesta: cadena de 2
	_score(-1) # puntúa la refutación interrumpida de pb
	_check(e.speaker() == pa, "la respuesta a la Refutar también habla 1 minuto")
	# La cadena ya llegó a 2: pb no puede refutar otra vez.
	_bad(_act("play_card", pb, {"card": "refutar"}), "tercera Refutar seguida")
	_do(_act("end_speech", pa))
	_score(5)
	_check(e.active == pb, "tras la cadena sigue el turno de pb")


func test_objection() -> void:
	# Procede.
	_game()
	_hand(pa, ["argumentar", "ejemplo"])
	_hand(pb, ["objecion", "ejemplo"])
	_play(pa, "argumentar")
	_play(pb, "objecion")
	_check(e.phase == DebateEngine.Phase.RESOLVE, "el juez decide la Objeción")
	_bad(_act("score", judge, {"points": 5}), "la Objeción no se puntúa con +5")
	_do(_act("decide", judge, {"passes": true}))
	_check(pa.score == -1 and pb.score == 1, "Objeción procede: rival -1, tú +1")
	_check(e.phase == DebateEngine.Phase.RESOLVE and e.current_unit()["player"] == pa, "el turno del rival termina y su intervención la puntúa el juez")
	_score(-2)
	_check(pa.score == -3, "se puntúa lo que pa alcanzó a decir")
	_check(e.phase == DebateEngine.Phase.SPEECH and e.speaker() == pb and e.time_left() == 60.0, "quien objetó toma la palabra 1 minuto")
	_check(pb.hand.size() == 1, "solo se gastó la carta Objeción")
	_do(_act("end_speech", pb))
	_check(e.phase == DebateEngine.Phase.PLAY and e.active == pa, "la palabra tomada no se puntúa y sigue el otro turno")
	_check(pb.score == 1, "sin puntaje extra para la palabra tomada")
	# No procede: la intervención del rival continúa con su tiempo.
	_game()
	_hand(pa, ["argumentar", "ejemplo"])
	_hand(pb, ["objecion", "ejemplo"])
	_play(pa, "argumentar")
	e.tick(20.0)
	_play(pb, "objecion")
	_do(_act("decide", judge, {"passes": false}))
	_check(pb.score == -1 and pa.score == 0, "Objeción no procede: tú -1")
	_check(e.phase == DebateEngine.Phase.SPEECH and e.speaker() == pa, "el rival sigue hablando")
	_check(is_equal_approx(e.time_left(), 40.0), "con el tiempo que le quedaba (%s)" % e.time_left())


func test_appeal() -> void:
	_game()
	_hand(pa, ["apelacion", "ejemplo"])
	_play(pa, "apelacion")
	_check(e.phase == DebateEngine.Phase.APPEAL, "Apelación espera al juez")
	_bad(_act("appeal_time", judge, {"seconds": 15}), "tiempo que no es 0, 30 o 60")
	_bad(_act("appeal_time", pb, {"seconds": 30}), "solo el juez concede tiempo")
	_do(_act("appeal_time", judge, {"seconds": 30}))
	_check(e.phase == DebateEngine.Phase.SPEECH and e.time_left() == 90.0, "60 s + 30 s concedidos")
	_do(_act("end_speech", pa))
	_score(5)
	_check(pa.score == 5 and e.active == pb, "el juez puntúa después y la Apelación cuenta como la carta del turno")
	for extra in [0, 60]:
		_game()
		_hand(pa, ["apelacion"])
		_play(pa, "apelacion")
		_do(_act("appeal_time", judge, {"seconds": extra}))
		_check(e.time_left() == 60.0 + extra, "Apelación con %d s extra" % extra)


func test_timers() -> void:
	_game()
	_hand(pa, ["interrogar", "ejemplo"])
	_play(pa, "interrogar")
	e.tick(61.0)
	_check(e.phase == DebateEngine.Phase.ANSWER, "al acabarse el tiempo termina la intervención")
	e.tick(31.0)
	_check(e.phase == DebateEngine.Phase.RESOLVE, "al acabarse la respuesta pasa al juez")
	_do(_act("decide", judge, {"passes": true}))
	_check(pb.score == -1, "decisión tras el tiempo")
	# Ventana de respuesta a un comodín: si se acaba, el comodín se resuelve.
	_game()
	_wilds(pa, ["cautela"])
	_wild(pa, "cautela")
	_check(e.phase == DebateEngine.Phase.RESPONSE and e.time_left() == 10.0, "ventana de respuesta de 10 s")
	e.tick(10.5)
	_check(e.phase == DebateEngine.Phase.PLAY and pb.blocked, "al acabarse la ventana el comodín surte efecto")


# ---------------------------------------------------------------------------
# Comodines
# ---------------------------------------------------------------------------

func test_bribe_accepted() -> void:
	_game()
	_hand(pa, ["argumentar", "ejemplo", "refutar", "desafio", "incriminacion"])
	_wilds(pa, ["soborno"])
	_bad(_act("play_wild", pa, {"card": "soborno", "amount": 6}), "sobornar con más monedas de las que tienes")
	_bad(_act("play_wild", pa, {"card": "soborno", "amount": 0}), "sobornar con 0 monedas")
	_wild(pa, "soborno", {"amount": 3})
	_check(e.phase == DebateEngine.Phase.RESPONSE, "el rival puede responder al Soborno")
	var played := _events_of("wild_played")
	_check(played.size() == 1 and played[0]["to"] == -1 and not played[0].has("amount"), "el rival ve el Soborno pero no el monto")
	_skip_response(pb)
	_check(e.phase == DebateEngine.Phase.BRIBE, "el juez decide en privado")
	_bad(_act("bribe_decision", pb, {"accept": true}), "solo el juez decide el soborno")
	_do(_act("bribe_decision", judge, {"accept": true}))
	_check(pa.hand.size() == 3, "Soborno aceptado: pierdes 2 cartas normales al azar")
	_check(pa.coins == 2 and judge.bank == 3, "las monedas van al juez")
	var ev := e.take_events()
	var secret := ev.filter(func(x: Dictionary) -> bool: return x["type"] == "bribe_decided")
	_check(secret.size() == 1 and secret[0]["to"] == pa.index and secret[0]["accepted"], "solo quien sobornó ve la decisión")
	_check(ev.filter(func(x: Dictionary) -> bool: return x["type"] == "bribe_answered" and x["to"] == -1 and not x.has("accepted")).size() == 1,
		"el rival solo sabe que el juez respondió")
	_check(e.phase == DebateEngine.Phase.PLAY and e.active == pa, "sigues en tu turno")
	# A partir de ahora el juez no puede bajarte más de -1 por intervención.
	pa.hand.assign([e.catalog.by_id("argumentar"), e.catalog.by_id("incriminacion")])
	_speak(pa, "argumentar", -2)
	_check(pa.score == -1, "-2 del juez se limita a -1 (%d)" % pa.score)
	_hand(pb, ["ejemplo", "argumentar"])
	_speak(pb, "ejemplo", -2)
	_check(pb.score == -2, "el límite solo protege al sobornador")
	_play(pa, "incriminacion")
	_do(_act("end_speech", pa))
	_do(_act("decide", judge, {"passes": false})) # -3 se limita a -1
	_check(pa.score == -2, "la decisión negativa también se limita a -1 (%d)" % pa.score)
	e.take_events()


func test_bribe_leaves_no_cards() -> void:
	# Un Soborno aceptado puede quitarte las 2 últimas cartas: sin cartas al tocarte, la partida termina.
	_game()
	_hand(pa, ["argumentar", "ejemplo"])
	_wilds(pa, ["soborno"])
	_wild(pa, "soborno", {"amount": 1})
	_skip_response(pb)
	_do(_act("bribe_decision", judge, {"accept": true}))
	_check(e.phase == DebateEngine.Phase.OVER and e.result["reason"] == "no_cards", "sin cartas tras el Soborno: fin de la partida")


func test_bribe_rejected() -> void:
	_game()
	_hand(pa, ["argumentar", "ejemplo", "refutar"])
	_wilds(pa, ["soborno"])
	_wild(pa, "soborno", {"amount": 2})
	_skip_response(pb)
	_do(_act("bribe_decision", judge, {"accept": false}))
	_check(pa.hand.size() == 3 and pa.coins == 5 and judge.bank == 0, "Soborno rechazado: nada cambia")
	_speak(pa, "argumentar", -2)
	_check(pa.score == -2, "sin escudo si el juez rechazó")


func test_verdict() -> void:
	# Acierto: el rival sobornó y el juez aceptó.
	_game()
	_hand(pa, ["argumentar", "ejemplo", "refutar", "desafio"])
	_wilds(pa, ["soborno"])
	_wilds(pb, ["veredicto"])
	_wild(pa, "soborno", {"amount": 2})
	_skip_response(pb)
	_do(_act("bribe_decision", judge, {"accept": true}))
	_check(judge.bank == 2, "el juez guarda las monedas mientras no lo descubran")
	_hand(pa, ["argumentar", "ejemplo"]) # el soborno aceptado quitó 2 cartas al azar
	_speak(pa, "argumentar", -1)
	_check(e.active == pb, "turno de pb")
	_wild(pb, "veredicto")
	_check(e.phase == DebateEngine.Phase.RESPONSE, "el Veredicto también abre ventana (Impugnación podría anularlo)")
	_skip_response(pa)
	_check(e.phase == DebateEngine.Phase.OVER, "Veredicto acertado termina la partida")
	_check(e.result["reason"] == "verdict" and e.result["winner"] == pb, "gana quien usó Veredicto")
	_check(e.judge_jailed and judge.bank == 0, "el juez va a la cárcel y pierde el soborno")
	# Gana aunque el sobornador tenga más puntos.
	_game()
	_hand(pa, ["argumentar", "ejemplo", "refutar", "desafio"])
	_hand(pb, ["ejemplo", "argumentar", "refutar"])
	_wilds(pa, ["soborno"])
	_wilds(pb, ["veredicto"])
	_speak(pa, "argumentar", 5)
	_speak(pb, "ejemplo", -1)
	_wild(pa, "soborno", {"amount": 1})
	_skip_response(pb)
	_do(_act("bribe_decision", judge, {"accept": true}))
	_hand(pa, ["ejemplo", "desafio"])
	_speak(pa, "ejemplo", 5)
	_check(pa.score == 10 and pb.score == -1, "el sobornador va ganando por mucho")
	_wild(pb, "veredicto")
	_skip_response(pa)
	_check(e.phase == DebateEngine.Phase.OVER and e.result["winner"] == pb, "Veredicto acertado: gana aunque el sobornador tenga más puntos")
	# Fallo: el juez rechazó el soborno -> quien usa Veredicto pierde 2.
	_game()
	_hand(pa, ["argumentar", "ejemplo", "refutar"])
	_wilds(pa, ["soborno"])
	_wilds(pb, ["veredicto"])
	_wild(pa, "soborno", {"amount": 1})
	_skip_response(pb)
	_do(_act("bribe_decision", judge, {"accept": false}))
	_speak(pa, "argumentar", 5)
	_wild(pb, "veredicto")
	_skip_response(pa)
	_check(e.phase != DebateEngine.Phase.OVER and pb.score == -2, "Veredicto sin soborno aceptado: -2 (%d)" % pb.score)
	# Veredicto sin soborno alguno.
	_game()
	_wilds(pb, ["veredicto"])
	_hand(pa, ["argumentar", "ejemplo"])
	_speak(pa, "argumentar", 5)
	_wild(pb, "veredicto")
	_skip_response(pa)
	_check(pb.score == -2 and e.phase == DebateEngine.Phase.PLAY, "Veredicto sin soborno: -2")
	# El propio sobornador no gana con su Veredicto.
	_game()
	_hand(pa, ["argumentar", "ejemplo", "desafio", "replanteamiento", "contraargumentar"])
	_wilds(pa, ["soborno", "veredicto"])
	_wild(pa, "soborno", {"amount": 1})
	_skip_response(pb)
	_do(_act("bribe_decision", judge, {"accept": true}))
	_wild(pa, "veredicto")
	_skip_response(pb)
	_check(e.phase != DebateEngine.Phase.OVER and pa.score == Config.verdict_fail_penalty,
		"Veredicto contra tu propio soborno falla (%d)" % pa.score)


func test_verdict_as_response() -> void:
	# Veredicto como respuesta directa al Soborno: se evalúa cuando el juez decide.
	for accept in [true, false]:
		_game()
		_hand(pa, ["argumentar", "ejemplo", "refutar"])
		_wilds(pa, ["soborno"])
		_wilds(pb, ["veredicto"])
		_wild(pa, "soborno", {"amount": 2})
		_do(_act("respond", pb, {"card": "veredicto"}))
		_check(e.phase == DebateEngine.Phase.BRIBE, "el soborno igual llega al juez")
		_do(_act("bribe_decision", judge, {"accept": accept}))
		if accept:
			_check(e.phase == DebateEngine.Phase.OVER and e.result["winner"] == pb, "aceptó: gana quien respondió con Veredicto")
		else:
			_check(e.phase == DebateEngine.Phase.PLAY and pb.score == -2, "rechazó: quien respondió con Veredicto pierde 2")


func test_steal() -> void:
	_game()
	_hand(pa, ["argumentar"])
	_hand(pb, ["ejemplo", "refutar"])
	_wilds(pa, ["robar_carta"])
	_wild(pa, "robar_carta")
	_skip_response(pb)
	_check(pa.hand.size() == 2 and pb.hand.size() == 1, "Robar carta: la carta pasa al rival")
	var moved := pa.hand.filter(func(c: CardData) -> bool: return c.id != "argumentar")
	_check(moved.size() == 1 and not pb.hand.has(moved[0]), "el rival la pierde")
	_check(pa.wilds.is_empty(), "el comodín queda gastado")
	# Puede dar una carta repetida (excepción a la regla de no repetir).
	_game()
	_hand(pa, ["argumentar"])
	_hand(pb, ["argumentar"])
	_wilds(pa, ["robar_carta"])
	_wild(pa, "robar_carta")
	_skip_response(pb)
	_check(pa.hand.size() == 2 and pa.hand[0].id == pa.hand[1].id, "Robar carta puede repetir carta")
	# Secreto neutraliza Robar carta.
	_game()
	_hand(pa, ["argumentar"])
	_hand(pb, ["ejemplo", "refutar"])
	_wilds(pa, ["robar_carta"])
	_wilds(pb, ["secreto"])
	_wild(pa, "robar_carta")
	_bad(_act("respond", pb, {"card": "cautela"}), "responder con un comodín que no tienes")
	_do(_act("respond", pb, {"card": "secreto"}))
	_check(pa.hand.size() == 1 and pb.hand.size() == 2, "Secreto: nadie te roba cartas")
	# Impugnación también lo anula.
	_game()
	_hand(pb, ["ejemplo"])
	_wilds(pa, ["robar_carta"])
	_wilds(pb, ["impugnacion"])
	_wild(pa, "robar_carta")
	_do(_act("respond", pb, {"card": "impugnacion"}))
	_check(pb.hand.size() == 1, "Impugnación anula el comodín del rival")
	# El rival sin cartas: no pasa nada.
	_game()
	_hand(pb, [])
	_wilds(pa, ["robar_carta"])
	_wild(pa, "robar_carta")
	_skip_response(pb)
	_check(e.phase == DebateEngine.Phase.PLAY, "robar de una mano vacía no rompe nada")


func test_secret_only_reactive() -> void:
	_game()
	_wilds(pa, ["secreto"])
	_bad(_act("play_wild", pa, {"card": "secreto"}), "Secreto solo se juega como respuesta")


func test_caution() -> void:
	# Cautela: el siguiente turno del rival se pierde.
	_game()
	_hand(pa, ["argumentar", "ejemplo", "replanteamiento"])
	_hand(pb, ["ejemplo", "refutar"])
	_wilds(pa, ["cautela"])
	_wild(pa, "cautela")
	_skip_response(pb)
	_check(pb.blocked, "Cautela bloquea al rival")
	_speak(pa, "argumentar", 5)
	_check(e.active == pa and not pb.blocked, "el turno bloqueado se pierde: vuelve a jugar pa")
	# Inocente responde a Cautela.
	_game()
	_wilds(pa, ["cautela"])
	_wilds(pb, ["inocente"])
	_hand(pa, ["argumentar", "ejemplo"])
	_wild(pa, "cautela")
	_do(_act("respond", pb, {"card": "inocente"}))
	_check(not pb.blocked and pb.innocent_left > 0, "Inocente protege de Cautela")
	# Impugnación responde a Cautela.
	_game()
	_wilds(pa, ["cautela"])
	_wilds(pb, ["impugnacion"])
	_wild(pa, "cautela")
	_do(_act("respond", pb, {"card": "impugnacion"}))
	_check(not pb.blocked, "Impugnación anula Cautela")
	# Un comodín que no es pareja no puede responder.
	_game()
	_wilds(pa, ["cautela"])
	_wilds(pb, ["secreto"])
	_wild(pa, "cautela")
	_bad(_act("respond", pb, {"card": "secreto"}), "Secreto no responde a Cautela")
	# Cautela con Inocente ya activo.
	_game()
	_hand(pb, ["ejemplo", "argumentar"])
	_hand(pa, ["argumentar", "ejemplo", "refutar"])
	_wilds(pb, ["inocente"])
	_speak(pa, "ejemplo", 5)
	_wild(pb, "inocente")
	_skip_response(pa)
	_speak(pb, "ejemplo", 5)
	_wilds(pa, ["cautela"])
	_wild(pa, "cautela")
	_skip_response(pb)
	_check(not pb.blocked, "Cautela no bloquea a quien tiene Inocente activo")


func test_innocent() -> void:
	_game()
	_hand(pa, ["incriminacion", "argumentar", "ejemplo"])
	_hand(pb, ["incriminacion", "ejemplo", "argumentar"])
	_wilds(pa, ["inocente"])
	_wild(pa, "inocente")
	_skip_response(pb)
	_play(pa, "incriminacion")
	_do(_act("end_speech", pa))
	_do(_act("decide", judge, {"passes": false})) # -3 -> -1
	_check(pa.score == -1, "Inocente limita la pérdida a -1 (%d)" % pa.score)
	# Dura hasta que termina el siguiente turno del rival: ahí también protege.
	_play(pb, "incriminacion")
	_do(_act("end_speech", pb))
	_do(_act("decide", judge, {"passes": true})) # pa perdería -2 -> -1
	_check(pa.score == -2, "Inocente también protege durante el turno del rival (%d)" % pa.score)
	# Después ya no.
	_check(pa.innocent_left == 0, "Inocente se gasta")
	_speak(pa, "argumentar", -2)
	_check(pa.score == -4, "sin Inocente vuelve a perder -2 (%d)" % pa.score)
	# El Veredicto fallido también lo respeta (cualquier pérdida se limita a -1).
	_game()
	_wilds(pb, ["veredicto"])
	pb.innocent_left = 2
	_hand(pa, ["argumentar", "ejemplo"])
	_speak(pa, "argumentar", 5)
	_wild(pb, "veredicto")
	_skip_response(pa)
	_check(pb.score == -1, "Veredicto fallido con Inocente activo: -2 se limita a -1 (%d)" % pb.score)


func test_cancel() -> void:
	# Impugnación proactiva: quita Inocente y Desacato del rival, y un bloqueo sobre uno mismo.
	_game()
	pb.innocent_left = 2
	pb.contempt = true
	pa.blocked = true
	pb.bribe_shield = true
	_wilds(pa, ["impugnacion"])
	_wild(pa, "impugnacion")
	_skip_response(pb)
	_check(pb.innocent_left == 0 and not pb.contempt and not pa.blocked, "Impugnación elimina beneficios activos y el bloqueo propio")
	_check(pb.bribe_shield, "Impugnación no deshace un Soborno ya aceptado")
	# Impugnación contra Impugnación.
	_game()
	_wilds(pa, ["impugnacion"])
	_wilds(pb, ["impugnacion"])
	pb.innocent_left = 2
	_wild(pa, "impugnacion")
	_do(_act("respond", pb, {"card": "impugnacion"}))
	_check(pb.innocent_left == 2, "la Impugnación respondida con otra Impugnación no surte efecto")


func test_contempt() -> void:
	# Puntos positivos se transfieren al rival.
	_game()
	_hand(pa, ["argumentar", "ejemplo"])
	_wilds(pa, ["desacato"])
	_wild(pa, "desacato")
	_skip_response(pb)
	_speak(pa, "argumentar", 5)
	_check(pa.score == 0 and pb.score == 5, "Desacato: los +5 van al rival")
	# Puntos negativos también se transfieren.
	_game()
	_hand(pa, ["argumentar", "ejemplo"])
	_wilds(pa, ["desacato"])
	_wild(pa, "desacato")
	_skip_response(pb)
	_speak(pa, "argumentar", -2)
	_check(pa.score == 0 and pb.score == -2, "Desacato: los -2 también van al rival")
	_hand(pb, ["ejemplo", "argumentar"])
	_speak(pb, "ejemplo", 5)
	_speak(pa, "ejemplo", 5)
	_check(pa.score == 5, "Desacato solo dura una resolución")
	# Con una decisión del juez: la primera resolución sobre ti.
	_game()
	_hand(pa, ["incriminacion", "ejemplo"])
	_wilds(pa, ["desacato"])
	_wild(pa, "desacato")
	_skip_response(pb)
	_play(pa, "incriminacion")
	_do(_act("end_speech", pa))
	_do(_act("decide", judge, {"passes": false})) # tú -3 -> se lo lleva el rival
	_check(pa.score == 0 and pb.score == -3, "Desacato con decisión: el -3 pasa al rival")


func test_precedent() -> void:
	_game()
	_wilds(pa, ["jurisprudencia"])
	_bad(_act("play_wild", pa, {"card": "jurisprudencia"}), "Jurisprudencia sin haber jugado una carta normal")
	_hand(pa, ["argumentar", "ejemplo", "replanteamiento"])
	_hand(pb, ["ejemplo", "argumentar", "replanteamiento", "contraargumentar", "refutar"])
	_speak(pa, "argumentar", 5)
	_speak(pb, "ejemplo", -1)
	_wild(pa, "jurisprudencia")
	_skip_response(pb)
	_check(e.active == pb and e.phase == DebateEngine.Phase.PLAY, "Jurisprudencia gasta tu turno completo")
	_check(pa.hand.size() == 2, "sin gastar ninguna carta")
	_speak(pb, "argumentar", 5)
	# Ahora el turno de pa repite Argumentar sin gastar la carta pero sí el turno.
	_check(e.phase == DebateEngine.Phase.SPEECH and e.speaker() == pa, "en tu siguiente turno repites la última carta")
	_check(e.current_unit()["card"].id == "argumentar" and e.current_unit()["repeat"], "es la última carta normal, repetida")
	_check(pa.hand.size() == 2, "la carta repetida no se gasta otra vez")
	_do(_act("end_speech", pa))
	_score(5)
	_check(pa.score == 10 and e.active == pb, "el juez puntúa la repetición y el turno se consumió")
	# La repetición no queda pendiente.
	_speak(pb, "replanteamiento", 5)
	_check(e.phase == DebateEngine.Phase.PLAY and e.active == pa and not pa.repeat_pending, "la repetición ocurre una sola vez")
	# Solo copia cartas normales: la última carta normal, no el comodín.
	_check(pa.last_normal.id == "argumentar", "solo copia cartas normales")


func test_end_wild() -> void:
	_game()
	_wilds(pa, ["end"])
	_bad(_act("play_wild", pa, {"card": "end"}), "END con pocos puntos y poco tiempo")
	# Con 20 puntos.
	pa.score = 20
	pb.score = 3
	_wild(pa, "end")
	_check(e.phase == DebateEngine.Phase.OVER, "END termina la partida de inmediato (no se puede responder)")
	_check(e.result["reason"] == "end" and e.result["winner"] == pa and not e.result["tie"], "gana quien tiene más puntos")
	# A los 5 minutos con cualquier puntaje.
	_game()
	_wilds(pa, ["end"])
	pa.score = 1
	pb.score = 4
	e.tick(299.0)
	_bad(_act("play_wild", pa, {"card": "end"}), "END a los 4:59")
	e.tick(2.0)
	_wild(pa, "end")
	_check(e.phase == DebateEngine.Phase.OVER and e.result["winner"] == pb, "END a los 5 min con cualquier puntaje: gana el que va arriba")
	# Empate.
	_game()
	_wilds(pa, ["end"])
	pa.score = 20
	pb.score = 20
	_wild(pa, "end")
	_check(e.result["tie"] and e.result["winner"] == null, "empate: sin ganador (la pantalla muestra «Empate»)")


func test_lupa_and_swap() -> void:
	_game()
	_wilds(pa, ["lupa"])
	_wilds(pb, ["cautela"])
	_wild(pa, "lupa", {"buy_extra": true})
	_skip_response(pb)
	var ev := e.take_events()
	var peek := ev.filter(func(x: Dictionary) -> bool: return x["type"] == "peek")
	_check(peek.size() == 1 and peek[0]["to"] == pa.index and peek[0]["wilds"] == ["cautela"], "la Lupa te muestra el comodín del rival (solo a ti)")
	_check(pa.coins == 4 and pa.wilds.size() == 1 and pa.wilds[0].effect != "peek", "comodín extra por 1 moneda")
	# Sin pagar el extra.
	_game()
	_wilds(pa, ["lupa"])
	_wild(pa, "lupa")
	_skip_response(pb)
	_check(pa.coins == 5 and pa.wilds.is_empty(), "sin comprar el extra no se gastan monedas")
	# Sin monedas no se puede comprar.
	_game()
	_wilds(pa, ["lupa"])
	pa.coins = 0
	_bad(_act("play_wild", pa, {"card": "lupa", "buy_extra": true}), "comprar el extra sin monedas")
	# Cambiar comodín.
	_game()
	_wilds(pa, ["cautela"])
	_do(_act("swap_wild", pa))
	_check(pa.coins == 4 and pa.wilds.size() == 1 and pa.wilds[0].id != "cautela", "cambiar el comodín cuesta 1 moneda y da uno nuevo")
	_bad(_act("swap_wild", pb), "cambiar comodín fuera de turno")
	pa.coins = 0
	_bad(_act("swap_wild", pa), "cambiar comodín sin monedas")
	pa.coins = 3
	_wilds(pa, ["lupa"])
	_wild(pa, "lupa")
	_skip_response(pb)
	_check(pa.wild_played, "ya usó un comodín")
	_wilds(pa, ["cautela"])
	_bad(_act("swap_wild", pa), "cambiar el comodín después de haber usado uno")


func test_response_window_rules() -> void:
	_game()
	_hand(pa, ["argumentar"])
	_wilds(pa, ["cautela"])
	_wilds(pb, ["inocente"])
	_wild(pa, "cautela")
	_bad(_act("play_card", pa, {"card": "argumentar"}), "no se juegan cartas normales durante la ventana")
	_bad(_act("pass_response", pa), "el que jugó el comodín no responde")
	_bad(_act("pass_response", judge), "el juez no responde")
	_bad(_act("respond", judge, {"card": "inocente"}), "el juez no responde")
	# Durante el turno del rival: Veredicto se puede jugar en cualquier momento.
	_game()
	_hand(pa, ["argumentar", "ejemplo"])
	_wilds(pb, ["veredicto"])
	_play(pa, "argumentar")
	_check(e.interrupt_cards(pb).any(func(c: CardData) -> bool: return c.id == "veredicto"), "Veredicto está disponible durante la intervención rival")
	_wild(pb, "veredicto")
	_check(e.phase == DebateEngine.Phase.RESPONSE, "ventana de respuesta")
	_skip_response(pa)
	_check(e.phase == DebateEngine.Phase.SPEECH and e.speaker() == pa and pb.score == -2, "tras Veredicto fallido la intervención continúa")


# ---------------------------------------------------------------------------
# Fin de partida
# ---------------------------------------------------------------------------

func test_no_cards_ends_game() -> void:
	_game()
	_hand(pa, ["argumentar"])
	_hand(pb, ["ejemplo"])
	_speak(pa, "argumentar", 5)
	_speak(pb, "ejemplo", -1)
	_check(e.phase == DebateEngine.Phase.OVER and e.result["reason"] == "no_cards", "sin cartas al tocarle: fin de la partida")
	_check(e.result["winner"] == pa, "gana quien tiene más puntos")
	# Solo quedan Refutar/Objeción: no hay carta jugable en tu turno.
	_game()
	_hand(pa, ["argumentar"])
	_hand(pb, ["refutar", "objecion"])
	_speak(pa, "argumentar", 5)
	_check(e.phase == DebateEngine.Phase.OVER, "solo cartas de interrupción: no hay nada que jugar en su turno")


func test_judge_end() -> void:
	_game()
	_bad(_act("judge_end", judge), "el juez no puede terminar antes de 10 min")
	e.tick(601.0)
	_check(e.can_judge_end(), "pasados 10 min el juez puede terminar")
	_bad(_act("judge_end", pa), "un debatiente no puede terminar la partida")
	_do(_act("judge_end", judge))
	_check(e.phase == DebateEngine.Phase.OVER and e.result["reason"] == "judge", "el juez termina la partida")
	# Es opcional: sin usarlo la partida sigue.
	_game()
	e.tick(700.0)
	_check(e.phase == DebateEngine.Phase.PLAY, "es un poder opcional del juez")


func test_tie() -> void:
	_game()
	_hand(pa, ["argumentar"])
	_hand(pb, ["ejemplo"])
	_speak(pa, "argumentar", -1)
	_speak(pb, "ejemplo", -1)
	_check(e.result["tie"] and e.result["winner"] == null, "empate: -1 a -1")


# ---------------------------------------------------------------------------
# Información oculta y datos
# ---------------------------------------------------------------------------

func test_privacy() -> void:
	_game()
	var v_rival := e.view_for(pb)
	_check(v_rival["you"]["hand"].size() == 5 and v_rival["you"]["coins"] == 5, "cada quien ve su propia mano y monedas")
	_check(v_rival["you"]["index"] == pb.index and v_rival["you"]["hand"] == pb.hand.map(func(c: CardData) -> String: return c.id),
		"la vista de pb trae solo la mano de pb")
	_check(not v_rival.has("hand") and not v_rival.has("coins") and not v_rival.has("wilds"), "nada de la mano, monedas o comodín del rival en la vista")
	var v_judge := e.view_for(judge)
	_check(not v_judge.has("you"), "el juez no tiene mano ni monedas")
	_check(not JSON.stringify(v_judge).contains("wilds") and not JSON.stringify(v_judge).contains("hand"), "el juez no ve ninguna mano ni comodín")
	# El rival no ve la decisión del juez sobre un soborno.
	_hand(pa, ["argumentar", "ejemplo", "refutar"])
	_wilds(pa, ["soborno"])
	_wild(pa, "soborno", {"amount": 2})
	_skip_response(pb)
	_do(_act("bribe_decision", judge, {"accept": true}))
	var public := e.take_events().filter(func(x: Dictionary) -> bool: return x["to"] == -1 or x["to"] == pb.index)
	_check(public.all(func(x: Dictionary) -> bool: return not x.has("accepted")), "ningún evento visible para el rival trae la decisión")
	_check(JSON.stringify(e.view_for(pb)).find("\"lost\"") == -1, "la vista del rival no trae las cartas perdidas")


## Manda la foto por el mismo camino que la red (serializar y leer) y arma el motor espejo de `p`.
func _mirror_of(p: PlayerData) -> DebateEngine:
	var wire: Dictionary = bytes_to_var(var_to_bytes(e.snapshot_for(p)))
	var m := DebateEngine.create_mirror(e.catalog)
	m.load_snapshot(wire)
	return m


func _ids(cards: Array) -> Array:
	return cards.map(func(c: CardData) -> String: return c.id)


func test_snapshot_and_mirror() -> void:
	_game()
	_hand(pa, ["argumentar", "refutar", "objecion", "ejemplo", "desafio"])
	_hand(pb, ["incriminacion", "refutar", "interrogar", "definicion", "replanteamiento"])
	_wilds(pa, ["soborno"])
	_wilds(pb, ["veredicto"])
	pa.coins = 4
	var m := _mirror_of(pa)
	var ma := m.player_by_index(pa.index)
	var mb := m.player_by_index(pb.index)
	_check(m.is_mirror and m.phase == e.phase and m.topic == e.topic and m.judge.index == judge.index, "el espejo copia fase, tema y juez")
	_check(m.active.index == pa.index and m.turn_index == e.turn_index, "el espejo copia de quién es el turno")
	_check(_ids(ma.hand) == _ids(pa.hand) and _ids(ma.wilds) == ["soborno"] and ma.coins == 4, "el espejo de pa ve su mano, comodín y monedas")
	_check(mb.hand.is_empty() and mb.wilds.is_empty() and mb.coins == 0, "...pero nada de la mano, comodín ni monedas del rival")
	_check(_ids(m.playable_cards(ma)) == _ids(e.playable_cards(pa)), "cartas jugables iguales en el espejo")
	_check(m.check_wild(ma, ma.wilds[0], {"amount": 2}) == e.check_wild(pa, pa.wilds[0], {"amount": 2}), "el espejo valida los comodines igual")
	# Lo que NO puede viajar en la foto de los demás.
	var snap_b := JSON.stringify(e.snapshot_for(pb))
	_check(not snap_b.contains("bribe_shield") and not snap_b.contains("\"soborno\""), "la foto de pb no trae el escudo ni el comodín de pa")
	var snap_j := e.snapshot_for(judge)
	_check(not snap_j.has("you") and not JSON.stringify(snap_j).contains("\"hand\""), "la foto del juez no trae ninguna mano")
	for entry in e.snapshot_for(pa)["players"]:
		_check(not entry.has("hand") and not entry.has("wilds") and not entry.has("coins"), "los datos públicos de cada jugador no traen mano, comodín ni monedas")
	# Posturas: cada quien solo sabe la suya hasta que las dos se revelan.
	_game_no_start()
	_do(_act("stance", players[0], {"agree": true}))
	var s0 := e.snapshot_for(players[0])
	var s1 := e.snapshot_for(players[1])
	_check(s0["stances"] == {0: true} and s1["stances"].is_empty() and s1["stance_chosen"] == [0], "la postura elegida no se ve hasta revelar; el otro solo sabe que ya eligió")
	_do(_act("stance", players[1], {"agree": false}))
	_check(e.snapshot_for(judge)["stances"] == {0: true, 1: false}, "reveladas las dos posturas, todos las ven")
	# Soborno pendiente: solo el juez ve el monto.
	_game()
	_hand(pa, ["argumentar", "ejemplo", "refutar", "desafio", "incriminacion"])
	_wilds(pa, ["soborno"])
	_wild(pa, "soborno", {"amount": 3})
	_skip_response(pb)
	_check(e.phase == DebateEngine.Phase.BRIBE, "soborno pendiente")
	_check(e.snapshot_for(judge)["bribe"]["amount"] == 3, "el juez ve el monto")
	_check(not e.snapshot_for(pa).has("bribe") and not e.snapshot_for(pb).has("bribe"), "los debatientes no ven el monto en la foto")
	var mj := _mirror_of(judge)
	_check(mj.pending_bribe()["amount"] == 3 and mj.pending_bribe()["player"].index == pa.index, "el espejo del juez reconstruye el soborno pendiente")
	_do(_act("bribe_decision", judge, {"accept": true}))
	# Durante una intervención: interrupciones y tiempos en el espejo.
	_game()
	_hand(pa, ["argumentar", "ejemplo"])
	_hand(pb, ["refutar", "objecion", "ejemplo"])
	_wilds(pb, ["veredicto"])
	_play(pa, "argumentar")
	var mp := _mirror_of(pb)
	var mpb := mp.player_by_index(pb.index)
	_check(_ids(mp.interrupt_cards(mpb)) == _ids(e.interrupt_cards(pb)), "el espejo sabe con qué cartas puede interrumpir el rival")
	_check(mp.speaker().index == pa.index and mp.current_unit()["card"].id == "argumentar", "el espejo sabe quién habla y con qué carta")
	var left := mp.time_left()
	mp.tick(5.0)
	_check(is_equal_approx(mp.time_left(), left - 5.0) and mp.phase == DebateEngine.Phase.SPEECH, "el reloj del espejo corre pero no cambia la fase")
	mp.tick(500.0)
	_check(mp.phase == DebateEngine.Phase.SPEECH and mp.time_left() == 0.0, "las reglas de tiempo las resuelve el servidor, no el espejo")
	_check(not mp.apply(_act("end_speech", pa))["ok"], "un espejo no aplica acciones")
	# Ventana de respuesta y final.
	_game()
	_wilds(pa, ["cautela"])
	_wilds(pb, ["inocente"])
	_wild(pa, "cautela")
	var mr := _mirror_of(pb)
	_check(mr.phase == DebateEngine.Phase.RESPONSE and mr.pending_wild().id == "cautela" and mr.pending_wild_owner().index == pa.index, "el espejo reconstruye la ventana de respuesta")
	_check(_ids(mr.response_options(mr.player_by_index(pb.index))) == ["inocente"], "y sabe con qué puede responder el rival")
	_skip_response(pb)
	pa.score = 3
	e.clock = 1000.0
	_do(_act("judge_end", judge))
	var mo := _mirror_of(judge)
	_check(mo.phase == DebateEngine.Phase.OVER and mo.result["reason"] == "judge" and mo.result["scores"] == e.result["scores"], "el espejo recibe el resultado final")


func test_data_driven_wild() -> void:
	# Un comodín nuevo (por ejemplo el 12) se agrega solo en el JSON, sin cambiar código.
	_game()
	var extra := CardData.from_dict({
		"id": "cautela_doble", "name": "Cautela doble", "effect": "block", "timing": "turn",
		"answerable_by": ["cancel"], "text": "Otro bloqueo de prueba."}, CardData.Kind.WILD)
	e.catalog.wilds.append(extra)
	pa.wilds.assign([extra])
	_wild(pa, "cautela_doble")
	_skip_response(pb)
	_check(pb.blocked, "un comodín agregado por datos usa el efecto existente")
	# Cambiar un número en los datos cambia la regla sin tocar código.
	var old := Config.turn_seconds
	Config.turn_seconds = 45
	_game()
	_hand(pa, ["argumentar"])
	_play(pa, "argumentar")
	_check(e.time_left() == 45.0, "la duración del turno sale de la configuración")
	Config.turn_seconds = old


func test_card_texts() -> void:
	var cat := CardCatalog.load_default()
	_check(cat.normals.size() == 13, "13 cartas normales")
	_check(cat.wilds.size() == 11, "11 comodines")
	for c in cat.normals + cat.wilds:
		_check(not c.text.contains("{") and c.title != "", "el texto de %s no deja marcadores sin reemplazar (%s)" % [c.id, c.text])
	_check(cat.by_id("incriminacion").text.contains("-2") and cat.by_id("incriminacion").text.contains("-3"), "el texto de Incriminación usa los puntos de los datos")
	_check(cat.by_id("end").text.contains("20"), "el texto de END usa end_min_puntos")


func test_game_state_room() -> void:
	# La sala reparte roles al azar y guarda las monedas del juez para cuando debata.
	var names: Array[String] = ["Ana", "Beto", "Caro"]
	GameState.new_room(names, "normal")
	var seen := {}
	for i in 30:
		GameState.start_game()
		seen[GameState.engine.judge.index] = true
		_check(GameState.engine.debaters.size() == 2 and not GameState.engine.debaters.has(GameState.engine.judge), "2 debatientes y 1 juez")
	_check(seen.size() == 3, "los roles rotan al azar entre los 3 (juez vistos: %s)" % str(seen.keys()))
	_check(GameState.games_played == 30, "cuenta partidas")
	GameState.new_room(names, "indefendible")
	GameState.start_game()
	_check(GameState.engine.mode == "indefendible" and GameState.engine.phase == DebateEngine.Phase.STANCE_RESULT, "modo Indefendible reparte posturas")
	# Temas por modo.
	_check(GameState.engine.topic != "", "hay pregunta")
