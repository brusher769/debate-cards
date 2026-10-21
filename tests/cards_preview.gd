extends Node
## Dibuja las 24 cartas (13 normales + 11 comodines) en español e inglés y comprueba que ningún
## texto quede recortado con «…» dentro de la carta. Con SHOT_DIR guarda una imagen de cada idioma.
## Necesita render real (no sirve con --headless):
##   SHOT_DIR=/ruta godot --path . res://tests/cards_preview.tscn
## Imprime "CARTAS OK" si todas caben. Úsala cada vez que edites textos de data/cards.json.

const CardViewScene := preload("res://scenes/ui/card_view.tscn")
const COLUMNS := 8

var _problems := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Settings.reset_to_defaults(false)
	var dir := OS.get_environment("SHOT_DIR")
	for lang in Settings.LANGUAGES:
		Settings.set_language(lang)
		var catalog := CardCatalog.load_default()
		var root := Control.new()
		add_child(root)
		var bg := ColorRect.new()
		bg.color = Color("0b0e16")
		bg.size = Vector2(1300, 720)
		root.add_child(bg)
		var grid := GridContainer.new()
		grid.columns = COLUMNS
		grid.position = Vector2(12, 12)
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		root.add_child(grid)
		var views: Array[CardView] = []
		for c: CardData in catalog.normals + catalog.wilds:
			var view: CardView = CardViewScene.instantiate()
			view.interactive = false
			view.setup(c)
			grid.add_child(view)
			views.append(view)
		for i in 4:
			await get_tree().process_frame
		for view in views:
			_check_label(view.get_node("%TextLabel"), view.card, lang)
			_check_label(view.get_node("%SummaryLabel"), view.card, lang)
		if dir != "":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/cartas_%s.png" % [dir, lang])
		root.queue_free()
		await get_tree().process_frame
	print("CARTAS OK" if _problems == 0 else "CARTAS CON TEXTO RECORTADO: %d" % _problems)
	get_tree().quit(1 if _problems > 0 else 0)


func _check_label(label: Label, card: CardData, lang: String) -> void:
	if label.get_visible_line_count() < label.get_line_count():
		_problems += 1
		printerr("FALLO: el texto de la carta «%s» (%s) no cabe: %d de %d líneas visibles. Acórtalo en data/cards.json." % [
			card.id, lang, label.get_visible_line_count(), label.get_line_count()])
