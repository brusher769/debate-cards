class_name DebateEngine
extends RefCounted
## Motor de reglas de UNA partida (REGLAS_DEBATE.md). Lógica pura: no conoce nodos ni pantallas.
##
## Cómo se usa
##   - Todo lo que hace un jugador es una ACCIÓN: un Dictionary con "type" y "player" (índice del
##     jugador) más los datos propios. engine.apply(accion) la valida y devuelve
##     {"ok": bool, "error": String}. Si no es válida, no cambia nada.
##   - El tiempo avanza con engine.tick(delta): el motor lleva el reloj de la partida, el de cada
##     intervención y el de la ventana de respuesta.
##   - Lo que pasa sale como EVENTOS (take_events()). Cada evento trae "to": -1 si es público o el
##     índice del único jugador que puede verlo (por ejemplo, el comodín que te da la Lupa).
##   - view_for(jugador) devuelve solo lo que ese jugador puede saber (su mano y sus monedas, nunca
##     las del rival), pensado para el servidor autoritativo de la fase online.
##   - En línea, el servidor tiene el motor de verdad y cada cliente un MOTOR ESPEJO
##     (create_mirror): snapshot_for(jugador) arma la foto del estado que ve ese jugador y
##     load_snapshot() la copia en el espejo, así la misma interfaz sirve en local y en línea. El
##     espejo no ejecuta reglas: solo refleja lo que manda el servidor.
##
## Acciones (campo "type"):
##   stance {agree}               un debatiente elige Acuerdo/Desacuerdo (fase STANCE)
##   continue                     avanza tras revelar las posturas (fase STANCE_RESULT)
##   play_card {card}             carta normal: en tu turno, o Refutar/Objeción durante el rival
##   play_wild {card, amount, buy_extra}   comodín (amount: Soborno; buy_extra: Lupa)
##   swap_wild                    cambiar el comodín por otro al azar (cuesta monedas)
##   respond {card} / pass_response        responder (o no) a un comodín del rival
##   end_speech                   quien habla termina su intervención
##   end_answer                   quien responde termina su respuesta
##   score {points}               el juez puntúa una intervención de puntaje libre
##   decide {passes}              el juez decide "procede / no procede"
##   appeal_time {seconds}        el juez concede tiempo a una Apelación
##   bribe_decision {accept}      el juez acepta o rechaza un Soborno (en privado)
##   judge_end                    el juez termina la partida (pasado el tiempo mínimo)
##
## Fases: STANCE -> STANCE_RESULT -> PLAY -> (SPEECH -> ANSWER -> RESOLVE) ... -> OVER.
## RESPONSE, BRIBE y APPEAL son pausas dentro de un turno.

signal changed

enum Phase { STANCE, STANCE_RESULT, PLAY, RESPONSE, BRIBE, APPEAL, SPEECH, ANSWER, RESOLVE, OVER }

var catalog: CardCatalog
var players: Array[PlayerData] = []
var judge: PlayerData
var debaters: Array[PlayerData] = []
## "normal" (posturas elegidas en secreto) o "indefendible" (posturas asignadas al azar).
var mode := "normal"
var topic := ""
var topics_rejected := 0
var phase: Phase = Phase.STANCE
## Segundos transcurridos desde que empezó el debate (no cuenta la elección de posturas).
var clock := 0.0
var turn_index := 0
var active: PlayerData
## PlayerData -> true si eligió "de acuerdo". Se llena en STANCE; no es pública hasta revelarla.
var stance_choices := {}
## true si los dos debatientes tienen posturas opuestas (hay debate).
var stances_opposite := false
## Al terminar: {"reason", "winner", "tie", "scores", "judge_jailed", "judge_bank"}.
var result := {}
var judge_jailed := false

var _topic_provider: Callable
var _rng := RandomNumberGenerator.new()
var _events: Array[Dictionary] = []
## Intervenciones de este turno en orden; la primera es la actual. Cada una es un Dictionary:
## player, card, stage (Phase), left (segundos), interrupted, floor (palabra sin puntaje), objection.
var _line: Array[Dictionary] = []
var _resume_phase: Phase = Phase.PLAY
var _pending := {} ## comodín en ventana de respuesta: player, card, params, response
var _response_left := 0.0
var _bribe_pending := {} ## Soborno esperando la decisión del juez: player, card, amount
var _pending_verdict: PlayerData = null
var _refute_count := 0
var _last_speaker: PlayerData
var _bribes := {} ## PlayerData -> monedas de Soborno que el juez aceptó en esta partida
var _bank_before := 0
var _started := false
## true en el cliente de una partida en línea: refleja el estado que manda el servidor y no aplica reglas.
var is_mirror := false
var _last_snapshot_key := ""


## Crea un motor espejo vacío para un cliente en línea (se llena con load_snapshot()).
static func create_mirror(cat: CardCatalog) -> DebateEngine:
	var e := DebateEngine.new()
	e.catalog = cat
	e.is_mirror = true
	return e


## Crea la partida: reparte manos, monedas y el primer tema. `topics` es un Callable que devuelve
## el siguiente tema (String). Con `rng` se pueden fijar las pruebas.
static func create(cat: CardCatalog, all_players: Array[PlayerData], judge_player: PlayerData,
		game_mode: String, topics: Callable, rng: RandomNumberGenerator = null) -> DebateEngine:
	var e := DebateEngine.new()
	e.catalog = cat
	e.players = all_players
	e.judge = judge_player
	e.mode = game_mode
	e._topic_provider = topics
	if rng != null:
		e._rng = rng
	else:
		e._rng.randomize()
	e._setup()
	return e


