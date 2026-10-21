class_name Deck
extends RefCounted
## Mazo con dos montones (argumentos y especiales) para poder controlar la mezcla de la mano:
## nunca hay más de Config.max_specials_in_hand especiales, así que siempre quedan argumentos jugables.

var _arg_pile: Array[CardData] = []
var _arg_discard: Array[CardData] = []
var _special_pile: Array[CardData] = []
var _special_discard: Array[CardData] = []


func load_from_json(path: String) -> bool:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("cards"):
		push_error("Deck: no pude leer las cartas de %s" % path)
		return false
	for d in parsed["cards"]:
		for i in int(d.get("copies", 1)):
			var c := CardData.from_dict(d)
			if c.is_special():
				_special_pile.append(c)
			else:
				_arg_pile.append(c)
	_arg_pile.shuffle()
	_special_pile.shuffle()
	return true


## Completa la mano del jugador hasta `size` cartas.
func fill_hand(player: PlayerData, size: int) -> void:
	while player.hand.size() < size:
		var specials_in_hand := 0
		for c in player.hand:
			if c.is_special():
				specials_in_hand += 1
		var want_special := specials_in_hand < Config.max_specials_in_hand and randf() < Config.special_draw_chance
		var card := _draw(want_special)
		if card == null:
			card = _draw(not want_special)
		if card == null:
			return
		player.hand.append(card)


func discard(card: CardData) -> void:
	if card.is_special():
		_special_discard.append(card)
	else:
		_arg_discard.append(card)


func _draw(special: bool) -> CardData:
	var pile: Array[CardData] = _special_pile if special else _arg_pile
	var discarded: Array[CardData] = _special_discard if special else _arg_discard
	if pile.is_empty():
		pile.append_array(discarded)
		discarded.clear()
		pile.shuffle()
	if pile.is_empty():
		return null
	return pile.pop_back()
