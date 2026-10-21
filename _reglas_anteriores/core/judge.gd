class_name Judge
extends RefCounted
## Contrato del juez. HumanJudge (un amigo con la interfaz de puntuación) lo implementa hoy;
## un AIJudge (API o modelo propio) podrá implementarlo mañana sin tocar el resto del juego.
##
## Uso: RoundManager llama request_verdict() y espera la señal verdict_ready.
## verdicts[i] es el Verdict de entries[i].

signal verdict_ready(verdicts: Array)


func request_verdict(_topic: String, _entries: Array) -> void:
	push_error("Judge.request_verdict() no está implementado en esta clase.")