func _setup() -> void:
	debaters.clear()
	for p in players:
		p.reset_for_game()
		if p != judge:
			debaters.append(p)
	_bank_before = judge.bank
	for p in debaters:
		var pool := catalog.normals.duplicate()
		_shuffle(pool)
		p.hand.assign(pool.slice(0, Config.hand_normals))
		var wild_pool := catalog.wilds.duplicate()
		_shuffle(wild_pool)
		p.wilds.assign(wild_pool.slice(0, Config.hand_wilds))
		p.coins = mini(Config.coins_start + p.bank, Config.coins_max)
		p.bank = 0
	topic = _topic_provider.call()
	phase = Phase.STANCE
	if mode == "indefendible":
		# El juego reparte las posturas: una de acuerdo y otra en desacuerdo, al azar.
		var first_agrees := _rng.randf() < 0.5
		stance_choices[debaters[0]] = first_agrees
		stance_choices[debaters[1]] = not first_agrees
		stances_opposite = true
		phase = Phase.STANCE_RESULT
		_emit("stances_revealed", {"opposite": true, "assigned": true, "choices": _choices_by_index()})


# ---------------------------------------------------------------------------
# API pública
# ---------------------------------------------------------------------------

## Aplica una acción de un jugador. Devuelve {"ok": bool, "error": String}.
func apply(action: Dictionary) -> Dictionary:
	if is_mirror:
		return _fail("Un motor espejo no aplica acciones: se mandan al servidor.")
	if phase == Phase.OVER:
		return _fail("La partida ya terminó.")
	var p := player_by_index(int(action.get("player", -1)))
	if p == null:
		return _fail("Jugador desconocido.")
	var err := ""
	match str(action.get("type", "")):
		"stance":
			err = _do_stance(p, bool(action.get("agree", false)))
		"continue":
			err = _do_continue()
		"play_card":
			err = _do_play_card(p, str(action.get("card", "")))
		"play_wild":
			err = _do_play_wild(p, str(action.get("card", "")), action)
		"swap_wild":
			err = _do_swap_wild(p)
		"respond":
			err = _do_respond(p, str(action.get("card", "")))
		"pass_response":
			err = _do_pass_response(p)
		"end_speech":
			err = _do_end_speech(p)
		"end_answer":
			err = _do_end_answer(p)
		"score":
			err = _do_score(p, int(action.get("points", 0)))
		"decide":
			err = _do_decide(p, bool(action.get("passes", false)))
		"appeal_time":
			err = _do_appeal_time(p, int(action.get("seconds", 0)))
		"bribe_decision":
			err = _do_bribe_decision(p, bool(action.get("accept", false)))
		"judge_end":
			err = _do_judge_end(p)
		_:
			err = "Acción desconocida: %s" % action.get("type", "")
	if err != "":
		return _fail(err)
	changed.emit()
	return {"ok": true, "error": ""}


## Hace pasar el tiempo. Cuando se acaba una intervención, una respuesta o la ventana de
## respuesta a un comodín, el motor lo resuelve solo.
func tick(delta: float) -> void:
	if is_mirror:
		_tick_mirror(delta)
		return
	if phase == Phase.OVER or not _started:
		return
	clock += delta
	var before := [phase, turn_index, _line.size(), _events.size()]
	match phase:
		Phase.SPEECH:
			var u := _line[0]
			u["left"] = float(u["left"]) - delta
			if float(u["left"]) <= 0.0:
				u["left"] = 0.0
				_emit("time_up", {"player": u["player"].index})
				_finish_speech()
		Phase.ANSWER:
			var u := _line[0]
			u["left"] = float(u["left"]) - delta
			if float(u["left"]) <= 0.0:
				u["left"] = 0.0
				_emit("time_up", {"player": _other(u["player"]).index})
				_to_resolve()
		Phase.RESPONSE:
			_response_left -= delta
			if _response_left <= 0.0:
				_resolve_pending()
	# Solo avisa si algo cambió de verdad (no en cada cuadro), para que la interfaz no se rehaga sin parar.
	if before != [phase, turn_index, _line.size(), _events.size()]:
		changed.emit()


## Eventos acumulados desde la última llamada (y los borra).
func take_events() -> Array[Dictionary]:
	var out := _events.duplicate()
	_events.clear()
	return out


func player_by_index(i: int) -> PlayerData:
	for p in players:
		if p.index == i:
			return p
	return null


func other(p: PlayerData) -> PlayerData:
	return _other(p)


## Segundos que le quedan a lo que está corriendo (intervención, respuesta o ventana), o 0.
func time_left() -> float:
	match phase:
		Phase.SPEECH, Phase.ANSWER:
			return maxf(float(_line[0]["left"]), 0.0)
		Phase.RESPONSE:
			return maxf(_response_left, 0.0)
	return 0.0


## La intervención actual (Dictionary con player, card, stage...) o {} si no hay.
func current_unit() -> Dictionary:
	return _line[0] if not _line.is_empty() else {}


## Quién habla ahora (null si nadie).
func speaker() -> PlayerData:
	if phase in [Phase.SPEECH, Phase.APPEAL] and not _line.is_empty():
		return _line[0]["player"]
	return null


## Cartas normales que `p` puede jugar como carta de su turno (Refutar y Objeción no).
func playable_cards(p: PlayerData) -> Array[CardData]:
	var out: Array[CardData] = []
	for c in p.hand:
		if not c.is_interrupt():
			out.append(c)
	return out


