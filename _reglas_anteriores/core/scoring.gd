class_name Scoring
extends RefCounted
## Reglas de puntuación en un solo lugar. Los números (nota máxima, bonus, factor de Refutar,
## bonus de Evidencia, penalización de Falacia) vienen del autoload Config (data/config.json).


## Calcula los puntos de la ronda. verdicts[i] corresponde a entries[i].
## Devuelve un Array de Dictionary: { "player": PlayerData, "total": int, "lines": Array[String] }
## con un elemento por debatiente. No modifica a los jugadores; eso lo hace RoundManager.
static func compute(entries: Array, verdicts: Array) -> Array:
	var arg_points := {} # PlayedEntry (argumento) -> int
	var notes := {} # PlayerData -> Array[String]
	var penalty := {} # PlayerData -> int
	var order: Array = [] # PlayerData, en orden de aparición

	for e: PlayedEntry in entries:
		if not notes.has(e.player):
			notes[e.player] = []
			penalty[e.player] = 0
			order.append(e.player)

	# 1) Argumentos (+ evidencia).
	for i in entries.size():
		var e: PlayedEntry = entries[i]
		if e.kind != CardData.Type.ARGUMENT:
			continue
		var v: Verdict = verdicts[i]
		var pts := v.total()
		notes[e.player].append(TranslationServer.translate("SC_ARGUMENT") % [e.card.summary, v.base, v.bonus])
		if e.evidence != null:
			pts += Config.evidence_bonus
			notes[e.player].append(TranslationServer.translate("SC_EVIDENCE") % Config.evidence_bonus)
		arg_points[e] = pts

	# 2) Refutaciones: restan puntos al argumento atacado.
	for i in entries.size():
		var e: PlayedEntry = entries[i]
		if e.kind != CardData.Type.REFUTE:
			continue
		var v: Verdict = verdicts[i]
		var target: PlayedEntry = e.target
		var before: int = arg_points[target]
		var dmg := floori(v.total() * Config.refute_factor)
		arg_points[target] = maxi(before - dmg, 0)
		var lost: int = before - arg_points[target]
		notes[e.player].append(TranslationServer.translate("SC_REFUTE") % [v.base, v.bonus, lost, target.player.display_name])
		notes[target.player].append(TranslationServer.translate("SC_REFUTED") % [e.player.display_name, lost])

	# 3) Falacias: si el juez las valida anulan el argumento; si no, penalizan a quien las lanzó.
	for i in entries.size():
		var e: PlayedEntry = entries[i]
		if e.kind != CardData.Type.FALLACY:
			continue
		var v: Verdict = verdicts[i]
		var target: PlayedEntry = e.target
		if v.fallacy_valid:
			arg_points[target] = 0
			notes[e.player].append(TranslationServer.translate("SC_FALLACY_OK") % target.player.display_name)
			notes[target.player].append(TranslationServer.translate("SC_FALLACY_OK_TARGET") % e.player.display_name)
		else:
			penalty[e.player] += Config.fallacy_penalty
			notes[e.player].append(TranslationServer.translate("SC_FALLACY_BAD") % Config.fallacy_penalty)
			notes[target.player].append(TranslationServer.translate("SC_FALLACY_BAD_TARGET") % e.player.display_name)

	# 4) Total por jugador.
	var by_player := {} # PlayerData -> int
	for e: PlayedEntry in entries:
		if e.kind == CardData.Type.ARGUMENT:
			by_player[e.player] = arg_points[e]

	var results: Array = []
	for p: PlayerData in order:
		var total: int = by_player.get(p, 0) - penalty[p]
		results.append({"player": p, "total": total, "lines": notes[p]})
	return results
