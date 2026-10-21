class_name GameRoom
extends RefCounted
## Una sala: los 3 jugadores que juegan varias partidas seguidas (REGLAS_DEBATE.md secciones 2 y 8).
## En cada partida los roles (2 debatientes + 1 juez) se reparten al azar y las monedas de sobornos
## no descubiertos que guardaba un juez pasan a quien vuelva a debatir. La usan GameState (partida
## local en una pantalla) y el servidor en línea (una GameRoom por sala).

const TOPIC_FILES := {
	"normal": "res://data/topics_normal.json",
	"indefendible": "res://data/topics_indefendible.json",
}
const MODES: Array[String] = ["normal", "indefendible"]

var players: Array[PlayerData] = []
## "normal" o "indefendible".
var mode := "normal"
## La partida en curso (null hasta llamar a start_game()).
var engine: DebateEngine
var catalog: CardCatalog
## Cuántas partidas se han jugado en esta sala.
var games_played := 0
## true = las preguntas se guardan con todos los idiomas ({"es": ..., "en": ...} como texto JSON) para que
## cada cliente la muestre en el suyo. Lo usa el servidor en línea.
var all_languages := false

var _all_topics: Array[String] = []
var _topics_left: Array[String] = []


## Prepara la sala con esos jugadores (en ese orden: su índice es su lugar en la sala).
func setup(names: Array[String], game_mode: String) -> void:
	players.clear()
	for i in names.size():
		var p := PlayerData.new()
		p.display_name = names[i]
		p.index = i
		players.append(p)
	mode = game_mode if MODES.has(game_mode) else "normal"
	games_played = 0
	engine = null


## Empieza una partida nueva: roles al azar, manos, monedas y primera pregunta.
func start_game(rng: RandomNumberGenerator = null) -> void:
	catalog = CardCatalog.load_default()
	_load_topics()
	var r := rng
	if r == null:
		r = RandomNumberGenerator.new()
		r.randomize()
	var judge_player := players[r.randi() % players.size()]
	engine = DebateEngine.create(catalog, players, judge_player, mode, next_topic, r)
	games_played += 1


## Una pregunta al azar de la lista del modo, sin repetir hasta agotarla.
func next_topic() -> String:
	if _topics_left.is_empty():
		_topics_left.append_array(_all_topics)
		_topics_left.shuffle()
	if _topics_left.is_empty():
		return TranslationServer.translate("NO_TOPICS")
	return _topics_left.pop_back()


func _load_topics() -> void:
	_all_topics.clear()
	_topics_left.clear()
	var path: String = TOPIC_FILES[mode]
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("topics"):
		for t in parsed["topics"]:
			_all_topics.append(_topic_text(t))
	else:
		push_error("GameRoom: no pude leer las preguntas de %s" % path)


## Una pregunta puede ser un texto suelto (vale para todos los idiomas) o un objeto {"es": ..., "en": ...}.
func _topic_text(t: Variant) -> String:
	if typeof(t) != TYPE_DICTIONARY:
		return str(t)
	if all_languages:
		return JSON.stringify(t)
	return topic_in_language(t, Settings.language)


## El texto de una pregunta {"es": ..., "en": ...} en un idioma (o en español si falta).
static func topic_in_language(t: Dictionary, lang: String) -> String:
	var text := str(t.get(lang, ""))
	return text if text != "" else str(t.get("es", ""))
