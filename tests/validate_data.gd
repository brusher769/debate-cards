extends Node
## Valida data/cards.json, data/topics_normal.json, data/topics_indefendible.json, data/config.json
## y data/i18n.json, y avisa en español qué está mal y dónde (archivo e id). Código de salida
## distinto de 0 si hay errores. Los "avisos" (por ejemplo, falta la traducción de una carta) se
## muestran pero no cuentan como error.
##   godot --headless --path . res://tests/validate_data.tscn

const CARDS_PATH := "res://data/cards.json"
const TOPIC_PATHS := ["res://data/topics_normal.json", "res://data/topics_indefendible.json"]
const CONFIG_PATH := "res://data/config.json"
const I18N_PATH := "res://data/i18n.json"
## Efectos que el motor (scripts/core/debate_engine.gd) sabe ejecutar. Una carta nueva puede usar
## cualquiera de ellos con otros números o textos; un efecto que no esté aquí necesita código.
const NORMAL_EFFECTS := ["speak", "refute", "objection", "appeal", "decision"]
const WILD_EFFECTS := ["bribe", "verdict", "steal", "block", "innocent", "secret", "cancel",
	"contempt", "precedent", "end", "peek"]
const NORMAL_TIMINGS := ["turn", "interrupt"]
const WILD_TIMINGS := ["turn", "any", "none"]
const NUMERIC_CONFIG_KEYS := ["cartas_normales_por_mano", "comodines_por_mano", "monedas_iniciales",
	"monedas_maximas", "costo_cambiar_comodin", "costo_lupa_comodin_extra", "duracion_turno_seg",
	"ventana_respuesta_comodin_seg", "end_min_puntos", "end_min_minutos", "juez_puede_terminar_minutos",
	"tiempo_interrogar_respuesta_seg", "penalizacion_max_con_soborno", "penalizacion_veredicto_fallido",
	"refutacion_cadena_max", "inocente_perdida_max"]
const LIST_CONFIG_KEYS := ["puntos_juez", "apelacion_opciones_seg"]
## Claves de i18n que el código arma por partes (por ejemplo tr("OVER_" + razón)).
const DYNAMIC_KEYS := ["OVER_NO_CARDS", "OVER_END", "OVER_VERDICT", "OVER_JUDGE"]

var _errors: Array[String] = []
var _warnings: Array[String] = []


func _ready() -> void:
	_validate_config()
	_validate_cards()
	for path in TOPIC_PATHS:
		_validate_topics(path)
	_validate_i18n()
	_validate_used_keys()
	for w in _warnings:
		print("AVISO: ", w)
	if _errors.is_empty():
		print("VALIDACION OK: cards.json, topics_normal.json, topics_indefendible.json, config.json e i18n.json están bien.")
		get_tree().quit(0)
	else:
		printerr("Se encontraron %d problema(s):" % _errors.size())
		for e in _errors:
			printerr(" - ", e)
		get_tree().quit(1)


func _err(msg: String) -> void:
	_errors.append(msg)


func _warn(msg: String) -> void:
	_warnings.append(msg)


## Lee y parsea un JSON. Devuelve null y registra un error si el archivo falta o el JSON es
## inválido; en ese caso el llamador debe cortar la validación de ese archivo.
func _parse_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		_err("%s: el archivo no existe." % path)
		return null
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if parsed == null:
		_err("%s: JSON inválido, revisa la sintaxis (comas, comillas, llaves)." % path)
		return null
	return parsed


# ---------------------------------------------------------------------------
# Cartas
# ---------------------------------------------------------------------------

