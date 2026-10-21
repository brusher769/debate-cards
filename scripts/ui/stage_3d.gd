@tool
class_name Stage3D
extends Node3D
## (@tool: la sala se construye también dentro del editor, así la ves en la pestaña 3D al abrir
## scenes/table.tscn. Lo que se construye por código no se guarda en la escena.)
## Escena 3D de la partida: sala, mesa, estrado del juez, tres figuras simples, cartas y cámara.
## Se construye por código con primitivas (cajas, cápsulas...). Cuando tengas modelos propios se
## reemplazan las piezas de _build_*() sin tocar el resto.
##
## No conoce las reglas: recibe datos (jugadores, cartas) y avisa con card_clicked. La mesa 2D
## (HUD) y DebateEngine la dirigen desde table.gd.
##
## Distribución (vista desde arriba, -Z es "el fondo"):
##
##              B (fondo)
##        +----------------+
##   A -> |     MESA       |  [ estrado del juez ]  (a la derecha de la pantalla)
##        +----------------+
##              A (cerca de la cámara)

signal card_clicked(card: CardData)

# =============================================================================
# AJUSTES VISUALES — lo que más se toca sin tener que entender el resto del archivo.
# Nada de esto cambia las reglas del juego, solo cómo se ve. Ver también GUIA_MODIFICAR.md.
#   - PLAYER_COLORS: color de cada jugador (asiento 0, 1 y 2) en su cuerpo y su placa.
#   - SEAT_POS / SEAT_YAW: dónde se sienta cada asiento (A, B, juez) y hacia dónde mira
#     (yaw en radianes; PI = 180°, PI/2 = 90°).
#   - TABLE_SIZE: ancho (X) x profundidad (Z) del tablero de la mesa.
#   - SLOT_X / SLOT_Z: dónde caen las cartas sobre la mesa (X según si es la última carta
#     normal o el último comodín, Z según el asiento del jugador que la jugó).
#   - VIEWS: posición ("pos") y punto al que mira ("target") de cada cámara. "overview" es
#     la vista general, "table" y "judge" se usan durante la ronda, "hand_0"/"hand_1" son la
#     vista en primera persona al elegir carta (una por asiento de debatiente).
# =============================================================================

const TABLE_TOP := 0.78
const CARD_Y := TABLE_TOP + 0.012
const HAND_SCALE := 0.75
const HAND_SPACING := 0.43
## Ancho máximo (en metros) que puede ocupar la fila de cartas de la mano.
const HAND_MAX_WIDTH := 1.9
## Posición de la mano en el espacio de la cámara (la mano es hija de la cámara).
const HAND_OFFSET := Vector3(0, -0.42, -1.7)
const HAND_LIFT := Vector3(0, 0.7, 0.5)

const SEAT_A := 0 ## debatiente cercano a la cámara
const SEAT_B := 1 ## debatiente del fondo
const SEAT_J := 2 ## juez, en el estrado
## Posición (x, y, z) de cada asiento: [A, B, Juez]. El juez está más alto y a un costado (su estrado).
const SEAT_POS := [Vector3(0, 0, 1.6), Vector3(0, 0, -1.6), Vector3(2.9, 0.4, 0)]
## Rotación (yaw, en radianes) de cada asiento: hacia dónde mira la figura.
const SEAT_YAW := [PI, 0.0, -PI / 2.0]
## Color de cada jugador según su índice (0, 1, 2), en el mismo orden que se van creando.
const PLAYER_COLORS := [Color("4a90d9"), Color("e08a3a"), Color("4bb37a")]
const JUDGE_GOLD := Color("e0b43a")
## Ancho (X) x profundidad (Z) del tablero de madera de la mesa. El fieltro y las patas se
## calculan a partir de este tamaño en _build_table().
const TABLE_SIZE := Vector2(3.4, 1.9)
## Sitio de cada carta sobre la mesa: x según el tipo y z según el asiento (A cerca, B al fondo).
const SLOT_X := {"arg": -0.32, "spec": 0.32}
const SLOT_Z := [0.42, -0.42]

