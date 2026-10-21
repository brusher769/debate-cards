class_name CardCatalog
extends RefCounted
## Todas las cartas del juego, cargadas de data/cards.json: las normales y los comodines.

const CARDS_PATH := "res://data/cards.json"

var normals: Array[CardData] = []
var wilds: Array[CardData] = []


static func load_default() -> CardCatalog:
	var c := CardCatalog.new()
	c.load_from_json(CARDS_PATH)
	return c


func load_from_json(path: String) -> bool:
	normals.clear()
	wilds.clear()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("CardCatalog: no pude leer las cartas de %s" % path)
		return false
	for d in parsed.get("normal", []):
		normals.append(CardData.from_dict(d, CardData.Kind.NORMAL))
	for d in parsed.get("wild", []):
		wilds.append(CardData.from_dict(d, CardData.Kind.WILD))
	return not normals.is_empty()


func by_id(id: String) -> CardData:
	for c in normals:
		if c.id == id:
			return c
	for c in wilds:
		if c.id == id:
			return c
	return null