## Cartas que `p` puede jugar para interrumpir la intervención actual del rival.
func interrupt_cards(p: PlayerData) -> Array[CardData]:
	var out: Array[CardData] = []
	if phase != Phase.SPEECH or _line.is_empty() or _line[0]["player"] == p or not debaters.has(p):
		return out
	for c in p.hand:
		if c.is_interrupt() and _check_interrupt(p, c) == "":
			out.append(c)
	for c in p.wilds:
		if c.timing == "any" and _check_wild(p, c, {}) == "":
			out.append(c)
	return out


## Comodines con los que `p` puede responder al comodín que está en la ventana de respuesta.
func response_options(p: PlayerData) -> Array[CardData]:
	var out: Array[CardData] = []
	if phase != Phase.RESPONSE or p == _pending["player"]:
		return out
	var w: CardData = _pending["card"]
	for c in p.wilds:
		if w.answerable_by.has(c.effect):
			out.append(c)
	return out


## El comodín que está esperando respuesta (o null).
func pending_wild() -> CardData:
	return _pending["card"] if phase == Phase.RESPONSE else null


func pending_wild_owner() -> PlayerData:
	return _pending["player"] if phase == Phase.RESPONSE else null


## Datos del Soborno que espera la decisión del juez ({} si no hay).
func pending_bribe() -> Dictionary:
	return _bribe_pending


## Devuelve "" si `p` puede jugar ahora ese comodín, o el motivo en español si no.
func check_wild(p: PlayerData, card: CardData, params := {}) -> String:
	return _check_wild(p, card, params)


func can_swap_wild(p: PlayerData) -> bool:
	return phase == Phase.PLAY and p == active and not p.wild_played and not p.wilds.is_empty() \
		and p.coins >= Config.swap_cost


## true si el juez ya puede usar "terminar la partida".
func can_judge_end() -> bool:
	return phase in [Phase.PLAY, Phase.SPEECH] and clock >= Config.judge_end_minutes * 60.0


## Lo que `p` puede saber: información pública más su mano y sus monedas. Nunca la mano, las
## monedas ni el comodín del rival, ni lo que decidió el juez sobre un soborno.
func view_for(p: PlayerData) -> Dictionary:
	var scores := {}
	for d in debaters:
		scores[d.index] = d.score
	var v := {
		"phase": phase,
		"topic": topic,
		"mode": mode,
		"judge": judge.index,
		"debaters": debaters.map(func(d: PlayerData) -> int: return d.index),
		"active": active.index if active != null else -1,
		"turn": turn_index,
		"clock": clock,
		"scores": scores,
		"speaker": speaker().index if speaker() != null else -1,
		"blocked": debaters.filter(func(d: PlayerData) -> bool: return d.blocked).map(func(d: PlayerData) -> int: return d.index),
	}
	if phase >= Phase.PLAY or phase == Phase.STANCE_RESULT:
		var stances := {}
		for d in debaters:
			if stance_choices.has(d):
				stances[d.index] = stance_choices[d]
		v["stances"] = stances
	if debaters.has(p):
		v["you"] = {
			"index": p.index,
			"hand": p.hand.map(func(c: CardData) -> String: return c.id),
			"wilds": p.wilds.map(func(c: CardData) -> String: return c.id),
			"coins": p.coins,
		}
	return v


# ---------------------------------------------------------------------------
# Fotos del estado (partidas en línea)
# ---------------------------------------------------------------------------

## La foto del estado tal como la ve `viewer`: todo lo público más, si es debatiente, su propia
## mano, comodines y monedas. NUNCA incluye la mano, las monedas ni el comodín del rival, ni el
## escudo del Soborno, ni lo que decidió el juez (salvo el monto del soborno pendiente, que solo
## ve el juez). Son solo diccionarios, números, textos y listas: se puede mandar por red.
func snapshot_for(viewer: PlayerData) -> Dictionary:
	var pl: Array = []
	for p in players:
		pl.append({
			"index": p.index, "name": p.display_name, "score": p.score,
			"blocked": p.blocked, "innocent_left": p.innocent_left, "contempt": p.contempt,
			"repeat_pending": p.repeat_pending,
			"last_normal": p.last_normal.id if p.last_normal != null else "",
			"last_wild": p.last_wild.id if p.last_wild != null else "",
		})
	var line: Array = []
	for u in _line:
		line.append({
			"player": (u["player"] as PlayerData).index, "card": (u["card"] as CardData).id,
			"stage": int(u["stage"]), "left": float(u["left"]), "interrupted": u["interrupted"],
			"floor": u["floor"], "objection": u["objection"], "repeat": u["repeat"],
		})
	var chosen: Array = []
	for p in stance_choices:
		chosen.append((p as PlayerData).index)
	var s := {
		"phase": int(phase), "topic": topic, "mode": mode, "topics_rejected": topics_rejected,
		"clock": clock, "turn_index": turn_index,
		"judge": judge.index, "debaters": debaters.map(func(d: PlayerData) -> int: return d.index),
		"active": active.index if active != null else -1,
		"players": pl, "stances_opposite": stances_opposite, "stance_chosen": chosen,
		"line": line, "response_left": _response_left, "refute_count": _refute_count,
		"judge_jailed": judge_jailed,
	}
	# Las posturas son secretas hasta que los dos eligen (cada quien solo sabe la suya).
	var stances := {}
	if phase >= Phase.STANCE_RESULT:
		for p in stance_choices:
			stances[(p as PlayerData).index] = stance_choices[p]
	elif viewer != null and stance_choices.has(viewer):
		stances[viewer.index] = stance_choices[viewer]
	s["stances"] = stances
	if phase == Phase.RESPONSE:
		s["pending"] = {"player": (_pending["player"] as PlayerData).index, "card": (_pending["card"] as CardData).id}
	if phase == Phase.OVER:
		var winner: PlayerData = result["winner"]
		s["result"] = {
			"reason": result["reason"], "winner": winner.index if winner != null else -1,
			"tie": result["tie"], "scores": result["scores"], "judge_jailed": result["judge_jailed"],
		}
	if viewer != null and debaters.has(viewer):
		s["you"] = {
			"index": viewer.index,
			"hand": viewer.hand.map(func(c: CardData) -> String: return c.id),
			"wilds": viewer.wilds.map(func(c: CardData) -> String: return c.id),
			"coins": viewer.coins, "wild_played": viewer.wild_played,
		}
	if viewer == judge and phase == Phase.BRIBE:
		s["bribe"] = {
			"player": (_bribe_pending["player"] as PlayerData).index,
			"card": (_bribe_pending["card"] as CardData).id, "amount": _bribe_pending["amount"],
		}
	return s


