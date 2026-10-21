class_name PlayerPanel
extends PanelContainer
## Marcador de un jugador: nombre, rol de la ronda (juez / postura) y puntaje.

const JUDGE_COLOR := Color("e0b43a")
const NORMAL_COLOR := Color("3a4358")

var player: PlayerData

@onready var _name_label: Label = %NameLabel
@onready var _role_label: Label = %RoleLabel
@onready var _score_label: Label = %ScoreLabel


func setup(p: PlayerData) -> void:
	player = p
	refresh("", false)


func refresh(role_text: String, is_judge: bool) -> void:
	if player == null:
		return
	_name_label.text = player.display_name
	_role_label.text = role_text
	_role_label.add_theme_color_override("font_color", JUDGE_COLOR if is_judge else Color("aab4c8"))
	_score_label.text = str(player.score)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1f2532")
	sb.border_color = JUDGE_COLOR if is_judge else NORMAL_COLOR
	sb.set_border_width_all(3 if is_judge else 2)
	sb.set_corner_radius_all(8)
	add_theme_stylebox_override("panel", sb)
