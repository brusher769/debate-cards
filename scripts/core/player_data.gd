class_name PlayerData
extends RefCounted
## Datos de un jugador de la sala. Los campos de "durante la partida" se reinician en reset_for_game().

var display_name := ""
var index := 0
## Monedas de sobornos no descubiertos que el jugador guarda como juez hasta que le toque debatir.
var bank := 0

# --- Durante una partida ---
var score := 0
var coins := 0
## Cartas normales en la mano (pueden repetirse solo si te las robaron con Robar carta).
var hand: Array[CardData] = []
## Comodines que tiene (normalmente uno; la Lupa puede dar uno más).
var wilds: Array[CardData] = []
## true si ya jugó algún comodín (ya no puede cambiarlo por monedas).
var wild_played := false
## Última carta normal y último comodín que jugó (sirven a Jurisprudencia y a la mesa).
var last_normal: CardData = null
var last_wild: CardData = null
## Efectos activos sobre este jugador.
var blocked := false ## Cautela: su próximo turno no puede usar cartas.
var innocent_left := 0 ## Inocente: cuántos turnos más dura.
var contempt := false ## Desacato: la próxima resolución del juez sobre él va al rival.
var bribe_shield := false ## Soborno aceptado: el juez no puede bajarle más de bribe_max_penalty.
var repeat_pending := false ## Jurisprudencia: en su siguiente turno repite su última carta normal.


func reset_for_game() -> void:
	score = 0
	coins = 0
	hand.clear()
	wilds.clear()
	wild_played = false
	last_normal = null
	last_wild = null
	blocked = false
	innocent_left = 0
	contempt = false
	bribe_shield = false
	repeat_pending = false