## Copia en este motor espejo la foto que mandó el servidor (ver snapshot_for).
func load_snapshot(s: Dictionary) -> void:
	is_mirror = true
	if players.is_empty():
		for d in s["players"]:
			var p := PlayerData.new()
			p.index = int(d["index"])
			players.append(p)
	for d in s["players"]:
		var p := player_by_index(int(d["index"]))
		p.display_name = str(d["name"])
		p.score = int(d["score"])
		p.blocked = d["blocked"]
		p.innocent_left = int(d["innocent_left"])
		p.contempt = d["contempt"]
		p.repeat_pending = d["repeat_pending"]
		p.last_normal = catalog.by_id(str(d["last_normal"]))
		p.last_wild = catalog.by_id(str(d["last_wild"]))
		p.hand.clear()
		p.wilds.clear()
		p.coins = 0
	judge = player_by_index(int(s["judge"]))
	debaters.clear()
	for i in s["debaters"]:
		debaters.append(player_by_index(int(i)))
	active = player_by_index(int(s["active"]))
	phase = int(s["phase"]) as Phase
	topic = str(s["topic"])
	mode = str(s["mode"])
	topics_rejected = int(s["topics_rejected"])
	clock = float(s["clock"])
	turn_index = int(s["turn_index"])
	_started = turn_index > 0
	stances_opposite = s["stances_opposite"]
	judge_jailed = s["judge_jailed"]
	# Posturas: los que ya eligieron figuran (con un valor de relleno) y las reveladas con su valor.
	stance_choices.clear()
	for i in s["stance_chosen"]:
		stance_choices[player_by_index(int(i))] = false
	for i in s["stances"]:
		stance_choices[player_by_index(int(i))] = s["stances"][i]
	_line.clear()
	for u in s["line"]:
		_line.append({
			"player": player_by_index(int(u["player"])), "card": catalog.by_id(str(u["card"])),
			"stage": int(u["stage"]), "left": float(u["left"]), "interrupted": u["interrupted"],
			"floor": u["floor"], "objection": u["objection"], "repeat": u["repeat"],
		})
	_response_left = float(s["response_left"])
	_refute_count = int(s["refute_count"])
	_pending = {}
	if s.has("pending"):
		_pending = {
			"player": player_by_index(int(s["pending"]["player"])), "card": catalog.by_id(str(s["pending"]["card"])),
			"params": {}, "response": null,
		}
	_bribe_pending = {}
	if s.has("bribe"):
		_bribe_pending = {
			"player": player_by_index(int(s["bribe"]["player"])), "card": catalog.by_id(str(s["bribe"]["card"])),
			"amount": int(s["bribe"]["amount"]),
		}
	result = {}
	if s.has("result"):
		var r: Dictionary = s["result"]
		result = {
			"reason": r["reason"], "winner": player_by_index(int(r["winner"])) if int(r["winner"]) >= 0 else null,
			"tie": r["tie"], "scores": r["scores"], "judge_jailed": r["judge_jailed"], "judge_bank": 0,
		}
	if s.has("you"):
		var you := player_by_index(int(s["you"]["index"]))
		for id in s["you"]["hand"]:
			you.hand.append(catalog.by_id(str(id)))
		for id in s["you"]["wilds"]:
			you.wilds.append(catalog.by_id(str(id)))
		you.coins = int(s["you"]["coins"])
		you.wild_played = s["you"]["wild_played"]
	# El servidor manda la foto de nuevo cada pocos segundos (para corregir los relojes): si nada
	# más cambió, no se avisa a la interfaz para que no se rehaga sin motivo.
	var key := _snapshot_key(s)
	if key != _last_snapshot_key:
		_last_snapshot_key = key
		changed.emit()


## Huella de una foto sin lo que cambia solo con el tiempo (relojes).
func _snapshot_key(s: Dictionary) -> String:
	var copy := s.duplicate(true)
	copy.erase("clock")
	copy.erase("response_left")
	for u in copy["line"]:
		u.erase("left")
	return var_to_str(copy).md5_text()


## Agrega eventos recibidos del servidor (motor espejo) para que la interfaz los lea con take_events().
func push_events(list: Array) -> void:
	for e in list:
		_events.append(e)


## En el espejo el reloj solo corre para mostrarlo; las reglas (fin de tiempo, etc.) las resuelve
## el servidor y llegan en la siguiente foto.
func _tick_mirror(delta: float) -> void:
	if phase == Phase.OVER or not _started:
		return
	clock += delta
	match phase:
		Phase.SPEECH, Phase.ANSWER:
			if not _line.is_empty():
				_line[0]["left"] = maxf(float(_line[0]["left"]) - delta, 0.0)
		Phase.RESPONSE:
			_response_left = maxf(_response_left - delta, 0.0)


