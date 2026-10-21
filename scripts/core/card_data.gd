class_name CardData
extends Resource
## Una carta del juego (normal o comodín). Todo lo que la define vive en data/cards.json:
## el motor de reglas (DebateEngine) solo lee estos campos, así que cambiar un número o el texto
## de una carta no requiere tocar código.

enum Kind { NORMAL, WILD }
## FREE: el juez puntúa +5/-2/-1. DECISION: el juez solo decide "procede / no procede" y los puntos
## son fijos (pass_*/fail_*). NONE: los comodines no los puntúa el juez.
enum Scoring { FREE, DECISION, NONE }

@export var id := ""
@export var kind: Kind = Kind.NORMAL
## Nombre corto de la carta (título).
@export var title := ""
## Descripción de lo que hace, ya con los números de la configuración puestos.
@export_multiline var text := ""
## Imagen opcional para la carta.
@export var image: Texture2D

## Comportamiento que ejecuta el motor: speak, refute, objection, appeal, decision (normales) o
## bribe, verdict, steal, block, innocent, secret, cancel, contempt, precedent, end, peek (comodines).
var effect := ""
var scoring: Scoring = Scoring.FREE
## Normales: "turn" (se juega en tu turno) o "interrupt" (durante la intervención del rival).
## Comodines: "turn" (tu turno), "any" (en cualquier momento) o "none" (solo como respuesta).
var timing := "turn"
## Comodines: efectos de comodín que pueden responder a este (ventana de respuesta).
var answerable_by: Array[String] = []
## Segundos de la intervención (0 = duracion_turno_seg).
var seconds := 0
## true = tras hablar, el rival responde (Interrogar, Definición, Desafío).
var answer := false
## Objeción: si procede, quien la jugó toma la palabra.
var takes_floor := false
## Puntos si la decisión procede / no procede, para quien jugó la carta (self) y su rival (rival).
var pass_self := 0
var pass_rival := 0
var fail_self := 0
var fail_rival := 0
## Datos propios de un efecto (por ejemplo lose_cards del Soborno o duration_turns de Inocente).
var params: Dictionary = {}


static func from_dict(d: Dictionary, kind_value: Kind) -> CardData:
	var c := CardData.new()
	c.id = str(d.get("id", ""))
	c.kind = kind_value
	c.effect = str(d.get("effect", ""))
	c.timing = str(d.get("timing", "turn"))
	c.scoring = _scoring_from_string(str(d.get("scoring", "none" if kind_value == Kind.WILD else "free")))
	c.seconds = int(d.get("seconds", 0))
	c.answer = bool(d.get("answer", false))
	c.takes_floor = bool(d.get("takes_floor", false))
	for k in d.get("answerable_by", []):
		c.answerable_by.append(str(k))
	var pass_d: Dictionary = d.get("pass", {})
	c.pass_self = int(pass_d.get("self", 0))
	c.pass_rival = int(pass_d.get("rival", 0))
	var fail_d: Dictionary = d.get("fail", {})
	c.fail_self = int(fail_d.get("self", 0))
	c.fail_rival = int(fail_d.get("rival", 0))
	var p = d.get("params", {})
	c.params = p if typeof(p) == TYPE_DICTIONARY else {}
	c.title = _localized(d, "name")
	c.text = c._apply_markers(_localized(d, "text"))
	var img_path := str(d.get("image", ""))
	if img_path != "" and ResourceLoader.exists(img_path):
		c.image = load(img_path)
	return c


## Texto en el idioma actual: los campos base ("name", "text") están en español y la versión en
## otro idioma va en "name_en", "text_en"... Si falta la traducción se usa el español.
static func _localized(d: Dictionary, field: String) -> String:
	if Settings.language != "es":
		var translated := str(d.get("%s_%s" % [field, Settings.language], ""))
		if translated != "":
			return translated
	return str(d.get(field, ""))


## Reemplaza en el texto los marcadores {llave} por los números de Config y de la propia carta
## (pass_self, pass_rival, fail_self, fail_rival y todo lo de "params"), para que el texto nunca
## quede desactualizado si cambias un valor en los datos.
func _apply_markers(raw: String) -> String:
	var values := Config.markers()
	values["pass_self"] = "%+d" % pass_self
	values["pass_rival"] = "%+d" % pass_rival
	values["fail_self"] = "%+d" % fail_self
	values["fail_rival"] = "%+d" % fail_rival
	for k in params:
		var v = params[k]
		# El JSON entrega los números como decimales (2.0): se muestran como enteros (2).
		values[str(k)] = int(v) if typeof(v) == TYPE_FLOAT and v == floorf(v) else v
	return raw.format(values)


static func _scoring_from_string(s: String) -> Scoring:
	match s:
		"decision":
			return Scoring.DECISION
		"none":
			return Scoring.NONE
		_:
			return Scoring.FREE


func is_wild() -> bool:
	return kind == Kind.WILD


## true = solo se puede jugar durante la intervención del rival (Refutar y Objeción).
func is_interrupt() -> bool:
	return kind == Kind.NORMAL and timing == "interrupt"


## Segundos que dura la intervención de esta carta.
func speech_seconds() -> int:
	return seconds if seconds > 0 else Config.turn_seconds
