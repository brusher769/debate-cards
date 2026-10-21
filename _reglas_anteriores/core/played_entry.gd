class_name PlayedEntry
extends RefCounted
## Una jugada que se defiende en voz alta y el juez puntúa: un argumento, una refutación
## o una falacia. (La carta de Evidencia no es una jugada aparte: se pega al argumento.)

## CardData.Type.ARGUMENT, REFUTE o FALLACY.
var kind: CardData.Type = CardData.Type.ARGUMENT
var player: PlayerData
var card: CardData
## Carta de Evidencia que refuerza este argumento (solo si kind == ARGUMENT).
var evidence: CardData = null
## Argumento atacado (solo si kind == REFUTE o FALLACY).
var target: PlayedEntry = null


func describe() -> String:
	match kind:
		CardData.Type.ARGUMENT:
			var s := TranslationServer.translate("DESC_ARGUMENT") % [player.display_name, card.summary]
			if evidence != null:
				s += TranslationServer.translate("DESC_EVIDENCE_SUFFIX")
			return s
		CardData.Type.REFUTE:
			return TranslationServer.translate("DESC_REFUTE") % [player.display_name, target.player.display_name]
		CardData.Type.FALLACY:
			return TranslationServer.translate("DESC_FALLACY") % [player.display_name, target.player.display_name]
	return player.display_name
