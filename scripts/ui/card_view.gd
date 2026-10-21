class_name CardView
extends PanelContainer
## Dibuja una CardData. Emite `pressed` al hacer clic si es interactiva y no está deshabilitada.
## Uso: var v = CardViewScene.instantiate(); v.setup(card); padre.add_child(v)

signal pressed(view: CardView)

## Color del borde según la categoría de la carta.
const FREE_COLOR := Color("3d7ab8") ## normal, la puntúa el juez (+5/-2/-1)
const DECISION_COLOR := Color("d98a2b") ## normal, el juez decide procede / no procede
const WILD_COLOR := Color("8a5fd0") ## comodín

var card: CardData
## false = solo se muestra (cartas ya jugadas sobre la mesa).
var interactive := true
## true = carta atenuada que no se puede elegir ahora.
var disabled := false
var selected := false:
	set(value):
		selected = value
		if is_node_ready():
			_refresh_style()

var _hover := false

@onready var _type_label: Label = %TypeLabel
@onready var _summary_label: Label = %SummaryLabel
@onready var _image: TextureRect = %Image
@onready var _text_label: Label = %TextLabel


func setup(c: CardData) -> void:
	card = c
	if is_node_ready():
		_refresh()


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	if not interactive:
		mouse_default_cursor_shape = Control.CURSOR_ARROW
	_refresh()


## Color de la categoría de una carta (sirve también para las tarjetas del menú y la guía).
static func color_of(c: CardData) -> Color:
	if c.is_wild():
		return WILD_COLOR
	return DECISION_COLOR if c.scoring == CardData.Scoring.DECISION else FREE_COLOR


## Clave de i18n del texto pequeño de arriba: qué tipo de carta es.
static func type_key(c: CardData) -> String:
	if c.is_wild():
		return "TYPE_WILD_REACTION" if c.timing == "none" else "TYPE_WILD"
	if c.scoring == CardData.Scoring.DECISION:
		return "TYPE_DECISION_INT" if c.is_interrupt() else "TYPE_DECISION"
	return "TYPE_FREE_INT" if c.is_interrupt() else "TYPE_FREE"


func _refresh() -> void:
	if card == null:
		return
	_type_label.text = tr(type_key(card))
	_type_label.add_theme_color_override("font_color", color_of(card))
	_summary_label.text = card.title
	_text_label.text = card.text
	_image.texture = card.image
	_image.visible = card.image != null
	_refresh_style()


func _refresh_style() -> void:
	if card == null:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("2a3346") if (_hover and interactive and not disabled) else Color("1f2532")
	sb.border_color = Color.WHITE if selected else color_of(card)
	sb.set_border_width_all(5 if selected else 3)
	sb.set_corner_radius_all(10)
	add_theme_stylebox_override("panel", sb)
	modulate = Color(1, 1, 1, 0.35) if disabled else Color.WHITE


func _gui_input(event: InputEvent) -> void:
	if not interactive or disabled:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(self)


func _on_mouse_entered() -> void:
	_hover = true
	_refresh_style()


func _on_mouse_exited() -> void:
	_hover = false
	_refresh_style()