func _validate_cards() -> void:
	var parsed = _parse_json(CARDS_PATH)
	if parsed == null:
		return
	if typeof(parsed) != TYPE_DICTIONARY:
		_err("%s: debe ser un objeto con las listas \"normal\" y \"wild\"." % CARDS_PATH)
		return
	var ids := {}
	var normals_playable := 0
	for group in ["normal", "wild"]:
		if typeof(parsed.get(group)) != TYPE_ARRAY:
			_err("%s: falta la lista \"%s\"." % [CARDS_PATH, group])
			continue
		var list: Array = parsed[group]
		for i in list.size():
			var d = list[i]
			if typeof(d) != TYPE_DICTIONARY:
				_err("%s: la carta %s en la posición %d no es un objeto." % [CARDS_PATH, group, i])
				continue
			var id := str(d.get("id", "")).strip_edges()
			var where: String
			if id == "":
				where = "%s (%s, posición %d)" % [CARDS_PATH, group, i]
				_err("%s: falta \"id\"." % where)
			else:
				where = "%s (id=\"%s\")" % [CARDS_PATH, id]
				if ids.has(id):
					_err("%s: id repetido \"%s\"." % [CARDS_PATH, id])
				ids[id] = true
			_validate_common(d, where)
			if group == "normal":
				_validate_normal(d, where)
				if str(d.get("timing", "turn")) == "turn":
					normals_playable += 1
			else:
				_validate_wild(d, where)
	# Con la configuración actual tiene que alcanzar el mazo para repartir manos.
	var normals: Array = parsed.get("normal", []) if typeof(parsed.get("normal")) == TYPE_ARRAY else []
	var wilds: Array = parsed.get("wild", []) if typeof(parsed.get("wild")) == TYPE_ARRAY else []
	if normals.size() < Config.hand_normals:
		_err("%s: hay %d cartas normales y cada mano recibe %d distintas (cartas_normales_por_mano)." % [CARDS_PATH, normals.size(), Config.hand_normals])
	if wilds.size() < Config.hand_wilds:
		_err("%s: hay %d comodines y cada mano recibe %d (comodines_por_mano)." % [CARDS_PATH, wilds.size(), Config.hand_wilds])
	if normals_playable == 0:
		_err("%s: no hay ninguna carta normal que se juegue en tu turno (timing \"turn\"): nadie podría jugar." % CARDS_PATH)
	# Los textos ya con los marcadores reemplazados no deben dejar llaves sin resolver.
	var catalog := CardCatalog.new()
	catalog.load_from_json(CARDS_PATH)
	for c in catalog.normals + catalog.wilds:
		if c.text.contains("{") or c.text.contains("}"):
			_err("%s (id=\"%s\"): el texto tiene un marcador desconocido: %s" % [CARDS_PATH, c.id, c.text])


func _validate_common(d: Dictionary, where: String) -> void:
	if str(d.get("name", "")).strip_edges() == "":
		_err("%s: el nombre (\"name\") está vacío." % where)
	if str(d.get("text", "")).strip_edges() == "":
		_err("%s: el texto (\"text\") está vacío." % where)
	for lang in _other_languages():
		if str(d.get("name_%s" % lang, "")).strip_edges() == "" or str(d.get("text_%s" % lang, "")).strip_edges() == "":
			_warn("%s: falta \"name_%s\" o \"text_%s\"; en ese idioma se mostrará en español." % [where, lang, lang])
	var img := str(d.get("image", "")).strip_edges()
	if img != "" and not FileAccess.file_exists(img):
		_err("%s: la imagen \"%s\" no existe." % [where, img])


func _validate_normal(d: Dictionary, where: String) -> void:
	var effect := str(d.get("effect", ""))
	if not NORMAL_EFFECTS.has(effect):
		_err("%s: efecto \"%s\" desconocido para una carta normal (%s)." % [where, effect, ", ".join(NORMAL_EFFECTS)])
	var timing := str(d.get("timing", "turn"))
	if not NORMAL_TIMINGS.has(timing):
		_err("%s: timing \"%s\" desconocido (debe ser turn o interrupt)." % [where, timing])
	var scoring := str(d.get("scoring", "free"))
	if scoring != "free" and scoring != "decision":
		_err("%s: scoring \"%s\" desconocido (debe ser free o decision)." % [where, scoring])
	if scoring == "decision":
		for key in ["pass", "fail"]:
			var block = d.get(key)
			if typeof(block) != TYPE_DICTIONARY:
				_err("%s: una carta de decisión necesita \"%s\": {\"self\": n, \"rival\": n}." % [where, key])
				continue
			for who in ["self", "rival"]:
				if block.has(who) and not _is_number(block[who]):
					_err("%s: \"%s.%s\" debe ser un número." % [where, key, who])
	if effect == "objection" and timing != "interrupt":
		_warn("%s: una Objeción normalmente es de timing \"interrupt\"." % where)


