class_name Card3D
extends Node3D
## Carta física en 3D. Su cara es la CardView 2D dibujada en un SubViewport, así el diseño de la
## carta se define una sola vez (en card_view.tscn) y sirve para 2D y 3D.
##
## Orientación local: la cara mira hacia +Z, el ancho va en X y el alto en Y. Para dejarla boca
## arriba sobre la mesa se gira -90° en X; en la mano (hija de la cámara) queda sin girar.
##
## Estructura:  Card3D -> _lifter (elevación) -> _flipper (volteo) -> cara / reverso / marco

const SIZE := Vector2(0.5, 0.7)
const FRAME_PAD := 0.05
const CardViewScene := preload("res://scenes/ui/card_view.tscn")
const HOVER_COLOR := Color("ffe8a3")
const FOCUS_COLOR := Color("ffd166")
const SELECT_COLOR := Color("ffffff")

static var _back_texture: ImageTexture

var card: CardData
## Hacia dónde se eleva la carta al resaltarla (mesa: hacia arriba; mano: arriba y hacia la cámara).
var lift_dir := Vector3(0, 0, 1)
## false = solo se ve (cartas sobre la mesa).
var interactive := true

var _hovered := false
var _selected := false
var _focused := false
var _disabled := false
var _dimmed := false
var _face_up := true

var _lifter: Node3D
var _flipper: Node3D
var _front_mat: StandardMaterial3D
var _back_mat: StandardMaterial3D
var _frame: MeshInstance3D
var _frame_mat: StandardMaterial3D
var _viewport: SubViewport
var _lift_tween: Tween
var _flip_tween: Tween
var _flip_arc_tween: Tween


static func create(c: CardData, face_up := true) -> Card3D:
	var n := Card3D.new()
	n.card = c
	n._face_up = face_up
	n._build()
	return n


func _build() -> void:
	# Cara: la CardView 2D renderizada en un SubViewport (a doble resolución para que se lea bien).
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(320, 430)
	_viewport.size_2d_override = Vector2i(160, 215)
	_viewport.size_2d_override_stretch = true
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var view: CardView = CardViewScene.instantiate()
	view.interactive = false
	view.setup(card)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(view)

	_lifter = Node3D.new()
	add_child(_lifter)
	_flipper = Node3D.new()
	_flipper.rotation.y = 0.0 if _face_up else PI
	_lifter.add_child(_flipper)

	_front_mat = _make_card_material(_viewport.get_texture())
	_back_mat = _make_card_material(_get_back_texture())
	_flipper.add_child(_make_quad(SIZE, _front_mat, 0.0, false))
	_flipper.add_child(_make_quad(SIZE, _back_mat, -0.002, true))

	_frame_mat = StandardMaterial3D.new()
	_frame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_frame_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_frame = _make_quad(SIZE + Vector2(FRAME_PAD, FRAME_PAD), _frame_mat, -0.006, false)
	_frame.visible = false
	_flipper.add_child(_frame)

	# Tras unos cuadros la textura ya está dibujada: se deja de redibujar para ahorrar GPU.
	var timer := Timer.new()
	timer.wait_time = 0.2
	timer.one_shot = true
	timer.autostart = true # arranca al entrar al árbol
	timer.timeout.connect(_freeze_viewport)
	add_child(timer)


func _freeze_viewport() -> void:
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _make_card_material(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	return m


func _make_quad(size: Vector2, mat: Material, z: float, flipped: bool) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.position.z = z
	if flipped:
		mi.rotation.y = PI
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Reverso compartido por todas las cartas: se dibuja una sola vez.
static func _get_back_texture() -> ImageTexture:
	if _back_texture != null:
		return _back_texture
	var k := 1.5
	var w := int(160 * k)
	var h := int(215 * k)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var navy := Color("1d2740")
	var blue := Color("3d7ab8")
	var light := Color("8fb8e6")
	var half := Vector2(w, h) / 2.0
	var radius := 10.0 * k
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5) - half
			var q := p.abs() - (half - Vector2(radius, radius))
			var d := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius
			var c := Color(0, 0, 0, 0)
			if d <= 0.0:
				c = navy
				if d > -6.0 * k:
					c = blue
				elif d > -11.0 * k and d < -9.0 * k:
					c = light
				var e := p.length()
				if e < 30.0 * k and e > 26.0 * k:
					c = light
				elif e < 12.0 * k:
					c = blue
			img.set_pixel(x, y, c)
	_back_texture = ImageTexture.create_from_image(img)
	return _back_texture


# ---------------------------------------------------------------------------
# Estado visual
# ---------------------------------------------------------------------------

func set_hovered(v: bool) -> void:
	_hovered = v
	_refresh()


func set_selected(v: bool) -> void:
	_selected = v
	_refresh()


func set_focused(v: bool) -> void:
	_focused = v
	_refresh()


func set_disabled(v: bool) -> void:
	_disabled = v
	_refresh()


func set_dimmed(v: bool) -> void:
	_dimmed = v
	_refresh()


func is_disabled() -> bool:
	return _disabled


func is_face_up() -> bool:
	return _face_up


func set_face_up(up: bool, animate := true) -> void:
	if up == _face_up:
		return
	_face_up = up
	var target := 0.0 if up else PI
	if _flip_tween != null:
		_flip_tween.kill()
	if _flip_arc_tween != null:
		_flip_arc_tween.kill()
	if not animate or not is_inside_tree():
		_flipper.rotation.y = target
		_flipper.position.z = 0.0
		return
	_flip_tween = create_tween()
	_flip_tween.tween_property(_flipper, "rotation:y", target, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# La carta sube un poco mientras gira y vuelve a bajar.
	_flip_arc_tween = create_tween()
	_flip_arc_tween.tween_property(_flipper, "position:z", 0.22, 0.2).set_ease(Tween.EASE_OUT)
	_flip_arc_tween.tween_property(_flipper, "position:z", 0.0, 0.25).set_ease(Tween.EASE_IN)


func _refresh() -> void:
	var can_hover := interactive and not _disabled
	var frame_color := Color(0, 0, 0, 0)
	if _selected:
		frame_color = SELECT_COLOR
	elif _focused:
		frame_color = FOCUS_COLOR
	elif _hovered and can_hover:
		frame_color = HOVER_COLOR
	_frame.visible = frame_color.a > 0.0
	_frame_mat.albedo_color = frame_color

	var shade := 1.0
	if _disabled:
		shade = 0.35
	elif _dimmed:
		shade = 0.55
	var tint := Color(shade, shade, shade, 1.0)
	_front_mat.albedo_color = tint
	_back_mat.albedo_color = tint

	var lift := 0.0
	if _selected:
		lift = 0.22
	elif _hovered and can_hover:
		lift = 0.12
	elif _focused:
		lift = 0.10
	if _lift_tween != null:
		_lift_tween.kill()
	if is_inside_tree():
		_lift_tween = create_tween()
		_lift_tween.tween_property(_lifter, "position", lift_dir * lift, 0.12).set_ease(Tween.EASE_OUT)
	else:
		_lifter.position = lift_dir * lift


## Distancia (en unidades del rayo) a la que el rayo toca la carta, o -1 si no la toca.
func ray_hit(origin: Vector3, dir: Vector3) -> float:
	var inv := global_transform.affine_inverse()
	var o := inv * origin
	var d := inv.basis * dir
	if absf(d.z) < 0.000001:
		return -1.0
	var t := -o.z / d.z
	if t < 0.0:
		return -1.0
	var p := o + d * t
	if absf(p.x) <= SIZE.x / 2.0 and absf(p.y) <= SIZE.y / 2.0:
		return t
	return -1.0
