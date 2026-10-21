extends Control
## Guía de juego por páginas. Los textos viven en data/i18n.json (claves HELP_1_TITLE, HELP_1_BODY,
## HELP_2_TITLE...) y los números salen de Config.markers(), así que nunca quedan desactualizados.
## Para agregar una página: súmale las dos claves en cada idioma y sube PAGES.

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const CardViewScene := preload("res://scenes/ui/card_view.tscn")
const PAGES := 6
## Página que muestra una carta de ejemplo de cada categoría.
const CARDS_PAGE := 4
## Ids de data/cards.json que se muestran de ejemplo: una de puntaje libre, una de decisión y un comodín.
const SAMPLE_IDS := ["argumentar", "incriminacion", "soborno"]

@onready var _title: Label = %PageTitle
@onready var _body: Label = %PageBody
@onready var _cards_row: HBoxContainer = %CardsRow
@onready var _prev: Button = %PrevButton
@onready var _next: Button = %NextButton
@onready var _counter: Label = %CounterLabel
@onready var _back: Button = %BackButton

var _page := 1


func _ready() -> void:
	_build_sample_cards()
	_prev.pressed.connect(_change_page.bind(-1))
	_next.pressed.connect(_change_page.bind(1))
	_back.pressed.connect(_go_back)
	_show_page()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_back()
	elif event.is_action_pressed("ui_left"):
		_change_page(-1)
	elif event.is_action_pressed("ui_right"):
		_change_page(1)


func _change_page(step: int) -> void:
	_page = clampi(_page + step, 1, PAGES)
	_show_page()


func _show_page() -> void:
	_title.text = tr("HELP_%d_TITLE" % _page)
	_body.text = tr("HELP_%d_BODY" % _page).format(_numbers())
	_cards_row.visible = _page == CARDS_PAGE
	_counter.text = "%d / %d" % [_page, PAGES]
	_prev.disabled = _page == 1
	_next.disabled = _page == PAGES


## Números que el texto de la guía puede usar entre llaves, por ejemplo {turn_seconds}
## (la lista completa está en Config.markers()).
func _numbers() -> Dictionary:
	return Config.markers()


## Una carta real de cada categoría, tomada de data/cards.json.
func _build_sample_cards() -> void:
	var catalog := CardCatalog.load_default()
	for id in SAMPLE_IDS:
		var card := catalog.by_id(id)
		if card == null:
			continue
		var view: CardView = CardViewScene.instantiate()
		view.interactive = false
		view.setup(card)
		_cards_row.add_child(view)


func _go_back() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