func _validate_wild(d: Dictionary, where: String) -> void:
	var effect := str(d.get("effect", ""))
	if not WILD_EFFECTS.has(effect):
		_err("%s: efecto \"%s\" desconocido para un comodín (%s). Un efecto nuevo necesita código en debate_engine.gd." % [where, effect, ", ".join(WILD_EFFECTS)])
	var timing := str(d.get("timing", "turn"))
	if not WILD_TIMINGS.has(timing):
		_err("%s: timing \"%s\" desconocido (debe ser turn, any o none)." % [where, timing])
	if typeof(d.get("answerable_by", [])) != TYPE_ARRAY:
		_err("%s: \"answerable_by\" debe ser una lista de efectos." % where)
	else:
		for r in d.get("answerable_by", []):
			if not WILD_EFFECTS.has(str(r)):
				_err("%s: \"answerable_by\" menciona un efecto desconocido \"%s\"." % [where, r])
	if typeof(d.get("params", {})) != TYPE_DICTIONARY:
		_err("%s: \"params\" debe ser un objeto." % where)


func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


# ---------------------------------------------------------------------------
# Preguntas
# ---------------------------------------------------------------------------

func _validate_topics(path: String) -> void:
	var parsed = _parse_json(path)
	if parsed == null:
		return
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("topics") or typeof(parsed["topics"]) != TYPE_ARRAY:
		_err("%s: falta la clave \"topics\" (debe ser una lista de preguntas)." % path)
		return
	if (parsed["topics"] as Array).size() < 10:
		_warn("%s: solo hay %d preguntas; con pocas se repiten enseguida." % [path, parsed["topics"].size()])
	var seen := {}
	for i in parsed["topics"].size():
		var entry = parsed["topics"][i]
		# Una pregunta es un texto suelto (todos los idiomas) o un objeto {"es": ..., "en": ...}.
		var t := str(entry.get("es", "") if typeof(entry) == TYPE_DICTIONARY else entry).strip_edges()
		if t == "":
			_err("%s: hay una pregunta vacía en la posición %d." % [path, i])
		elif seen.has(t):
			_err("%s: pregunta repetida \"%s\"." % [path, t])
		else:
			seen[t] = true
		if typeof(entry) == TYPE_DICTIONARY:
			for lang in _other_languages():
				if str(entry.get(lang, "")).strip_edges() == "":
					_warn("%s: a la pregunta \"%s\" le falta la versión \"%s\"; en ese idioma se mostrará en español." % [path, t, lang])
		elif _other_languages().size() > 0:
			_warn("%s: la pregunta \"%s\" es un texto suelto; en otros idiomas se mostrará igual." % [path, t])


# ---------------------------------------------------------------------------
# Configuración
# ---------------------------------------------------------------------------

func _validate_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		return # config.json es opcional: sin él se usan los valores por defecto de Config.
	var parsed = _parse_json(CONFIG_PATH)
	if parsed == null:
		return
	if typeof(parsed) != TYPE_DICTIONARY:
		_err("%s: debe ser un objeto JSON con las claves de ajustes." % CONFIG_PATH)
		return
	for key in NUMERIC_CONFIG_KEYS:
		if parsed.has(key) and not _is_number(parsed[key]):
			_err("%s: \"%s\" debe ser un número." % [CONFIG_PATH, key])
	for key in LIST_CONFIG_KEYS:
		if not parsed.has(key):
			continue
		var v = parsed[key]
		if typeof(v) != TYPE_ARRAY or (v as Array).is_empty():
			_err("%s: \"%s\" debe ser una lista de números, por ejemplo [5, -2, -1]." % [CONFIG_PATH, key])
			continue
		for n in v:
			if not _is_number(n):
				_err("%s: \"%s\" tiene un valor que no es número: %s." % [CONFIG_PATH, key, n])
	for key in ["duracion_turno_seg", "ventana_respuesta_comodin_seg", "tiempo_interrogar_respuesta_seg"]:
		if parsed.has(key) and _is_number(parsed[key]) and float(parsed[key]) <= 0.0:
			_err("%s: \"%s\" debe ser mayor que 0." % [CONFIG_PATH, key])
	if parsed.has("monedas_iniciales") and parsed.has("monedas_maximas") \
			and _is_number(parsed["monedas_iniciales"]) and _is_number(parsed["monedas_maximas"]) \
			and float(parsed["monedas_maximas"]) < float(parsed["monedas_iniciales"]):
		_err("%s: \"monedas_maximas\" no puede ser menor que \"monedas_iniciales\"." % CONFIG_PATH)
	for key in ["penalizacion_max_con_soborno", "penalizacion_veredicto_fallido", "inocente_perdida_max"]:
		if parsed.has(key) and _is_number(parsed[key]) and float(parsed[key]) > 0.0:
			_warn("%s: \"%s\" suele ser un número negativo (es una pérdida de puntos)." % [CONFIG_PATH, key])


