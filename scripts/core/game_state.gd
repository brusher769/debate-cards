extends Node
## Autoload "GameState": la sala en la que se juega en esta pantalla. En local (una sola pantalla)
## guarda una GameRoom con los 3 jugadores y la partida en curso; en línea guarda el motor espejo
## que reconstruye el cliente (ver Net). Las reglas viven en DebateEngine.

const MODES := GameRoom.MODES

var players: Array[PlayerData] = []
## "normal" o "indefendible".
var mode := "normal"
## La partida en curso: un DebateEngine (en línea, el motor espejo). Null hasta que empieza una.
var engine: DebateEngine
var catalog: CardCatalog
## Cuántas partidas se han jugado en esta sala.
var games_played := 0
## Índice del jugador que está frente a ESTA pantalla en una partida en línea; -1 = local (los 3
## comparten la pantalla y hay pantalla de relevo).
var viewer_index := -1

var _room: GameRoom


## Prepara una sala local nueva con esos 3 jugadores. La partida se crea con start_game().
func new_room(names: Array[String], game_mode: String) -> void:
	_room = GameRoom.new()
	_room.setup(names, game_mode)
	viewer_index = -1
	_copy_from_room()


## Empieza una partida local nueva en la sala: roles al azar, manos, monedas y primera pregunta.
func start_game(rng: RandomNumberGenerator = null) -> void:
	_room.start_game(rng)
	_copy_from_room()


## Prepara el estado para jugar en línea: `mirror` es el motor espejo que actualiza Net y `slot`
## el lugar de este jugador en la sala.
func use_online(mirror: DebateEngine, slot: int) -> void:
	_room = null
	engine = mirror
	players = mirror.players
	catalog = mirror.catalog
	mode = mirror.mode
	viewer_index = slot


## true si esta pantalla es de una partida en línea.
func is_online() -> bool:
	return viewer_index >= 0


## El texto de una pregunta en el idioma actual. En línea el servidor manda la pregunta con todos
## los idiomas ({"es": ..., "en": ...} como texto JSON) y aquí se elige el del jugador.
func topic_display(raw: String) -> String:
	if raw.begins_with("{"):
		var parsed = JSON.parse_string(raw)
		if typeof(parsed) == TYPE_DICTIONARY:
			return GameRoom.topic_in_language(parsed, Settings.language)
	return raw


func _copy_from_room() -> void:
	players = _room.players
	mode = _room.mode
	engine = _room.engine
	catalog = _room.catalog
	games_played = _room.games_played
