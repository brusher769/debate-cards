class_name RoundManager
extends Node
## Máquina de estados de UNA ronda. No conoce la interfaz: la UI escucha state_changed
## y llama a advance(), pick_argument(), pick_special() y end_round().
##
## TOPIC -> PICK_STANCE -> STANCES -> PICK_ARGUMENT -> REVEAL -> PICK_SPECIAL -> SPEECH ->
## JUDGING -> RESULTS
##
## Al empezar sale un tema al azar (TOPIC). Cada debatiente elige en secreto "a favor" o "en
## contra" (PICK_STANCE). Si eligieron posturas opuestas hay debate (STANCES -> PICK_ARGUMENT);
## si eligieron lo mismo no lo hay y STANCES vuelve a TOPIC con otro tema al azar.
##
## state_changed también se emite al cambiar de quien elige (PICK_*) y al cambiar de discurso
## (SPEECH), aunque el estado sea el mismo: la UI debe releer picker / speech_index.

signal state_changed(new_state: int)

enum State { TOPIC, PICK_STANCE, STANCES, PICK_ARGUMENT, REVEAL, PICK_SPECIAL, SPEECH, JUDGING, RESULTS }

var state: State = State.TOPIC
var topic := ""
var judge: PlayerData
var debaters: Array[PlayerData] = []
## PlayerData -> postura ya traducida ("A favor" / "En contra"). Vacío hasta que hay acuerdo.
var stances := {}
## PlayerData -> true si eligió "a favor". Se llena durante PICK_STANCE.
var stance_choices := {}
## En STANCES: true si eligieron posturas opuestas (hay debate), false si eligieron lo mismo.
var stances_agree := false
## Postura (traducida) que eligieron los dos cuando no hubo debate; vacía si hubo debate.
var shared_stance := ""
## Cuántos temas se han descartado en esta ronda porque los dos eligieron la misma postura.
var topics_rejected := 0
var arguments := {} # PlayerData -> CardData
var specials := {} # PlayerData -> CardData o null
var entries: Array[PlayedEntry] = []
var speech_index := 0
var pick_index := 0
var results: Array = [] # salida de Scoring.compute()
var judge_impl: Judge


func setup(j: Judge) -> void:
	judge_impl = j
	judge_impl.verdict_ready.connect(_on_verdicts)


func start_round() -> void:
	GameState.current_round += 1
	judge = GameState.judge()
	debaters = GameState.debaters()
	topic = GameState.next_topic()
	stances.clear()
	stance_choices.clear()
	stances_agree = false
	shared_stance = ""
	topics_rejected = 0
	arguments.clear()
	specials.clear()
	entries.clear()
	results.clear()
	pick_index = 0
	speech_index = 0
	_set_state(State.TOPIC)


## Avanza en los estados que solo esperan un "continuar": TOPIC, STANCES, REVEAL y SPEECH.
func advance() -> void:
	match state:
		State.TOPIC:
			pick_index = 0
			stance_choices.clear()
			_set_state(State.PICK_STANCE)
		State.STANCES:
			pick_index = 0
			if stances_agree:
				_set_state(State.PICK_ARGUMENT)
			else:
				topics_rejected += 1
				topic = GameState.next_topic()
				stance_choices.clear()
				_set_state(State.TOPIC)
		State.REVEAL:
			pick_index = 0
			_set_state(State.PICK_SPECIAL)
		State.SPEECH:
			speech_index += 1
			if speech_index >= entries.size():
				_set_state(State.JUDGING)
				judge_impl.request_verdict(topic, entries)
			else:
				_set_state(State.SPEECH)


func current_picker() -> PlayerData:
	return debaters[pick_index]


func current_entry() -> PlayedEntry:
	return entries[speech_index]


func opponent_of(p: PlayerData) -> PlayerData:
	return debaters[1] if p == debaters[0] else debaters[0]


## El debatiente actual elige su postura sobre el tema: true = a favor, false = en contra.
func pick_stance(for_it: bool) -> bool:
	if state != State.PICK_STANCE:
		return false
	stance_choices[current_picker()] = for_it
	pick_index += 1
	if pick_index < debaters.size():
		_set_state(State.PICK_STANCE)
		return true
	stances_agree = stance_choices[debaters[0]] != stance_choices[debaters[1]]
	stances.clear()
	shared_stance = ""
	if stances_agree:
		for p in debaters:
			stances[p] = tr("STANCE_FOR") if stance_choices[p] else tr("STANCE_AGAINST")
	else:
		shared_stance = tr("STANCE_FOR") if stance_choices[debaters[0]] else tr("STANCE_AGAINST")
	_set_state(State.STANCES)
	return true


func pick_argument(card: CardData) -> bool:
	var p := current_picker()
	if state != State.PICK_ARGUMENT or card.type != CardData.Type.ARGUMENT or not p.hand.has(card):
		return false
	arguments[p] = card
	p.hand.erase(card)
	GameState.deck.discard(card)
	pick_index += 1
	if pick_index >= debaters.size():
		_set_state(State.REVEAL)
	else:
		_set_state(State.PICK_ARGUMENT)
	return true


## card == null significa "no juego carta especial".
func pick_special(card: CardData) -> bool:
	var p := current_picker()
	if state != State.PICK_SPECIAL:
		return false
	if card != null:
		if not card.is_special() or not p.hand.has(card):
			return false
		p.hand.erase(card)
		GameState.deck.discard(card)
	specials[p] = card
	pick_index += 1
	if pick_index >= debaters.size():
		_build_entries()
		speech_index = 0
		_set_state(State.SPEECH)
	else:
		_set_state(State.PICK_SPECIAL)
	return true


## Cierra la ronda: repone las manos. Devuelve true si la partida terminó.
func end_round() -> bool:
	for p in GameState.players:
		GameState.deck.fill_hand(p, GameState.hand_size)
	return GameState.is_game_over()


func _build_entries() -> void:
	entries.clear()
	var arg_entry := {} # PlayerData -> PlayedEntry
	for p in debaters:
		var e := PlayedEntry.new()
		e.kind = CardData.Type.ARGUMENT
		e.player = p
		e.card = arguments[p]
		entries.append(e)
		arg_entry[p] = e
	for p in debaters:
		var s: CardData = specials.get(p)
		if s == null:
			continue
		if s.type == CardData.Type.EVIDENCE:
			arg_entry[p].evidence = s
		else:
			var e := PlayedEntry.new()
			e.kind = s.type
			e.player = p
			e.card = s
			e.target = arg_entry[opponent_of(p)]
			entries.append(e)


func _on_verdicts(verdicts: Array) -> void:
	if state != State.JUDGING:
		return
	results = Scoring.compute(entries, verdicts)
	for r in results:
		r["player"].score += r["total"]
	GameState.scores_changed.emit()
	_set_state(State.RESULTS)


func _set_state(s: State) -> void:
	state = s
	state_changed.emit(s)
