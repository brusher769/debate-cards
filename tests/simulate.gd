extends Node
## Simulación sin interfaz: bots que juegan partidas completas con acciones legales al azar
## (todas las cartas, comodines, respuestas, interrupciones, sobornos y fines de partida) y
## revisan que el motor nunca se atasque ni rompa sus invariantes.
##   godot --headless --path . res://tests/simulate.tscn
## Imprime "SIMULACION OK" si todo pasó.

const GAMES := 300
const MAX_STEPS := 4000

var _failures := 0
var _reasons := {}
var _rng := RandomNumberGenerator.new()
var _seen := {} ## cartas y efectos que se llegaron a jugar
var _steps_total := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FALLO: ", msg)


func _ready() -> void:
	Settings.reset_to_defaults(false)
	_rng.seed = 12345
	for g in GAMES:
		_play_game(g)
	_check(_reasons.size() >= 3, "las partidas terminan de varias formas distintas: %s" % str(_reasons))
	_check(_seen.size() >= 20, "los bots probaron casi todas las cartas (%d distintas)" % _seen.size())
	if _failures == 0:
		print("SIMULACION OK (%d partidas, %d pasos; fines: %s)" % [GAMES, _steps_total, str(_reasons)])
	else:
		printerr("SIMULACION CON FALLOS: ", _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _play_game(g: int) -> void:
	var players: Array[PlayerData] = []
	for i in 3:
		var p := PlayerData.new()
		p.display_name = "Bot%d" % i
		p.index = i
		p.bank = _rng.randi_range(0, 6) if g % 5 == 0 else 0
		players.append(p)
	var judge := players[_rng.randi() % 3]
	var mode := "normal" if g % 4 != 3 else "indefendible"
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + g
	var e := DebateEngine.create(CardCatalog.load_default(), players, judge, mode, func() -> String: return "Tema", rng)
	var steps := 0
	while e.phase != DebateEngine.Phase.OVER and steps < MAX_STEPS:
		steps += 1
		_step(e, players)
		_invariants(e)
		e.take_events()
	_steps_total += steps
	_check(e.phase == DebateEngine.Phase.OVER, "la partida %d terminó (fase %d tras %d pasos)" % [g, e.phase, steps])
	if e.phase != DebateEngine.Phase.OVER:
		return
	var r := e.result
	_reasons[r["reason"]] = int(_reasons.get(r["reason"], 0)) + 1
	_check(r.has("scores") and r.has("winner") and r.has("tie"), "resultado completo")
	if r["reason"] != "verdict":
		var a := e.debaters[0].score
		var b := e.debaters[1].score
		_check(r["tie"] == (a == b), "empate solo si los puntos son iguales")
		if a != b:
			_check(r["winner"] == (e.debaters[0] if a > b else e.debaters[1]), "gana quien tiene más puntos")
	else:
		_check(e.judge_jailed and r["winner"] != null, "Veredicto acertado: el juez va a la cárcel y hay ganador")
	# Las monedas de sobornos no descubiertos las guarda el juez; si lo descubren, no.
	if e.judge_jailed:
		_check(judge.bank == 0 or g % 5 == 0, "el juez descubierto no se lleva el soborno")
	# Acciones tras terminar se rechazan.
	var late := e.apply({"type": "judge_end", "player": e.judge.index})
	_check(not late["ok"], "no se puede actuar tras terminar")


## Una decisión de bot sencilla según la fase; siempre usa acciones que el motor dice que son legales.
func _step(e: DebateEngine, players: Array[PlayerData]) -> void:
	var judge := e.judge
	match e.phase:
		DebateEngine.Phase.STANCE:
			for p in e.debaters:
				if not e.stance_choices.has(p):
					_send(e, "stance", p, {"agree": _rng.randf() < 0.5})
					return
		DebateEngine.Phase.STANCE_RESULT:
			_send(e, "continue", judge)
		DebateEngine.Phase.PLAY:
			_play_turn(e)
		DebateEngine.Phase.RESPONSE:
			var owner := e.pending_wild_owner()
			var responder := e.other(owner)
			var options := e.response_options(responder)
			if not options.is_empty() and _rng.randf() < 0.6:
				_send(e, "respond", responder, {"card": options[_rng.randi() % options.size()].id})
			else:
				_send(e, "pass_response", responder)
		DebateEngine.Phase.BRIBE:
			_send(e, "bribe_decision", judge, {"accept": _rng.randf() < 0.5})
		DebateEngine.Phase.APPEAL:
			_send(e, "appeal_time", judge, {"seconds": Config.appeal_options[_rng.randi() % Config.appeal_options.size()]})
		DebateEngine.Phase.SPEECH:
			var speaker := e.speaker()
			var rival := e.other(speaker)
			var options := e.interrupt_cards(rival)
			var roll := _rng.randf()
			if not options.is_empty() and roll < 0.35:
				var c := options[_rng.randi() % options.size()]
				if c.is_wild():
					_send(e, "play_wild", rival, {"card": c.id})
				else:
					_send(e, "play_card", rival, {"card": c.id})
			elif roll < 0.55:
				e.tick(_rng.randf_range(1.0, 90.0)) # se acaba el tiempo (a veces mucho)
			elif e.can_judge_end() and roll < 0.6:
				_send(e, "judge_end", judge)
			else:
				_send(e, "end_speech", speaker)
		DebateEngine.Phase.ANSWER:
			if _rng.randf() < 0.3:
				e.tick(_rng.randf_range(1.0, 40.0))
			else:
				_send(e, "end_answer", e.other(e.current_unit()["player"]))
		DebateEngine.Phase.RESOLVE:
			var card: CardData = e.current_unit()["card"]
			if card.scoring == CardData.Scoring.DECISION:
				_send(e, "decide", judge, {"passes": _rng.randf() < 0.5})
			else:
				_send(e, "score", judge, {"points": Config.judge_points[_rng.randi() % Config.judge_points.size()]})


func _play_turn(e: DebateEngine) -> void:
	var p := e.active
	var roll := _rng.randf()
	if roll < 0.08 and e.can_judge_end():
		_send(e, "judge_end", e.judge)
		return
	if roll < 0.12 and e.can_swap_wild(p):
		_send(e, "swap_wild", p)
		return
	if roll < 0.15:
		e.tick(_rng.randf_range(10.0, 200.0)) # el reloj de la partida avanza
		return
	# Un comodín legal (con parámetros al azar) antes de la carta normal.
	if roll < 0.55:
		var options: Array[Dictionary] = []
		for w in p.wilds:
			var params := {}
			if w.effect == "bribe":
				params["amount"] = _rng.randi_range(1, maxi(p.coins, 1))
			if w.effect == "peek":
				params["buy_extra"] = _rng.randf() < 0.5
			if e.check_wild(p, w, params) == "":
				options.append({"card": w.id, "params": params})
		# Los comodines reactivos de otro jugador no cuentan aquí; también el rival puede jugar Veredicto.
		if not options.is_empty():
			var pick := options[_rng.randi() % options.size()]
			var extra: Dictionary = pick["params"]
			extra["card"] = pick["card"]
			_send(e, "play_wild", p, extra)
			return
	# Carta normal.
	var playable := e.playable_cards(p)
	_check(not playable.is_empty(), "en PLAY siempre hay carta jugable")
	if playable.is_empty():
		return
	var c := playable[_rng.randi() % playable.size()]
	_send(e, "play_card", p, {"card": c.id})


func _send(e: DebateEngine, type: String, p: PlayerData, extra := {}) -> void:
	var action := {"type": type, "player": p.index}
	action.merge(extra)
	var before := e.phase
	var r := e.apply(action)
	if not r["ok"]:
		_check(false, "el bot mandó %s en fase %d y se rechazó: %s" % [action, before, r["error"]])
		# Para no atascar la simulación, se cierra la partida (y ya quedó anotado el fallo).
		e.phase = DebateEngine.Phase.OVER
		e.result = {"reason": "error", "winner": null, "tie": true, "scores": {}, "judge_jailed": false, "judge_bank": 0}
		return
	if type == "play_card" or type == "respond" or type == "play_wild":
		_seen[str(extra.get("card", ""))] = true


func _invariants(e: DebateEngine) -> void:
	for p in e.debaters:
		_check(p.coins >= 0, "monedas nunca negativas (%s: %d)" % [p.display_name, p.coins])
		_check(p.hand.size() <= Config.hand_normals + 20, "mano con tamaño razonable")
		for c in p.hand:
			_check(c != null and not c.is_wild(), "la mano solo tiene cartas normales")
		for c in p.wilds:
			_check(c != null and c.is_wild(), "los comodines son comodines")
		_check(p.innocent_left >= 0, "Inocente no baja de 0")
	_check(e.judge.hand.is_empty() and e.judge.wilds.is_empty(), "el juez nunca tiene cartas")
	if e.phase == DebateEngine.Phase.SPEECH or e.phase == DebateEngine.Phase.ANSWER:
		_check(not e.current_unit().is_empty(), "hay una intervención en curso")
	# La vista de cada jugador se puede generar siempre y nunca trae la mano del rival.
	for p in e.players:
		var v := e.view_for(p)
		_check(v.has("phase") and v.has("scores"), "vista completa")
		if p == e.judge:
			_check(not v.has("you"), "el juez no tiene información privada")
