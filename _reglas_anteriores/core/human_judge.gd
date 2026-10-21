class_name HumanJudge
extends Judge
## Juez humano: pide la entrada a la interfaz (input_requested) y espera a que la UI
## llame submit() con los veredictos.

signal input_requested(topic: String, entries: Array)


func request_verdict(topic: String, entries: Array) -> void:
	input_requested.emit(topic, entries)


func submit(verdicts: Array) -> void:
	verdict_ready.emit(verdicts)