## Cámaras de la partida: "pos" es dónde está la cámara y "target" el punto al que mira.
const VIEWS := {
	# El HUD ocupa la parte de arriba y de abajo de la pantalla: las vistas dejan la escena en medio.
	&"overview": {"pos": Vector3(-0.4, 3.6, 5.8), "target": Vector3(0.5, 1.7, 0.0)},
	&"table": {"pos": Vector3(0.0, 2.85, 1.05), "target": Vector3(0.0, 0.78, -0.15)},
	&"judge": {"pos": Vector3(0.6, 2.3, 3.2), "target": Vector3(1.55, 1.9, -0.35)},
	&"hand_0": {"pos": Vector3(0.0, 1.9, 2.5), "target": Vector3(0.5, 0.75, 0.15)},
	&"hand_1": {"pos": Vector3(0.0, 1.9, -2.5), "target": Vector3(0.5, 0.75, -0.15)},
}

var current_view: StringName = &"overview"

var _camera: Camera3D
var _hand_root: Node3D
var _table_root: Node3D
var _figures: Array[Dictionary] = []
var _gavel: Node3D
var _seat_of := {} # PlayerData -> asiento
var _hand_cards: Array[Card3D] = []
var _hand_seat := -1
var _table_cards := {} # "asiento_tipo" -> Card3D
var _hover: Card3D = null
var _cam_tween: Tween


func _ready() -> void:
	_build_environment()
	_build_room()
	_build_table()
	_build_judge_stand()
	for seat in 3:
		_figures.append(_build_figure(seat))
	_build_camera()
	_table_root = Node3D.new()
	add_child(_table_root)
	set_view(&"overview", false)


# ---------------------------------------------------------------------------
# API pública (la usa table.gd)
# ---------------------------------------------------------------------------

## Sienta a cada jugador en su lugar: debatientes en A y B, juez en el estrado.
func set_roles(judge: PlayerData, debaters: Array, stances: Dictionary) -> void:
	_seat_of.clear()
	_seat_of[debaters[0]] = SEAT_A
	_seat_of[debaters[1]] = SEAT_B
	_seat_of[judge] = SEAT_J
	for p: PlayerData in _seat_of:
		var seat: int = _seat_of[p]
		var fig: Dictionary = _figures[seat]
		var color: Color = PLAYER_COLORS[p.index % PLAYER_COLORS.size()]
		var mat: StandardMaterial3D = fig["body_mat"]
		mat.albedo_color = color.darkened(0.6) if seat == SEAT_J else color
		var plate: Label3D = fig["plate"]
		if seat == SEAT_J:
			plate.text = "%s\n%s" % [p.display_name, tr("ROLE_JUDGE")]
			plate.modulate = JUDGE_GOLD
		else:
			plate.text = "%s\n%s" % [p.display_name, stances.get(p, "")]
			plate.modulate = Color.WHITE


## Anillo de luz bajo el jugador que está actuando (null = ninguno).
func set_active_player(p: PlayerData) -> void:
	for i in 3:
		_figures[i]["ring"].visible = false
	if p != null and _seat_of.has(p):
		_figures[_seat_of[p]]["ring"].visible = true


## Mueve la cámara a una vista: overview, table, judge, hand_0, hand_1.
func set_view(view: StringName, animate := true) -> void:
	current_view = view
	var v: Dictionary = VIEWS[view]
	var pos: Vector3 = v["pos"]
	var to := Transform3D(Basis.looking_at(v["target"] - pos, Vector3.UP), pos)
	if _cam_tween != null:
		_cam_tween.kill()
	if not animate or not is_inside_tree():
		_camera.transform = to
		return
	var from := _camera.transform
	_cam_tween = create_tween()
	_cam_tween.tween_method(_lerp_camera.bind(from, to), 0.0, 1.0, 0.8) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


