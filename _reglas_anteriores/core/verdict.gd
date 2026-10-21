class_name Verdict
extends RefCounted
## Veredicto del juez sobre UNA jugada (una entrada de la ronda).

## Nota base (0 a Config.max_base).
var base := 0
## Puntos extra por algo que impresionó al juez (0 a Config.max_bonus).
var bonus := 0
## Solo para cartas de Falacia: ¿el juez valida que el argumento del rival era una falacia?
var fallacy_valid := false


func total() -> int:
	return base + bonus