# ---------------------------------------------------------------------------
# Posturas y comienzo del debate
# ---------------------------------------------------------------------------

func _do_stance(p: PlayerData, agree: bool) -> String:
	if phase != Phase.STANCE:
		return "Ahora no se eligen posturas."
	if not debaters.has(p):
		return "Solo los debatientes eligen postura."
	if stance_choices.has(p):
		return "Ya elegiste tu postura."
	stance_choices[p] = agree
	_emit("stance_chosen", {"player": p.index})
	if stance_choices.size() == debaters.size():
		stances_opposite = stance_choices[debaters[0]] != stance_choices[debaters[1]]
		phase = Phase.STANCE_RESULT
		_emit("stances_revealed", {"opposite": stances_opposite, "assigned": false, "choices": _choices_by_index()})
	return ""


func _do_continue() -> String:
	if phase != Phase.STANCE_RESULT:
		return "No hay nada que continuar."
	if stances_opposite:
		_started = true
		active = debaters[_rng.randi() % debaters.size()]
		_begin_turn()
	else:
		# Sin oposición no hay debate: sale otra pregunta y se vuelve a elegir.
		topics_rejected += 1
		topic = _topic_provider.call()
		stance_choices.clear()
		phase = Phase.STANCE
		_emit("topic_rejected", {"topic": topic})
	return ""


# ---------------------------------------------------------------------------
# Turnos
# ---------------------------------------------------------------------------

func _begin_turn() -> void:
	turn_index += 1
	_refute_count = 0
	_line.clear()
	for p in debaters:
		if p.innocent_left > 0:
			p.innocent_left -= 1
	if active.blocked:
		# Cautela: este turno no puede usar cartas, así que se pierde.
		active.blocked = false
		active.repeat_pending = false
		_emit("turn_skipped", {"player": active.index})
		active = _other(active)
		_begin_turn()
		return
	if active.repeat_pending:
		# Jurisprudencia: repite la última carta normal sin gastarla.
		active.repeat_pending = false
		_emit("turn_started", {"player": active.index, "turn": turn_index, "repeat": true})
		_start_unit(active, active.last_normal, true)
		return
	if playable_cards(active).is_empty():
		_finish("no_cards", null)
		return
	phase = Phase.PLAY
	_emit("turn_started", {"player": active.index, "turn": turn_index, "repeat": false})


func _end_turn() -> void:
	active = _other(_last_speaker)
	_begin_turn()


func _do_swap_wild(p: PlayerData) -> String:
	if phase != Phase.PLAY or p != active:
		return "Solo puedes cambiar tu comodín en tu turno."
	if p.wild_played:
		return "Ya usaste un comodín: no puedes cambiarlo."
	if p.wilds.is_empty():
		return "No tienes comodín para cambiar."
	if p.coins < Config.swap_cost:
		return "No te alcanzan las monedas."
	var old := p.wilds[0]
	var options := catalog.wilds.filter(func(c: CardData) -> bool: return c.id != old.id)
	if options.is_empty():
		return "No hay otro comodín para dar."
	p.coins -= Config.swap_cost
	p.wilds[0] = options[_rng.randi() % options.size()]
	_emit("wild_swapped", {"player": p.index})
	_emit("wild_received", {"card": p.wilds[0].id}, p.index)
	return ""


# ---------------------------------------------------------------------------
# Cartas normales
# ---------------------------------------------------------------------------

func _do_play_card(p: PlayerData, card_id: String) -> String:
	var card := _find(p.hand, card_id)
	if card == null:
		return "No tienes esa carta."
	match phase:
		Phase.PLAY:
			if p != active:
				return "No es tu turno."
			if card.is_interrupt():
				return "%s solo se juega durante la intervención del rival." % card.title
			p.hand.erase(card)
			p.last_normal = card
			_emit("card_played", {"player": p.index, "card": card.id})
			_start_unit(p, card, false)
		Phase.SPEECH:
			var err := _check_interrupt(p, card)
			if err != "":
				return err
			p.hand.erase(card)
			p.last_normal = card
			_emit("card_played", {"player": p.index, "card": card.id, "interrupt": true})
			if card.effect == "refute":
				_interrupt_refute(p, card)
			else:
				_interrupt_objection(p, card)
		_:
			return "Ahora no se pueden jugar cartas normales."
	return ""


func _check_interrupt(p: PlayerData, card: CardData) -> String:
	if phase != Phase.SPEECH or _line.is_empty():
		return "No hay ninguna intervención que interrumpir."
	if not debaters.has(p) or _line[0]["player"] == p:
		return "Solo el rival puede interrumpir la intervención."
	if not card.is_interrupt():
		return "Solo Refutar y Objeción se juegan durante la intervención del rival."
	if card.effect == "refute" and _refute_count >= Config.refute_chain_max:
		return "La cadena de Refutar ya llegó al máximo."
	return ""


## Empieza una intervención con `card` de `p`. `repeated` = viene de Jurisprudencia (no gasta carta).
func _start_unit(p: PlayerData, card: CardData, repeated: bool) -> void:
	var stage := Phase.APPEAL if card.effect == "appeal" else Phase.SPEECH
	_line = [{
		"player": p, "card": card, "stage": stage, "left": float(card.speech_seconds()),
		"interrupted": false, "floor": false, "objection": false, "repeat": repeated,
	}]
	_enter_unit()