## Idiomas distintos del español (el base), tomados de Settings.LANGUAGES.
func _other_languages() -> Array:
	var out: Array = []
	for code in Settings.LANGUAGES:
		if code != "es":
			out.append(code)
	return out


# ---------------------------------------------------------------------------
# Traducciones
# ---------------------------------------------------------------------------

func _validate_i18n() -> void:
	var parsed = _parse_json(I18N_PATH)
	if parsed == null:
		return
	if typeof(parsed) != TYPE_DICTIONARY:
		_err("%s: debe ser un objeto con un bloque por idioma." % I18N_PATH)
		return
	var base: Dictionary = {}
	if typeof(parsed.get("es")) == TYPE_DICTIONARY:
		base = parsed["es"]
	else:
		_err("%s: falta el bloque \"es\" (el idioma base)." % I18N_PATH)
		return
	var known_markers: Dictionary = Config.markers()
	for lang in Settings.LANGUAGES:
		if typeof(parsed.get(lang)) != TYPE_DICTIONARY:
			_err("%s: falta el bloque \"%s\"." % [I18N_PATH, lang])
			continue
		var block: Dictionary = parsed[lang]
		for key in base:
			if not block.has(key):
				_err("%s: a la clave \"%s\" le falta la traducción \"%s\"." % [I18N_PATH, key, lang])
			elif str(block[key]).strip_edges() == "":
				_err("%s: la clave \"%s\" está vacía en \"%s\"." % [I18N_PATH, key, lang])
			elif _placeholders(str(block[key])) != _placeholders(str(base[key])):
				_err("%s: la clave \"%s\" en \"%s\" usa distintos %%s/%%d o {llaves} que en español." % [I18N_PATH, key, lang])
		for key in block:
			if not base.has(key):
				_err("%s: la clave \"%s\" existe en \"%s\" pero no en \"es\"." % [I18N_PATH, key, lang])
			# Los {marcadores} de la guía tienen que existir en Config.markers().
			for m in _placeholders(str(block[key])):
				if m.begins_with("{") and not known_markers.has(m.substr(1, m.length() - 2)):
					_err("%s: la clave \"%s\" (%s) usa el marcador desconocido %s." % [I18N_PATH, key, lang, m])


## Marcadores de un texto (%s, %d, %+d y {nombre}), en orden, para compararlos entre idiomas.
func _placeholders(text: String) -> Array:
	var re := RegEx.new()
	re.compile("%[+\\-]?[sd]|\\{[a-z_]+\\}")
	var out: Array = []
	for m in re.search_all(text):
		out.append(m.get_string())
	return out


## Toda clave que el código o las escenas usan tiene que existir en i18n.json (si no, se vería
## cruda en pantalla). Revisa tr("CLAVE"), TranslationServer.translate("CLAVE") y los textos de
## las escenas que son una clave.
func _validate_used_keys() -> void:
	var parsed = _parse_json(I18N_PATH)
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("es")) != TYPE_DICTIONARY:
		return
	var keys: Dictionary = parsed["es"]
	var re_call := RegEx.new()
	re_call.compile("(?:\\btr|translate)\\(\"([A-Z][A-Z0-9_]+)\"\\s*\\)")
	var re_scene := RegEx.new()
	re_scene.compile("\\btext = \"([A-Z][A-Z0-9_]{3,})\"")
	for path in _files_under("res://scripts", "gd"):
		# Los comentarios (## ...) pueden nombrar claves de ejemplo: solo se revisa el código.
		for line in FileAccess.get_file_as_string(path).split("\n"):
			if line.strip_edges().begins_with("#"):
				continue
			for m in re_call.search_all(line):
				if not keys.has(m.get_string(1)):
					_err("%s: usa la clave de traducción \"%s\", que no existe en i18n.json." % [path, m.get_string(1)])
	for path in _files_under("res://scenes", "tscn"):
		var text := FileAccess.get_file_as_string(path)
		for m in re_scene.search_all(text):
			if not keys.has(m.get_string(1)):
				_err("%s: el texto \"%s\" parece una clave de traducción que no existe en i18n.json." % [path, m.get_string(1)])
	for k in DYNAMIC_KEYS:
		if not keys.has(k):
			_err("%s: falta la clave \"%s\" (el código la arma por partes)." % [I18N_PATH, k])


func _files_under(dir_path: String, extension: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.get_extension() == extension:
			out.append(dir_path.path_join(f))
	for sub in dir.get_directories():
		out.append_array(_files_under(dir_path.path_join(sub), extension))
	return out