## Muestra `cards` (la mano y los comodines de `player`) desde SU asiento (primera persona: su
## figura se oculta). Las cartas que no están en `playable` salen atenuadas y no se pueden elegir.
func show_hand(player: PlayerData, cards: Array, playable: Array) -> void:
	hide_hand()
	_hand_seat = _seat_of.get(player, SEAT_A)
	_figures[_hand_seat]["root"].visible = false
	set_view(StringName("hand_%d" % _hand_seat))
	var n := cards.size()
	# Con muchas cartas se juntan un poco para que quepan en pantalla.
	var spacing := minf(HAND_SPACING, HAND_MAX_WIDTH / maxf(n - 1, 1.0))
	for i in n:
		var data: CardData = cards[i]
		var c := Card3D.create(data)
		c.lift_dir = HAND_LIFT
		c.scale = Vector3.ONE * HAND_SCALE
		c.set_disabled(not playable.has(data))
		_hand_root.add_child(c)
		var t := float(i) - (n - 1) / 2.0
		c.rotation.z = -t * 0.06
		var home := Vector3(t * spacing, -absf(t) * 0.025, 0.0)
		c.position = home + Vector3(0, -1.0, 0.2)
		var tw := create_tween()
		tw.tween_interval(i * 0.05)
		tw.tween_property(c, "position", home, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_hand_cards.append(c)


func hide_hand() -> void:
	for c in _hand_cards:
		c.queue_free()
	_hand_cards.clear()
	_hover = null
	if _hand_seat >= 0:
		_figures[_hand_seat]["root"].visible = true
		_hand_seat = -1


## Resalta la carta elegida en la mano (null = ninguna).
func select_card(card: CardData) -> void:
	for c in _hand_cards:
		c.set_selected(card != null and c.card == card)


## Deja sobre la mesa las cartas jugadas. args: PlayerData -> última carta normal jugada (o null);
## specials: PlayerData -> último comodín jugado (o null). Es idempotente: solo crea, voltea o
## quita lo que cambió.
func sync_table(args: Dictionary, specials: Dictionary, args_up: bool, specials_up: bool) -> void:
	var wanted := {} # clave -> { "seat", "kind", "card", "up" }
	for p in args:
		if _seat_of.has(p) and args[p] != null:
			_want(wanted, _seat_of[p], "arg", args[p], args_up)
	for p in specials:
		if _seat_of.has(p) and specials[p] != null:
			_want(wanted, _seat_of[p], "spec", specials[p], specials_up)

	for key in _table_cards.keys():
		var existing: Card3D = _table_cards[key]
		if not wanted.has(key) or wanted[key]["card"] != existing.card:
			_discard_table_card(existing)
			_table_cards.erase(key)
	for key in wanted:
		var w: Dictionary = wanted[key]
		var node: Card3D = _table_cards.get(key)
		if node == null:
			_table_cards[key] = _spawn_table_card(w["seat"], w["kind"], w["card"], w["up"])
		else:
			node.set_face_up(w["up"])


## Resalta las cartas de la intervención actual y atenúa el resto (lista vacía = sin resaltar).
## Si se da `by`, solo cuentan las cartas de ese jugador (dos jugadores pueden tener sobre la mesa
## la misma carta y no deben resaltarse las dos).
func focus_cards(cards: Array, by: PlayerData = null) -> void:
	var seat: int = _seat_of.get(by, -1) if by != null else -1
	for key in _table_cards:
		var node: Card3D = _table_cards[key]
		var of_seat: bool = seat < 0 or int(str(key).split("_")[0]) == seat
		var on: bool = of_seat and cards.has(node.card)
		node.set_focused(on)
		node.set_dimmed(not cards.is_empty() and not on)


func clear_table() -> void:
	for key in _table_cards:
		_discard_table_card(_table_cards[key])
	_table_cards.clear()


## Martillazo del juez.
func gavel() -> void:
	var tw := create_tween()
	for i in 2:
		tw.tween_property(_gavel, "rotation:z", 0.02, 0.10).set_ease(Tween.EASE_IN)
		tw.tween_property(_gavel, "rotation:z", -0.6, 0.16).set_ease(Tween.EASE_OUT)


## Carta de la mano que hay bajo un punto de la pantalla, o null.
func pick_card_at(screen_pos: Vector2) -> CardData:
	var hit := _hand_card_at(screen_pos)
	return hit.card if hit != null else null


## Posición en pantalla de una carta (mano o mesa). Sirve para pruebas.
func card_screen_position(card: CardData) -> Vector2:
	for c in _hand_cards:
		if c.card == card:
			return _camera.unproject_position(c.global_position)
	for key in _table_cards:
		var node: Card3D = _table_cards[key]
		if node.card == card:
			return _camera.unproject_position(node.global_position)
	return Vector2(-1, -1)


func hand_card_count() -> int:
	return _hand_cards.size()


func table_card_count() -> int:
	return _table_cards.size()


func camera() -> Camera3D:
	return _camera


# ---------------------------------------------------------------------------
# Entrada: hover y clic sobre las cartas de la mano
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventMouseMotion:
		_set_hover(_hand_card_at(event.position))
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hit := _hand_card_at(event.position)
		if hit != null:
			card_clicked.emit(hit.card)


func _hand_card_at(screen_pos: Vector2) -> Card3D:
	if _hand_cards.is_empty():
		return null
	var origin := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	var best: Card3D = null
	var best_t := INF
	for c in _hand_cards:
		if c.is_disabled():
			continue
		var t := c.ray_hit(origin, dir)
		if t >= 0.0 and t < best_t:
			best = c
			best_t = t
	return best


func _set_hover(c: Card3D) -> void:
	if c == _hover:
		return
	if _hover != null and is_instance_valid(_hover):
		_hover.set_hovered(false)
	_hover = c
	if _hover != null:
		_hover.set_hovered(true)


# ---------------------------------------------------------------------------
# Cartas sobre la mesa
# ---------------------------------------------------------------------------

func _want(wanted: Dictionary, seat: int, kind: String, card: CardData, up: bool) -> void:
	wanted["%d_%s" % [seat, kind]] = {"seat": seat, "kind": kind, "card": card, "up": up}


func _slot_position(seat: int, kind: String) -> Vector3:
	return Vector3(SLOT_X[kind], CARD_Y, SLOT_Z[seat])


func _spawn_table_card(seat: int, kind: String, data: CardData, up: bool) -> Card3D:
	var node := Card3D.create(data, up)
	node.interactive = false
	_table_root.add_child(node)
	var target := _slot_position(seat, kind)
	var jitter := randf_range(-0.04, 0.04)
	node.rotation = Vector3(-PI / 2.0, jitter, 0.0)
	node.position = Vector3(0.0, 1.3, SEAT_POS[seat].z * 0.9)
	node.scale = Vector3.ONE * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(node, "position", target, 0.45).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	return node


func _discard_table_card(node: Card3D) -> void:
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector3.ONE * 0.01, 0.2)
	tw.tween_callback(node.queue_free)