## Pone el motor en la fase que corresponde a la intervención actual.
func _enter_unit() -> void:
	var u := _line[0]
	phase = int(u["stage"]) as Phase
	if phase == Phase.SPEECH or phase == Phase.APPEAL:
		_last_speaker = u["player"]
	_emit("unit_started", {"player": u["player"].index, "card": u["card"].id, "stage": int(phase), "floor": u["floor"]})


func _do_end_speech(p: PlayerData) -> String:
	if phase != Phase.SPEECH:
		return "Nadie está hablando."
	if _line[0]["player"] != p:
		return "Solo quien habla puede terminar su intervención."
	_finish_speech()
	return ""


## Termina el discurso actual: sigue la respuesta del rival (si la carta la pide) o el juez.
func _finish_speech() -> void:
	var u := _line[0]
	var card: CardData = u["card"]
	if card.answer and not u["interrupted"] and not u["floor"]:
		u["stage"] = Phase.ANSWER
		u["left"] = float(Config.answer_seconds)
		_enter_unit()
	else:
		_to_resolve()


func _do_end_answer(p: PlayerData) -> String:
	if phase != Phase.ANSWER:
		return "Nadie está respondiendo."
	if _line[0]["player"] == p or not debaters.has(p):
		return "Solo el rival puede terminar la respuesta."
	_to_resolve()
	return ""


## Pasa la intervención actual a manos del juez (o la cierra si no la puntúa nadie).
func _to_resolve() -> void:
	var u := _line[0]
	if u["floor"]:
		_unit_done()
		return
	u["stage"] = Phase.RESOLVE
	_enter_unit()


## La intervención actual terminó: sigue la siguiente o acaba el turno.
func _unit_done() -> void:
	_line.pop_front()
	if _line.is_empty():
		if phase != Phase.OVER:
			_end_turn()
	else:
		_enter_unit()


func _do_appeal_time(p: PlayerData, seconds: int) -> String:
	if phase != Phase.APPEAL:
		return "No hay una Apelación esperando al juez."
	if p != judge:
		return "Solo el juez concede el tiempo."
	if not Config.appeal_options.has(seconds):
		return "Tiempo no permitido: %d." % seconds
	var u := _line[0]
	u["left"] = float(u["left"]) + seconds
	u["stage"] = Phase.SPEECH
	_emit("appeal_granted", {"seconds": seconds})
	_enter_unit()
	return ""


func _do_score(p: PlayerData, points: int) -> String:
	if phase != Phase.RESOLVE or p != judge:
		return "Ahora no puntúa el juez."
	var u := _line[0]
	if u["objection"] or (u["card"] as CardData).scoring != CardData.Scoring.FREE:
		return "Esta carta se decide con procede / no procede."
	if not Config.judge_points.has(points):
		return "El juez solo puntúa con %s." % str(Config.judge_points)
	_award(u["player"], points, true)
	_emit("scored", {"player": u["player"].index, "card": u["card"].id, "points": points})
	_unit_done()
	return ""


func _do_decide(p: PlayerData, passes: bool) -> String:
	if phase != Phase.RESOLVE or p != judge:
		return "Ahora no decide el juez."
	var u := _line[0]
	var card: CardData = u["card"]
	if card.scoring != CardData.Scoring.DECISION:
		return "Esta carta se puntúa con %s." % str(Config.judge_points)
	var who: PlayerData = u["player"]
	var rival := _other(who)
	if passes:
		_award(who, card.pass_self, true)
		_award(rival, card.pass_rival, true)
	else:
		_award(who, card.fail_self, true)
		_award(rival, card.fail_rival, true)
	_emit("decided", {"player": who.index, "card": card.id, "passes": passes})
	if u["objection"]:
		_objection_resolved(passes)
	else:
		_unit_done()
	return ""


# ---------------------------------------------------------------------------
# Interrupciones: Refutar y Objeción
# ---------------------------------------------------------------------------

func _interrupt_refute(p: PlayerData, card: CardData) -> void:
	_refute_count += 1
	_line[0]["interrupted"] = true
	# La intervención interrumpida se cierra ya (la puntúa el juez) y luego habla quien refuta.
	_line.insert(1, {
		"player": p, "card": card, "stage": Phase.SPEECH, "left": float(card.speech_seconds()),
		"interrupted": false, "floor": false, "objection": false, "repeat": false,
	})
	_to_resolve()


func _interrupt_objection(p: PlayerData, card: CardData) -> void:
	# El juez decide ya; mientras tanto la intervención del rival queda en pausa (abajo en la fila).
	_line.insert(0, {
		"player": p, "card": card, "stage": Phase.RESOLVE, "left": 0.0,
		"interrupted": false, "floor": false, "objection": true, "repeat": false,
	})
	_enter_unit()


func _objection_resolved(passes: bool) -> void:
	var obj: Dictionary = _line.pop_front()
	var card: CardData = obj["card"]
	if passes and card.takes_floor:
		# Procede: termina el turno del rival y quien objetó toma la palabra sin gastar otra carta.
		_line[0]["interrupted"] = true
		_line.insert(1, {
			"player": obj["player"], "card": card, "stage": Phase.SPEECH, "left": float(Config.turn_seconds),
			"interrupted": false, "floor": true, "objection": false, "repeat": false,
		})
		_to_resolve()
	else:
		_enter_unit() # el rival sigue hablando con el tiempo que le quedaba


# ---------------------------------------------------------------------------
# Comodines
# ---------------------------------------------------------------------------

