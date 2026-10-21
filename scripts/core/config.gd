extends Node
## Autoload "Config": parámetros de las reglas, cargados desde data/config.json.
## Los nombres del JSON son los mismos que en el apartado 14 de REGLAS_DEBATE.md; aquí abajo
## cada uno tiene su variable (en inglés, como el resto del código) con el mismo valor por defecto.
## Si falta el archivo o una clave, se usa el valor por defecto: el juego nunca se rompe por un
## config.json incompleto. Se carga antes que GameState (ver orden de autoloads en project.godot).

const CONFIG_PATH := "res://data/config.json"

## cartas_normales_por_mano: cartas normales (todas distintas) que recibe cada debatiente.
var hand_normals := 5
## comodines_por_mano: comodines que recibe cada debatiente.
var hand_wilds := 1
## monedas_iniciales: monedas con las que empieza cada debatiente.
var coins_start := 5
## monedas_maximas: tope de monedas al empezar (5 + monedas de sobornos no descubiertos).
var coins_max := 10
## costo_cambiar_comodin: monedas que cuesta cambiar el comodín por otro al azar.
var swap_cost := 1
## costo_lupa_comodin_extra: monedas que cuesta el comodín extra de la Lupa.
var lupa_cost := 1
## duracion_turno_seg: segundos de una intervención.
var turn_seconds := 60
## ventana_respuesta_comodin_seg: segundos que tiene el rival para responder a un comodín.
var response_seconds := 10
## end_min_puntos: puntos que hacen falta para poder usar END.
var end_min_points := 20
## end_min_minutos: minutos de partida tras los cuales se puede usar END con cualquier puntaje.
var end_min_minutes := 5
## juez_puede_terminar_minutos: minutos de partida tras los cuales el juez puede terminarla.
var judge_end_minutes := 10
## tiempo_interrogar_respuesta_seg: segundos que tiene el rival para responder una pregunta
## (Interrogar, y también Definición y Desafío, que piden una respuesta igual).
var answer_seconds := 30
## puntos_juez: los únicos valores con los que el juez puntúa una intervención.
var judge_points: Array[int] = [5, -2, -1]
## penalizacion_max_con_soborno: lo máximo que el juez puede quitarle a quien lo sobornó.
var bribe_max_penalty := -1
## penalizacion_veredicto_fallido: puntos que pierde quien juega Veredicto sin haber soborno.
var verdict_fail_penalty := -2

# Ajustes que las reglas no numeran pero que también son datos (ver DECISIONES.md).
## apelacion_opciones_seg: tiempo extra que el juez puede conceder con Apelación.
var appeal_options: Array[int] = [0, 30, 60]
## refutacion_cadena_max: máximo de Refutar seguidas (la del rival y la respuesta).
var refute_chain_max := 2
## inocente_perdida_max: lo máximo que se puede perder mientras Inocente está activo.
var innocent_max_penalty := -1


func _ready() -> void:
	_load()


func _load() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Config: %s no es un JSON válido, uso los valores por defecto." % CONFIG_PATH)
		return
	hand_normals = int(parsed.get("cartas_normales_por_mano", hand_normals))
	hand_wilds = int(parsed.get("comodines_por_mano", hand_wilds))
	coins_start = int(parsed.get("monedas_iniciales", coins_start))
	coins_max = int(parsed.get("monedas_maximas", coins_max))
	swap_cost = int(parsed.get("costo_cambiar_comodin", swap_cost))
	lupa_cost = int(parsed.get("costo_lupa_comodin_extra", lupa_cost))
	turn_seconds = int(parsed.get("duracion_turno_seg", turn_seconds))
	response_seconds = int(parsed.get("ventana_respuesta_comodin_seg", response_seconds))
	end_min_points = int(parsed.get("end_min_puntos", end_min_points))
	end_min_minutes = int(parsed.get("end_min_minutos", end_min_minutes))
	judge_end_minutes = int(parsed.get("juez_puede_terminar_minutos", judge_end_minutes))
	answer_seconds = int(parsed.get("tiempo_interrogar_respuesta_seg", answer_seconds))
	judge_points = _int_list(parsed.get("puntos_juez"), judge_points)
	bribe_max_penalty = int(parsed.get("penalizacion_max_con_soborno", bribe_max_penalty))
	verdict_fail_penalty = int(parsed.get("penalizacion_veredicto_fallido", verdict_fail_penalty))
	appeal_options = _int_list(parsed.get("apelacion_opciones_seg"), appeal_options)
	refute_chain_max = int(parsed.get("refutacion_cadena_max", refute_chain_max))
	innocent_max_penalty = int(parsed.get("inocente_perdida_max", innocent_max_penalty))


## Convierte una lista del JSON en Array[int]; si no es una lista válida devuelve `fallback`.
func _int_list(value: Variant, fallback: Array[int]) -> Array[int]:
	if typeof(value) != TYPE_ARRAY or (value as Array).is_empty():
		return fallback
	var out: Array[int] = []
	for v in value:
		out.append(int(v))
	return out


## Todos los números que los textos de las cartas y de la guía pueden usar entre llaves,
## por ejemplo {end_points}. Un solo lugar para que el texto nunca quede desactualizado.
func markers() -> Dictionary:
	return {
		"hand_normals": hand_normals,
		"hand_wilds": hand_wilds,
		"coins_start": coins_start,
		"coins_max": coins_max,
		"swap_cost": swap_cost,
		"lupa_cost": lupa_cost,
		"turn_seconds": turn_seconds,
		"response_seconds": response_seconds,
		"end_points": end_min_points,
		"end_minutes": end_min_minutes,
		"judge_end_minutes": judge_end_minutes,
		"answer_seconds": answer_seconds,
		"judge_points": ", ".join(judge_points.map(func(n: int) -> String: return "%+d" % n)),
		"bribe_cap": bribe_max_penalty,
		"verdict_penalty": verdict_fail_penalty,
		"innocent_cap": innocent_max_penalty,
		"refute_chain": refute_chain_max,
	}
