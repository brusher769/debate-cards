extends Node
## Vista previa de la escena 3D sin HUD: recorre las cámaras y guarda capturas (SHOT_DIR).
##   SHOT_DIR=/ruta godot --path . res://tests/stage_preview.tscn
## (necesita render real: no sirve con --headless)

var _dir := ""
var _n := 0


func _ready() -> void:
	_dir = OS.get_environment("SHOT_DIR")
	_run.call_deferred()


func _shot(label: String) -> void:
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if _dir == "":
		return
	_n += 1
	get_viewport().get_texture().get_image().save_png("%s/p%02d_%s.png" % [_dir, _n, label])


## La mano de un jugador tal como se dibuja: cartas normales y comodines.
func _cards_of(p: PlayerData) -> Array:
	var cards: Array = []
	cards.append_array(p.hand)
	cards.append_array(p.wilds)
	return cards


func _run() -> void:
	Settings.reset_to_defaults(false)
	var names: Array[String] = ["Ana", "Beto", "Caro"]
	GameState.new_room(names, "normal")
	GameState.start_game()
	var judge := GameState.engine.judge
	var deb := GameState.engine.debaters
	var stances := {deb[0]: "De acuerdo", deb[1]: "En desacuerdo"}

	var stage := Stage3D.new()
	add_child(stage)
	await get_tree().process_frame
	stage.set_roles(judge, deb, stances)
	stage.set_view(&"overview", false)
	await _shot("overview")

	stage.set_active_player(deb[0])
	var hand_a := _cards_of(deb[0])
	stage.show_hand(deb[0], hand_a, hand_a)
	await _shot("mano_A")
	stage.select_card(deb[0].hand[1])
	await _shot("mano_A_seleccion")
	stage.hide_hand()

	var normals := {}
	var wilds := {}
	for p in deb:
		normals[p] = p.hand[0]
		wilds[p] = p.wilds[0]
	stage.sync_table(normals, {}, true, true)
	stage.set_view(&"table", false)
	await _shot("mesa_cartas_normales")
	stage.sync_table(normals, wilds, true, true)
	stage.focus_cards([normals[deb[0]]])
	stage.set_active_player(deb[0])
	await _shot("mesa_discurso")

	stage.set_view(&"judge", false)
	stage.set_active_player(judge)
	stage.focus_cards([])
	await _shot("juez")

	# Mano con una carta atenuada (no jugable) y con un comodín extra: 7 cartas.
	var hand_b := _cards_of(deb[1])
	hand_b.append(GameState.catalog.by_id("lupa"))
	stage.show_hand(deb[1], hand_b, hand_b.slice(0, 3))
	await _shot("mano_B_7_cartas")
	print("PREVIEW OK")
	get_tree().quit()