func _do_play_wild(p: PlayerData, card_id: String, action: Dictionary) -> String:
	var card := _find(p.wilds, card_id)
	if card == null:
		return "No tienes ese comodín."
	var err := _check_wild(p, card, action)
	if err != "":
		return err
	p.wilds.erase(card)
	p.wild_played = true
	p.last_wild = card
	_emit("wild_played", {"player": p.index, "card": card.id})
	var w := {"player": p, "card": card, "params": action.duplicate(), "response": null}
	if card.answerable_by.is_empty():
		_pending = w
		_resume_phase = phase
		_resolve_pending()
	else:
		# Ventana de respuesta: siempre se abre (aunque el rival no tenga comodín) para no
		# revelar si lo tiene.
		_pending = w
		_resume_phase = phase
		phase = Phase.RESPONSE
		_response_left = float(Config.response_seconds)
	return ""


func _check_wild(p: PlayerData, card: CardData, params: Dictionary) -> String:
	if not debaters.has(p):
		return "El juez no juega cartas."
	match phase:
		Phase.PLAY:
			if card.timing == "none":
				return "%s solo se juega como respuesta." % card.title
			if card.timing == "turn" and p != active:
				return "%s solo se juega en tu turno." % card.title
		Phase.SPEECH:
			if card.timing != "any":
				return "%s solo se juega en tu turno." % card.title
		_:
			return "Ahora no se pueden jugar comodines."
	match card.effect:
		"bribe":
			var amount := int(params.get("amount", 0))
			if amount < 1 or amount > p.coins:
				return "El soborno debe ser de 1 a %d monedas." % p.coins
		"precedent":
			if p.last_normal == null:
				return "Todavía no jugaste ninguna carta normal para repetir."
		"end":
			if p.score < Config.end_min_points and clock < Config.end_min_minutes * 60.0:
				return "END pide %d puntos o %d minutos de partida." % [Config.end_min_points, Config.end_min_minutes]
		"peek":
			if bool(params.get("buy_extra", false)) and p.coins < Config.lupa_cost:
				return "No te alcanzan las monedas para el comodín extra."
	return ""


func _do_respond(p: PlayerData, card_id: String) -> String:
	if phase != Phase.RESPONSE:
		return "No hay ningún comodín que responder."
	if p == _pending["player"] or not debaters.has(p):
		return "Solo el rival puede responder."
	var card := _find(p.wilds, card_id)
	if card == null:
		return "No tienes ese comodín."
	var w: CardData = _pending["card"]
	if not w.answerable_by.has(card.effect):
		return "%s no puede responder a %s." % [card.title, w.title]
	p.wilds.erase(card)
	p.wild_played = true
	p.last_wild = card
	_emit("wild_played", {"player": p.index, "card": card.id, "response": true})
	_pending["response"] = card
	_resolve_pending()
	return ""


func _do_pass_response(p: PlayerData) -> String:
	if phase != Phase.RESPONSE:
		return "No hay ningún comodín que responder."
	if p == _pending["player"] or not debaters.has(p):
		return "Solo el rival puede responder."
	_resolve_pending()
	return ""


## Cierra la ventana de respuesta y aplica el comodín (con la respuesta del rival, si la hubo).
func _resolve_pending() -> void:
	var w := _pending
	_pending = {}
	var x: PlayerData = w["player"]
	var card: CardData = w["card"]
	var r: CardData = w["response"]
	var negated := false
	var steal_blocked := false
	if r != null:
		var y := _other(x)
		match r.effect:
			"cancel":
				negated = true
				_emit("wild_cancelled", {"player": x.index, "card": card.id})
			"secret":
				steal_blocked = true
			"verdict":
				_pending_verdict = y
			_:
				_apply_wild(y, r, {}, false)
	phase = _resume_phase
	if not negated and phase != Phase.OVER:
		_apply_wild(x, card, w["params"], steal_blocked)
	if phase == Phase.OVER or phase == Phase.BRIBE:
		return # el soborno espera al juez; después sigue _after_wild()
	_after_wild(x, card, negated)


## Lo que queda por hacer cuando un comodín ya se resolvió por completo.
func _after_wild(x: PlayerData, card: CardData, negated: bool) -> void:
	if phase == Phase.OVER:
		return
	if _pending_verdict != null:
		var v := _pending_verdict
		_pending_verdict = null
		_evaluate_verdict(v)
		if phase == Phase.OVER:
			return
	if card.effect == "precedent" and not negated:
		# Jurisprudencia gasta el turno entero.
		_last_speaker = x
		_line.clear()
		_end_turn()
		return
	phase = _resume_phase
	# Un Soborno aceptado puede dejar sin cartas a quien está en su turno: fin por "sin cartas".
	if phase == Phase.PLAY and playable_cards(active).is_empty():
		_finish("no_cards", null)