func _lerp_camera(t: float, from: Transform3D, to: Transform3D) -> void:
	_camera.transform = Transform3D(from.basis.slerp(to.basis, t), from.origin.lerp(to.origin, t))


# ---------------------------------------------------------------------------
# Construcción de la sala (todo con primitivas; reemplazable por modelos)
# ---------------------------------------------------------------------------

func _mat(color: Color, roughness := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m


func _add_mesh(parent: Node, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _box(parent: Node, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _add_mesh(parent, b, pos, _mat(color))


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0b0e16")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b8c2e0")
	env.ambient_light_energy = 0.85
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(20), 0)
	sun.light_energy = 0.45
	sun.shadow_enabled = false
	add_child(sun)

	var lamp := SpotLight3D.new()
	lamp.position = Vector3(0, 4.4, 0.2)
	lamp.rotation.x = -PI / 2.0
	lamp.spot_range = 9.0
	lamp.spot_angle = 48.0
	lamp.light_color = Color("ffe2b0")
	lamp.light_energy = 4.0
	add_child(lamp)


func _build_room() -> void:
	var wall := Color("2a3450")
	_box(self, Vector3(18, 0.2, 18), Vector3(0, -0.1, 0), Color("3a3028")) # piso
	_box(self, Vector3(18, 7, 0.3), Vector3(0, 3.5, -8), wall) # fondo
	_box(self, Vector3(0.3, 7, 18), Vector3(-8, 3.5, 0), wall)
	_box(self, Vector3(0.3, 7, 18), Vector3(8, 3.5, 0), wall)
	_box(self, Vector3(18, 7, 0.3), Vector3(0, 3.5, 8), wall)
	# Alfombra bajo la mesa.
	var rug := CylinderMesh.new()
	rug.top_radius = 3.8
	rug.bottom_radius = 3.8
	rug.height = 0.02
	_add_mesh(self, rug, Vector3(0, 0.01, 0), _mat(Color("4a2630")))
	# Lámpara colgante sobre la mesa.
	var shade := CylinderMesh.new()
	shade.top_radius = 0.15
	shade.bottom_radius = 0.6
	shade.height = 0.35
	_add_mesh(self, shade, Vector3(0, 4.45, 0.2), _mat(Color("2a2a2f")))


func _build_table() -> void:
	var wood := Color("5a3d27")
	_box(self, Vector3(TABLE_SIZE.x, 0.08, TABLE_SIZE.y), Vector3(0, TABLE_TOP - 0.04, 0), wood)
	_box(self, Vector3(TABLE_SIZE.x - 0.2, 0.006, TABLE_SIZE.y - 0.2), Vector3(0, TABLE_TOP + 0.003, 0), Color("1f5f4a")) # fieltro
	for sx in [-1.55, 1.55]:
		for sz in [-0.8, 0.8]:
			_box(self, Vector3(0.14, TABLE_TOP - 0.08, 0.14), Vector3(sx, (TABLE_TOP - 0.08) / 2.0, sz), wood.darkened(0.25))


func _build_judge_stand() -> void:
	var wood := Color("4a3222")
	_box(self, Vector3(1.8, 0.4, 2.4), Vector3(2.9, 0.2, 0), wood) # estrado
	_box(self, Vector3(0.3, 0.6, 2.0), Vector3(2.2, 0.7, 0), wood.lightened(0.1)) # tribuna
	var block := CylinderMesh.new()
	block.top_radius = 0.09
	block.bottom_radius = 0.09
	block.height = 0.05
	_add_mesh(self, block, Vector3(2.2, 1.025, 0.45), _mat(Color("2a1c12")))
	# Martillo: el pivote está en el extremo del mango; en reposo queda levantado.
	_gavel = Node3D.new()
	_gavel.position = Vector3(2.52, 1.09, 0.45)
	_gavel.rotation.z = -0.6
	add_child(_gavel)
	_box(_gavel, Vector3(0.32, 0.03, 0.03), Vector3(-0.16, 0, 0), Color("7a5636"))
	var head := CylinderMesh.new()
	head.top_radius = 0.05
	head.bottom_radius = 0.05
	head.height = 0.14
	var head_node := _add_mesh(_gavel, head, Vector3(-0.32, 0, 0), _mat(Color("8a6238")))
	head_node.rotation.x = PI / 2.0


func _build_figure(seat: int) -> Dictionary:
	var root := Node3D.new()
	root.position = SEAT_POS[seat]
	root.rotation.y = SEAT_YAW[seat]
	add_child(root)
	var wood := Color("6b4a2f")
	_box(root, Vector3(0.55, 0.06, 0.55), Vector3(0, 0.45, 0), wood) # asiento
	_box(root, Vector3(0.55, 0.62, 0.06), Vector3(0, 0.78, -0.28), wood) # respaldo
	_box(root, Vector3(0.1, 0.42, 0.1), Vector3(0, 0.22, 0), wood.darkened(0.2)) # pata

	var body_mat := _mat(PLAYER_COLORS[seat % 3], 0.7)
	var torso := CapsuleMesh.new()
	torso.radius = 0.21
	torso.height = 0.78
	_add_mesh(root, torso, Vector3(0, 0.86, 0), body_mat)
	for side in [-1.0, 1.0]:
		var arm := CapsuleMesh.new()
		arm.radius = 0.055
		arm.height = 0.54
		var arm_node := _add_mesh(root, arm, Vector3(0.25 * side, 1.0, 0.22), body_mat)
		arm_node.rotation.x = 2.16

	var head := SphereMesh.new()
	head.radius = 0.17
	head.height = 0.34
	_add_mesh(root, head, Vector3(0, 1.42, 0), _mat(Color("f0c9a4"), 0.6))
	for side in [-1.0, 1.0]:
		var eye := SphereMesh.new()
		eye.radius = 0.025
		eye.height = 0.05
		_add_mesh(root, eye, Vector3(0.065 * side, 1.45, 0.15), _mat(Color("15151a")))
	if seat == SEAT_J:
		# Birrete del juez.
		var cap := CylinderMesh.new()
		cap.top_radius = 0.12
		cap.bottom_radius = 0.12
		cap.height = 0.12
		_add_mesh(root, cap, Vector3(0, 1.63, 0), _mat(Color("15151a")))
		_box(root, Vector3(0.42, 0.04, 0.42), Vector3(0, 1.7, 0), Color("15151a"))

	var plate := Label3D.new()
	plate.position = Vector3(0, 2.0, 0)
	plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	plate.fixed_size = true # mismo tamaño en pantalla sin importar la distancia
	plate.font_size = 40
	plate.pixel_size = 0.0009
	plate.outline_size = 10
	plate.outline_modulate = Color(0, 0, 0, 1)
	plate.text = ""
	root.add_child(plate)

	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = 0.62
	ring_mesh.bottom_radius = 0.62
	ring_mesh.height = 0.01
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color = Color(1.0, 0.85, 0.3, 0.5)
	var ring := _add_mesh(root, ring_mesh, Vector3(0, 0.02, 0), ring_mat)
	ring.visible = false

	return {"root": root, "body_mat": body_mat, "plate": plate, "ring": ring}


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.fov = 55.0
	_camera.near = 0.05
	_camera.far = 60.0
	add_child(_camera)
	_camera.current = true
	_hand_root = Node3D.new()
	_hand_root.position = HAND_OFFSET
	_camera.add_child(_hand_root)