func _apply_wild(x: PlayerData, card: CardData, params: Dictionary, steal_blocked: bool) -> void:
	var y := _other(x)
	match card.effect:
		"bribe":
			_bribe_pending = {"player": x, "card": card, "amount": int(params.get("amount", 1))}
			phase = Phase.BRIBE
		"verdict":
			_evaluate_verdict(x)
		"steal":
			if steal_blocked:
				_emit("steal_blocked", {"player": x.index})
			elif y.hand.is_empty():
				_emit("steal_failed", {"player": x.index})
			else:
				var stolen := y.hand[_rng.randi() % y.hand.size()]
				y.hand.erase(stolen)
				x.hand.append(stolen)
				_emit("card_stolen", {"player": x.index})
				_emit("stolen_card", {"card": stolen.id, "from": y.index, "by": x.index}, x.index)
				_emit("stolen_card", {"card": stolen.id, "from": y.index, "by": x.index}, y.index)
		"block":
			if y.innocent_left > 0:
				_emit("block_negated", {"player": y.index})
			else:
				y.blocked = true
				_emit("blocked", {"player": y.index})
		"innocent":
			x.innocent_left = int(card.params.get("duration_turns", 2))
		"cancel":
			# Proactivo: quita los beneficios activos del rival y un bloqueo sobre uno mismo.
			# No deshace un Soborno ya aceptado.
			y.innocent_left = 0
			y.contempt = false
			y.repeat_pending = false
			x.blocked = false
			_emit("benefits_cancelled", {"player": x.index})
		"contempt":
			x.contempt = true
		"precedent":
			x.repeat_pending = true
		"end":
			_finish("end", null)
		"peek":
			_emit("peek", {"wilds": y.wilds.map(func(c: CardData) -> String: return c.id)}, x.index)
			if bool(params.get("buy_extra", false)) and x.coins >= Config.lupa_cost:
				var options := catalog.wilds.filter(func(c: CardData) -> bool: return c.effect != "peek")
				if not options.is_empty():
					x.coins -= Config.lupa_cost
					var extra: CardData = options[_rng.randi() % options.size()]
					x.wilds.append(extra)
					_emit("wild_received", {"card": extra.id}, x.index)
		"secret":
			pass # solo tiene efecto como respuesta a Robar carta (ver _resolve_pending)


func _do_bribe_decision(p: PlayerData, accept: bool) -> String:
	if phase != Phase.BRIBE or p != judge:
		return "No hay un soborno esperando al juez."
	var x: PlayerData = _bribe_pending["player"]
	var card: CardData = _bribe_pending["card"]
	var amount: int = _bribe_pending["amount"]
	_bribe_pending = {}
	var lost := 0
	if accept:
		x.coins -= amount
		judge.bank += amount
		_bribes[x] = int(_bribes.get(x, 0)) + amount
		x.bribe_shield = true
		for i in int(card.params.get("lose_cards", 2)):
			if x.hand.is_empty():
				break
			x.hand.remove_at(_rng.randi() % x.hand.size())
			lost += 1
	# El resultado es secreto: solo lo ve quien sobornó. Los demás solo saben que el juez respondió.
	_emit("bribe_decided", {"accepted": accept, "lost": lost}, x.index)
	_emit("bribe_answered", {})
	phase = _resume_phase
	_after_wild(x, card, false)
	return ""


func _evaluate_verdict(y: PlayerData) -> void:
	var rival := _other(y)
	if _bribes.has(rival):
		judge_jailed = true
		judge.bank = _bank_before # el soborno descubierto no pasa a la siguiente partida
		_emit("verdict_result", {"player": y.index, "correct": true})
		_finish("verdict", y)
	else:
		_emit("verdict_result", {"player": y.index, "correct": false})
		_award(y, Config.verdict_fail_penalty, false)


func _do_judge_end(p: PlayerData) -> String:
	if p != judge:
		return "Solo el juez puede terminar la partida."
	if not can_judge_end():
		return "El juez puede terminar la partida después de %d minutos." % Config.judge_end_minutes
	_finish("judge", null)
	return ""


# ---------------------------------------------------------------------------
# Puntos y fin de partida
# ---------------------------------------------------------------------------

## Suma o resta puntos aplicando los efectos activos. `judged` = viene de una resolución del
## juez (sobre eso actúan el escudo del Soborno y Desacato). Inocente limita cualquier pérdida.
func _award(p: PlayerData, delta: int, judged: bool) -> void:
	if delta == 0:
		return
	var target := p
	var amount := delta
	if judged and p.bribe_shield and amount < Config.bribe_max_penalty:
		amount = Config.bribe_max_penalty
	if p.innocent_left > 0 and amount < Config.innocent_max_penalty:
		amount = Config.innocent_max_penalty
	if judged and p.contempt:
		# Desacato: los puntos que iba a recibir (buenos o malos) se los lleva el rival.
		p.contempt = false
		target = _other(p)
		_emit("contempt_transfer", {"from": p.index, "to_player": target.index, "delta": amount})
		if target.innocent_left > 0 and amount < Config.innocent_max_penalty:
			amount = Config.innocent_max_penalty
	target.score += amount
	_emit("points", {"player": target.index, "delta": amount, "asked": delta})


func _finish(reason: String, winner: PlayerData) -> void:
	phase = Phase.OVER
	var tie := false
	if reason != "verdict":
		var a := debaters[0]
		var b := debaters[1]
		if a.score > b.score:
			winner = a
		elif b.score > a.score:
			winner = b
		else:
			winner = null
			tie = true
	var scores := {}
	for d in debaters:
		scores[d.index] = d.score
	result = {
		"reason": reason, "winner": winner, "tie": tie, "scores": scores,
		"judge_jailed": judge_jailed, "judge_bank": judge.bank,
	}
	_emit("game_over", {"reason": reason, "winner": winner.index if winner != null else -1, "tie": tie})


# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------

func _other(p: PlayerData) -> PlayerData:
	return debaters[1] if p == debaters[0] else debaters[0]


func _find(list: Array[CardData], id: String) -> CardData:
	for c in list:
		if c.id == id:
			return c
	return null


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi() % (i + 1)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _choices_by_index() -> Dictionary:
	var out := {}
	for p in stance_choices:
		out[p.index] = stance_choices[p]
	return out


func _emit(type: String, data := {}, to := -1) -> void:
	var e: Dictionary = data.duplicate()
	e["type"] = type
	e["to"] = to
	_events.append(e)


func _fail(msg: String) -> Dictionary:
	return {"ok": false, "error": msg}
