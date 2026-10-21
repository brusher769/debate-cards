extends Node3D
## Mesa de juego: une la escena 3D (Stage3D) con el HUD 2D (marcador, instrucciones, panel del
## juez, botones). No tiene reglas propias: dibuja el estado de DebateEngine y le manda las
## acciones de los jugadores. Las reglas viven en scripts/core/debate_engine.gd.
##
## Como los 3 juegan en la misma pantalla, antes de mostrar una mano (o una decisión privada del
## juez) aparece una pantalla de "pásale el control a X" (el overlay) para que nadie vea las cartas
## de otro. Al elegir, la cámara se pone en el asiento de quien juega (primera persona).
## Mientras el overlay está visible el reloj del motor se detiene (el tiempo de pasar el control
## no cuenta contra nadie).
##
## En línea (GameState.is_online()) cada jugador tiene su propia pantalla: no hay relevo, el motor
## es el espejo de Net (que refleja lo que manda el servidor) y las acciones van al servidor. Cada
## uno ve solo lo suyo: su mano si es su turno, y un aviso de a quién se espera si no lo es.

const PlayerPanelScene := preload("res://scenes/ui/player_panel.tscn")
const MENU_SCENE := "res://scenes/main_menu.tscn"
const TIME_UP_COLOR := Color("e5534b")
const LOG_LINES := 4
const Phase := DebateEngine.Phase

## Para qué está mostrándose la mano de un jugador.
enum Ctx { NONE, PLAY, RESPOND, INTERRUPT }

@onready var _stage: Stage3D = %Stage
@onready var _round_label: Label = %RoundLabel
@onready var _topic_label: Label = %TopicLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _players_row: HBoxContainer = %PlayersRow
@onready var _instruction: Label = %InstructionLabel
@onready var _center_panel: PanelContainer = %CenterPanel
@onready var _judge_panel: VBoxContainer = %JudgePanel
@onready var _info: RichTextLabel = %ResultsLabel
@onready var _hint: Label = %HintLabel
@onready var _skip_button: Button = %SkipButton
@onready var _judge_end_button: Button = %JudgeEndButton
@onready var _interrupt_button: Button = %InterruptButton
@onready var _swap_button: Button = %SwapButton
@onready var _action_button: Button = %ActionButton
@onready var _overlay: ColorRect = %Overlay
@onready var _overlay_title: Label = %OverlayTitle
@onready var _overlay_body: Label = %OverlayBody
@onready var _overlay_button: Button = %OverlayButton
@onready var _overlay_button2: Button = %OverlayButton2
@onready var _agree_button: Button = %AgreeButton
@onready var _disagree_button: Button = %DisagreeButton

var _engine: DebateEngine
## En línea: true, y el jugador que está frente a esta pantalla.
var _online := false
var _me: PlayerData = null
var _panels := {} # PlayerData -> PlayerPanel
var _selected_card: CardData = null
var _ctx := Ctx.NONE
## Jugador cuya mano se está mostrando ahora (null = ninguna) y de qué turno.
var _hand_owner: PlayerData = null
var _hand_turn := -1
## true mientras el rival elige una carta para interrumpir (el reloj queda en pausa).
var _interrupting := false
## Pregunta cuya pantalla de presentación ya se vio (antes de elegir postura).
var _topic_seen := ""
var _shared_stance := "" ## postura que eligieron los dos cuando no hubo debate
var _log: Array[String] = []
var _notes := {} # índice de jugador -> Array[String]: avisos privados para su próxima mano
var _action := Callable()
var _overlay_action := Callable()
var _param_row: HBoxContainer
var _amount: SpinBox
var _extra_check: CheckButton
var _label_tick := 0.0


func _ready() -> void:
	_action_button.pressed.connect(_on_action_pressed)
	_skip_button.pressed.connect(_on_skip_pressed)
	_interrupt_button.pressed.connect(_on_interrupt_pressed)
	_swap_button.pressed.connect(_on_swap_pressed)
	_judge_end_button.pressed.connect(_on_judge_end_pressed)
	_overlay_button.pressed.connect(_on_overlay_pressed)
	_overlay_button2.pressed.connect(_go_to_menu)
	_agree_button.pressed.connect(_on_stance_chosen.bind(true))
	_disagree_button.pressed.connect(_on_stance_chosen.bind(false))
	_stage.card_clicked.connect(_on_card_clicked)
	_build_param_row()

	# Si se abre esta escena sola desde el editor (F6) no hay partida: se crea una de prueba
	# para poder ver y acomodar el diseño. Al jugar desde el menú, la partida ya existe.
	if GameState.engine == null:
		var names: Array[String] = []
		for i in 3:
			names.append(tr("DEFAULT_PLAYER_NAME") % (i + 1))
		GameState.new_room(names, "normal")
		GameState.start_game()

	_engine = GameState.engine
	_online = GameState.is_online()
	if _online:
		_me = _engine.player_by_index(GameState.viewer_index)
		_setup_online()
	for p in GameState.players:
		var panel: PlayerPanel = PlayerPanelScene.instantiate()
		_players_row.add_child(panel)
		panel.setup(p)
		_panels[p] = panel
		_notes[p.index] = []
	_engine.changed.connect(_sync)
	_engine.take_events()
	_sync()


func _process(delta: float) -> void:
	if _engine == null or _engine.phase == Phase.OVER:
		return
	# En línea el reloj lo corre Net (motor espejo); aquí solo en una pantalla compartida.
	if not _online and not _overlay.visible and not _interrupting:
		_engine.tick(delta)
	_label_tick -= delta
	if _label_tick <= 0.0:
		_label_tick = 0.1
		_update_labels()


# ---------------------------------------------------------------------------
# Dibujo según la fase del motor
# ---------------------------------------------------------------------------

func _sync() -> void:
	if _engine == null:
		return
	_consume_events()
	if _engine.phase != Phase.PLAY:
		_hand_owner = null
	_reset_hud()
	if _engine.phase != Phase.STANCE:
		_stage.set_roles(_engine.judge, _engine.debaters, _stances_text())
	_refresh_scoreboard()
	_topic_label.text = "«%s»" % _topic()
	_hint.text = ""
	match _engine.phase:
		Phase.STANCE:
			_show_stance()
		Phase.STANCE_RESULT:
			_show_stance_result()
		Phase.PLAY:
			_show_play()
		Phase.RESPONSE:
			_show_response()
		Phase.BRIBE:
			_show_bribe()
		Phase.APPEAL:
			_show_appeal()
		Phase.SPEECH:
			_show_speech()
		Phase.ANSWER:
			_show_answer()
		Phase.RESOLVE:
			_show_resolve()
		Phase.OVER:
			_show_final()
	_apply_log_to_hint()
	_hint.get_parent().visible = _hint.text != "" # sin pista no se muestra la barra vacía
	_update_labels()


func _show_stance() -> void:
	_stage.clear_table()
	if _online:
		_show_stance_online()
		return
	if _topic_seen != _engine.topic:
		# Presentación de la pregunta: la ven los tres, incluido el juez.
		_stage.set_roles(_engine.judge, _engine.debaters, {})
		_stage.set_view(&"overview")
		var text := tr("STANCE_TOPIC_INSTR") % _engine.judge.display_name
		if _engine.topics_rejected > 0:
			text = tr("TOPIC_REJECTED") % _shared_stance + "\n" + text
		_instruction.text = text
		_hint.text = tr("STANCE_TOPIC_HINT")
		_set_action(tr("BTN_CHOOSE_STANCE"), _ack_topic)
		return
	var picker := _next_stance_picker()
	_stage.set_roles(_engine.judge, _engine.debaters, {})
	_stage.set_view(&"overview")
	_overlay_title.text = tr("HANDOFF_TITLE") % picker.display_name
	_overlay_body.text = tr("STANCE_HANDOFF_BODY") % [picker.display_name, _topic()]
	_overlay_button.text = tr("STANCE_HANDOFF_BUTTON") % picker.display_name
	_overlay_action = _reveal_stance_choice.bind(picker)
	_overlay.show()
	_instruction.text = tr("TURN_OF") % picker.display_name
	_hint.text = tr("STANCE_PICK_HINT")
	_action_button.hide()


## En línea: cada debatiente elige en su pantalla; los demás esperan.
func _show_stance_online() -> void:
	_stage.set_roles(_engine.judge, _engine.debaters, {})
	_stage.set_view(&"overview")
	var text := tr("STANCE_TOPIC_INSTR") % _engine.judge.display_name
	if _engine.topics_rejected > 0:
		text = tr("TOPIC_REJECTED") % _shared_stance + "\n" + text
	_instruction.text = text
	_action_button.hide()
	if _me != _engine.judge and not _engine.stance_choices.has(_me):
		_stage.set_active_player(_me)
		_hint.text = tr("STANCE_PICK_HINT")
		_agree_button.show()
		_disagree_button.show()
	elif _me != _engine.judge:
		_hint.text = tr("ONLINE_WAIT_OTHER_STANCE")
	else:
		_hint.text = tr("ONLINE_WAIT_STANCES")


func _ack_topic() -> void:
	_topic_seen = _engine.topic
	_sync()


func _next_stance_picker() -> PlayerData:
	for p in _engine.debaters:
		if not _engine.stance_choices.has(p):
			return p
	return _engine.debaters[0]


func _reveal_stance_choice(picker: PlayerData) -> void:
	_overlay.hide()
	_stage.set_active_player(picker)
	_instruction.text = tr("STANCE_PICK_INSTR") % picker.display_name
	_agree_button.show()
	_disagree_button.show()


func _on_stance_chosen(agree: bool) -> void:
	if _online:
		_agree_button.hide() # ya elegiste: se espera al servidor
		_disagree_button.hide()
		_send("stance", _me, {"agree": agree})
	else:
		_send("stance", _next_stance_picker(), {"agree": agree})


## Resultado de las dos elecciones: hay debate (posturas opuestas) o sale otra pregunta.
func _show_stance_result() -> void:
	_stage.clear_table()
	_stage.set_view(&"overview")
	if _engine.stances_opposite:
		var text := tr("STANCES_ASSIGNED_INSTR") if _engine.mode == "indefendible" else tr("STANCES_OK_INSTR")
		for p in _engine.debaters:
			text += "\n" + tr("DEFENDS") % [p.display_name, _stance_text(p)]
		_instruction.text = text
		_hint.text = tr("STANCES_OK_HINT")
		_set_action(tr("BTN_START_DEBATE"), _send.bind("continue", _me if _online else _engine.judge))
	else:
		_shared_stance = _stance_text(_engine.debaters[0])
		_instruction.text = tr("STANCES_CLASH_INSTR") % _shared_stance
		_set_action(tr("BTN_NEW_TOPIC"), _send.bind("continue", _me if _online else _engine.judge))


## Turno de un debatiente: pantalla de relevo y luego su mano.
func _show_play() -> void:
	var p := _engine.active
	_sync_table()
	_stage.set_view(&"table")
	if _online:
		if p == _me:
			_reveal_hand(p, Ctx.PLAY)
		else:
			_wait_for(tr("ONLINE_WAIT_TURN") % p.display_name)
		return
	if _hand_owner == p and _hand_turn == _engine.turn_index:
		_reveal_hand(p, Ctx.PLAY) # sigue siendo la misma mano (por ejemplo tras cambiar el comodín)
		return
	_overlay_title.text = tr("HANDOFF_TITLE") % p.display_name
	_overlay_body.text = tr("PLAY_HANDOFF_BODY") % [p.display_name, _stance_text(p), _engine.turn_index]
	_overlay_button.text = tr("HANDOFF_BUTTON") % p.display_name
	_overlay_action = _reveal_play.bind(p)
	_overlay.show()
	_instruction.text = tr("TURN_OF") % p.display_name
	_hint.text = tr("HINT_PICK")
	_action_button.hide()


func _reveal_play(p: PlayerData) -> void:
	_hand_owner = p
	_hand_turn = _engine.turn_index
	_reveal_hand(p, Ctx.PLAY)


## Muestra la mano (cartas normales y comodines) de `p` en primera persona.
func _reveal_hand(p: PlayerData, ctx: Ctx) -> void:
	_overlay.hide()
	_ctx = ctx
	_hand_owner = p
	_stage.set_active_player(p)
	var cards: Array = []
	cards.append_array(p.hand)
	cards.append_array(p.wilds)
	_stage.show_hand(p, cards, _playable_for(p, ctx))
	var text := ""
	match ctx:
		Ctx.PLAY:
			text = tr("PLAY_INSTR") % [p.display_name, p.coins]
			if _engine.can_swap_wild(p):
				_swap_button.text = tr("BTN_SWAP_WILD") % Config.swap_cost
				_swap_button.show()
			_set_action(tr("BTN_PLAY_CARD"), _confirm_pick, false)
			_hint.text = tr("HINT_PICK")
		Ctx.RESPOND:
			var wild_owner := _engine.pending_wild_owner()
			text = tr("RESPOND_INSTR") % [p.display_name, wild_owner.display_name, _engine.pending_wild().title]
			_skip_button.text = tr("BTN_NO_RESPOND")
			_skip_button.show()
			_set_action(tr("BTN_RESPOND"), _confirm_pick, false)
		Ctx.INTERRUPT:
			text = tr("INTERRUPT_INSTR") % p.display_name if not _engine.interrupt_cards(p).is_empty() else tr("INTERRUPT_NONE") % p.display_name
			_skip_button.text = tr("BTN_CANCEL")
			_skip_button.show()
			_set_action(tr("BTN_PLAY_CARD"), _confirm_pick, false)
	var notes := _take_notes(p)
	if notes != "":
		text += "\n" + notes
	_instruction.text = text


func _playable_for(p: PlayerData, ctx: Ctx) -> Array:
	var out: Array = []
	match ctx:
		Ctx.PLAY:
			out.append_array(_engine.playable_cards(p))
			for w in p.wilds:
				# Se comprueba con datos de ejemplo válidos; el motor revisa los reales al jugarla.
				if _engine.check_wild(p, w, {"amount": 1}) == "":
					out.append(w)
		Ctx.RESPOND:
			out.append_array(_engine.response_options(p))
		Ctx.INTERRUPT:
			out.append_array(_engine.interrupt_cards(p))
	return out


## Un comodín ofrece a un rival la posibilidad de responder: relevo al que responde.
func _show_response() -> void:
	var wild_owner := _engine.pending_wild_owner()
	var responder := _engine.other(wild_owner)
	var w := _engine.pending_wild()
	_sync_table()
	_stage.set_view(&"table")
	_stage.focus_cards([w], wild_owner)
	if _online:
		_instruction.text = tr("WILD_PLAYED_INSTR") % [wild_owner.display_name, w.title]
		if _me == responder:
			_reveal_hand(_me, Ctx.RESPOND)
		else:
			_wait_for(tr("ONLINE_WAIT_RESPONSE") % responder.display_name)
		return
	_overlay_title.text = tr("HANDOFF_TITLE") % responder.display_name
	_overlay_body.text = tr("RESPONSE_HANDOFF_BODY") % [wild_owner.display_name, w.title, Config.response_seconds]
	_overlay_button.text = tr("HANDOFF_BUTTON") % responder.display_name
	_overlay_action = _reveal_hand.bind(responder, Ctx.RESPOND)
	_overlay.show()
	_instruction.text = tr("WILD_PLAYED_INSTR") % [wild_owner.display_name, w.title]
	_hint.text = tr("RESPONSE_HINT") % responder.display_name
	_action_button.hide()


## El juez decide un Soborno en privado: nadie más debe mirar.
func _show_bribe() -> void:
	var judge := _engine.judge
	_sync_table()
	_stage.set_view(&"judge")
	if _online:
		_instruction.text = tr("BRIBE_PUBLIC_INSTR")
		if _me == judge:
			_reveal_bribe()
		else:
			_wait_for(tr("ONLINE_WAIT_JUDGE"))
		return
	_overlay_title.text = tr("HANDOFF_TITLE") % judge.display_name
	_overlay_body.text = tr("BRIBE_HANDOFF_BODY") % judge.display_name
	_overlay_button.text = tr("BRIBE_HANDOFF_BUTTON") % judge.display_name
	_overlay_action = _reveal_bribe
	_overlay.show()
	_instruction.text = tr("BRIBE_PUBLIC_INSTR")
	_action_button.hide()


func _reveal_bribe() -> void:
	_overlay.hide()
	var b := _engine.pending_bribe()
	var who: PlayerData = b["player"]
	var lose := int((b["card"] as CardData).params.get("lose_cards", 2))
	_clear(_judge_panel)
	_add_text(tr("BRIBE_DECISION_INSTR") % [who.display_name, b["amount"], lose, absi(Config.bribe_max_penalty)])
	var row := _button_row()
	row.add_child(_button(tr("BTN_ACCEPT_BRIBE"), _send.bind("bribe_decision", _engine.judge, {"accept": true})))
	row.add_child(_button(tr("BTN_REJECT_BRIBE"), _send.bind("bribe_decision", _engine.judge, {"accept": false})))
	_judge_panel.add_child(row)
	_center_panel.show()
	_judge_panel.show()
	_action_button.hide()


func _show_appeal() -> void:
	var u := _engine.current_unit()
	var who: PlayerData = u["player"]
	_sync_table()
	_stage.set_view(&"judge")
	_stage.set_active_player(_engine.judge)
	_instruction.text = tr("APPEAL_INSTR") % [who.display_name, _engine.judge.display_name]
	if _online and _me != _engine.judge:
		_wait_for(tr("ONLINE_WAIT_JUDGE"))
		return
	_clear(_judge_panel)
	_add_text(tr("APPEAL_QUESTION") % who.display_name)
	var row := _button_row()
	for s in Config.appeal_options:
		row.add_child(_button("+%d s" % s, _send.bind("appeal_time", _engine.judge, {"seconds": s})))
	_judge_panel.add_child(row)
	_center_panel.show()
	_judge_panel.show()
	_action_button.hide()


func _show_speech() -> void:
	var u := _engine.current_unit()
	var p: PlayerData = u["player"]
	var card: CardData = u["card"]
	_sync_table()
	_stage.focus_cards([card], p)
	_stage.set_active_player(p)
	_stage.set_view(&"table")
	if u["floor"]:
		_instruction.text = tr("SPEECH_FLOOR") % p.display_name
	else:
		_instruction.text = tr("SPEECH_FMT") % [p.display_name, card.title]
	_hint.text = tr("SPEECH_HINT") % _engine.other(p).display_name
	if _online:
		# Solo quien habla puede terminar; solo su rival puede interrumpir.
		if p == _me:
			_set_action(tr("BTN_END_SPEECH"), _send.bind("end_speech", _me))
		else:
			_action_button.hide()
		_interrupt_button.text = tr("BTN_INTERRUPT_ONLINE")
		_interrupt_button.visible = _me != _engine.judge and _me != p
		return
	_set_action(tr("BTN_END_SPEECH"), _send.bind("end_speech", p))
	_interrupt_button.text = tr("BTN_INTERRUPT") % _engine.other(p).display_name
	_interrupt_button.show()


func _show_answer() -> void:
	var u := _engine.current_unit()
	var asker: PlayerData = u["player"]
	var responder := _engine.other(asker)
	_sync_table()
	_stage.focus_cards([u["card"]], asker)
	_stage.set_active_player(responder)
	_stage.set_view(&"table")
	_instruction.text = tr("ANSWER_INSTR") % [responder.display_name, asker.display_name]
	if _online:
		if responder == _me:
			_set_action(tr("BTN_END_ANSWER"), _send.bind("end_answer", _me))
		else:
			_action_button.hide()
		return
	_set_action(tr("BTN_END_ANSWER"), _send.bind("end_answer", responder))


func _show_resolve() -> void:
	var u := _engine.current_unit()
	var who: PlayerData = u["player"]
	var card: CardData = u["card"]
	var judge := _engine.judge
	_sync_table()
	_stage.focus_cards([card], who)
	_stage.set_active_player(judge)
	_stage.set_view(&"judge")
	if _online and _me != judge:
		var key := "RESOLVE_DECISION" if card.scoring == CardData.Scoring.DECISION else "RESOLVE_FREE"
		_instruction.text = tr(key) % [judge.display_name, who.display_name, card.title]
		_wait_for(tr("ONLINE_WAIT_JUDGE"))
		return
	_clear(_judge_panel)
	var row := _button_row()
	if card.scoring == CardData.Scoring.DECISION:
		var rival := _engine.other(who)
		if u["objection"]:
			_instruction.text = tr("RESOLVE_OBJECTION") % [who.display_name, rival.display_name]
		else:
			_instruction.text = tr("RESOLVE_DECISION") % [judge.display_name, who.display_name, card.title]
		_add_text(tr("RESOLVE_IF_UPHELD") % _effects_text(who, rival, card.pass_self, card.pass_rival)
			+ "\n" + tr("RESOLVE_IF_OVERRULED") % _effects_text(who, rival, card.fail_self, card.fail_rival))
		row.add_child(_button(tr("BTN_UPHELD"), _send.bind("decide", judge, {"passes": true})))
		row.add_child(_button(tr("BTN_OVERRULED"), _send.bind("decide", judge, {"passes": false})))
	else:
		_instruction.text = tr("RESOLVE_FREE") % [judge.display_name, who.display_name, card.title]
		if u["interrupted"]:
			_add_text(tr("RESOLVE_INTERRUPTED"))
		for pts in Config.judge_points:
			row.add_child(_button("%+d" % pts, _send.bind("score", judge, {"points": pts})))
	_judge_panel.add_child(row)
	_center_panel.show()
	_judge_panel.show()
	_action_button.hide()


func _show_final() -> void:
	_stage.gavel()
	_stage.set_view(&"overview")
	_sync_table()
	var r := _engine.result
	var ranking := _engine.debaters.duplicate()
	ranking.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.score > b.score)
	var lines := ""
	var pos := 1
	for p: PlayerData in ranking:
		lines += tr("FINAL_LINE") % [pos, p.display_name, p.score] + "\n"
		pos += 1
	var head := tr("FINAL_TIE") if r["tie"] else tr("FINAL_WINNER") % (r["winner"] as PlayerData).display_name
	var why := tr("OVER_" + str(r["reason"]).to_upper())
	if r["judge_jailed"]:
		why += "\n" + tr("OVER_JAILED") % _engine.judge.display_name
	_overlay_title.text = tr("FINAL_TITLE")
	_overlay_body.text = "%s\n%s\n\n%s\n%s" % [head, why, lines.strip_edges(), tr("FINAL_JUDGE") % _engine.judge.display_name]
	_overlay_button.text = tr("BTN_ANOTHER_GAME")
	_overlay_action = _new_game
	_overlay_button2.text = tr("BTN_BACK_MENU")
	_overlay_button2.show()
	if _online and not Net.is_host():
		_overlay_button.hide() # solo el anfitrión empieza otra partida
		_overlay_body.text += "\n\n" + tr("ONLINE_WAIT_HOST")
	else:
		_overlay_button.show()
	_overlay.show()
	_action_button.hide()


# ---------------------------------------------------------------------------
# Acciones de los jugadores
# ---------------------------------------------------------------------------

## Manda una acción al motor. Si la rechaza, muestra el motivo. Devuelve true si se aceptó.
func _send(type: String, p: PlayerData, extra := {}) -> bool:
	var action := {"type": type, "player": p.index}
	action.merge(extra)
	if _online:
		# En línea la acción va al servidor, que pone tu lugar y la valida; si la rechaza, avisa por Net.
		Net.send_action(action)
		return true
	var r := _engine.apply(action)
	if not r["ok"]:
		_hint.text = "! " + str(r["error"])
		_hint.get_parent().show()
	return r["ok"]


func _on_card_clicked(card: CardData) -> void:
	_selected_card = card
	_stage.select_card(card)
	_action_button.disabled = false
	match _ctx:
		Ctx.RESPOND:
			_action_button.text = tr("BTN_RESPOND_WITH") % card.title
		_:
			_action_button.text = tr("BTN_PLAY_WILD") % card.title if card.is_wild() else tr("BTN_PLAY_CARD_NAMED") % card.title
	_param_row.hide()
	if _ctx != Ctx.RESPOND and card.is_wild():
		_show_wild_params(card)


func _confirm_pick() -> void:
	if _selected_card == null or _hand_owner == null:
		return
	var card := _selected_card
	var p := _hand_owner
	var extra := {"card": card.id}
	var ok := false
	match _ctx:
		Ctx.RESPOND:
			ok = _send("respond", p, extra)
		Ctx.PLAY, Ctx.INTERRUPT:
			if card.is_wild():
				extra.merge(_wild_params(card))
				ok = _send("play_wild", p, extra)
			else:
				ok = _send("play_card", p, extra)
	if ok:
		_interrupting = false


func _on_skip_pressed() -> void:
	match _ctx:
		Ctx.RESPOND:
			if _hand_owner != null:
				_send("pass_response", _hand_owner)
		Ctx.INTERRUPT:
			_interrupting = false
			_sync()


func _on_interrupt_pressed() -> void:
	var speaker := _engine.speaker()
	if speaker == null:
		return
	var rival := _engine.other(speaker)
	if _online:
		_reveal_hand(_me, Ctx.INTERRUPT) # cada quien en su pantalla: no hay relevo ni pausa
		return
	_interrupting = true
	_overlay_title.text = tr("HANDOFF_TITLE") % rival.display_name
	_overlay_body.text = tr("INTERRUPT_HANDOFF_BODY") % [rival.display_name, speaker.display_name, rival.display_name]
	_overlay_button.text = tr("HANDOFF_BUTTON") % rival.display_name
	_overlay_action = _reveal_hand.bind(rival, Ctx.INTERRUPT)
	_overlay.show()


func _on_swap_pressed() -> void:
	if _hand_owner != null:
		_send("swap_wild", _hand_owner)


func _on_judge_end_pressed() -> void:
	_send("judge_end", _engine.judge)


func _new_game() -> void:
	if _online:
		Net.start_game() # el servidor reparte roles nuevos y llega otra foto
		return
	GameState.start_game()
	get_tree().reload_current_scene()


func _go_to_menu() -> void:
	if _online:
		Net.leave_room()
		Net.shutdown()
		Voice.set_mic(false)
		GameState.viewer_index = -1
	get_tree().change_scene_to_file(MENU_SCENE)


func _on_action_pressed() -> void:
	if _action.is_valid():
		_action.call()


func _on_overlay_pressed() -> void:
	if _overlay_action.is_valid():
		_overlay_action.call()


# ---------------------------------------------------------------------------
# Partida en línea
# ---------------------------------------------------------------------------

## Prepara lo que solo existe en línea: el chat, el micrófono y los avisos del servidor.
func _setup_online() -> void:
	Net.error_received.connect(_on_net_error)
	Net.room_closed.connect(_on_connection_lost)
	Net.disconnected.connect(_on_net_disconnected)
	Net.game_started.connect(_on_net_game_started)
	var chat := ChatPanel.new()
	chat.collapsible = true
	chat.with_mic = true
	$HUD.add_child(chat)
	# Pegado al borde derecho, a media altura; al desplegarse crece hacia la izquierda y hacia arriba/abajo.
	chat.anchor_left = 1.0
	chat.anchor_right = 1.0
	chat.anchor_top = 0.5
	chat.anchor_bottom = 0.5
	chat.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	chat.grow_vertical = Control.GROW_DIRECTION_BOTH
	chat.offset_left = -308.0
	chat.offset_right = -8.0
	chat.offset_top = -20.0
	chat.offset_bottom = 20.0


func _on_net_error(message: String) -> void:
	_hint.text = "! " + message
	_hint.get_parent().show()


func _on_net_disconnected() -> void:
	_on_connection_lost(tr("ONLINE_DISCONNECTED"))


## Empieza otra partida en la misma sala: se limpia lo de la anterior.
func _on_net_game_started() -> void:
	_topic_seen = ""
	_shared_stance = ""
	_hand_owner = null
	_log.clear()
	for list: Array in _notes.values():
		list.clear()


## Se cerró la sala o se perdió la conexión: aviso a pantalla completa y vuelta al menú.
func _on_connection_lost(reason: String) -> void:
	_engine.changed.disconnect(_sync)
	_reset_hud()
	_overlay_title.text = tr("ONLINE_ROOM_CLOSED")
	_overlay_body.text = reason
	_overlay_button.text = tr("BTN_BACK_MENU")
	_overlay_action = _go_to_menu
	_overlay_button.show()
	_overlay_button2.hide()
	_overlay.show()
	Voice.set_mic(false)


## Pantalla de espera: no eres quien debe actuar ahora.
func _wait_for(text: String) -> void:
	_action_button.hide()
	_hint.text = text


## La pregunta en el idioma de esta pantalla (en línea llega con todos los idiomas).
func _topic() -> String:
	return GameState.topic_display(_engine.topic)


# ---------------------------------------------------------------------------
# Parámetros de los comodines (monto del Soborno, extra de la Lupa)
# ---------------------------------------------------------------------------

func _build_param_row() -> void:
	_param_row = HBoxContainer.new()
	_param_row.add_theme_constant_override("separation", 8)
	_param_row.hide()
	var label := Label.new()
	label.name = "AmountLabel"
	_param_row.add_child(label)
	_amount = SpinBox.new()
	_amount.min_value = 1
	_amount.step = 1
	_amount.custom_minimum_size = Vector2(90, 0)
	_param_row.add_child(_amount)
	_extra_check = CheckButton.new()
	_param_row.add_child(_extra_check)
	var footer: HBoxContainer = _action_button.get_parent()
	footer.add_child(_param_row)
	footer.move_child(_param_row, 1) # justo después de la barra de pistas


func _show_wild_params(card: CardData) -> void:
	var p := _hand_owner
	match card.effect:
		"bribe":
			_amount.max_value = maxi(p.coins, 1)
			_amount.value = mini(int(_amount.value), maxi(p.coins, 1))
			_param_row.get_node("AmountLabel").text = tr("PARAM_BRIBE_AMOUNT")
			_param_row.get_node("AmountLabel").show()
			_amount.show()
			_extra_check.hide()
			_param_row.show()
		"peek":
			_param_row.get_node("AmountLabel").hide()
			_amount.hide()
			_extra_check.text = tr("PARAM_BUY_EXTRA") % Config.lupa_cost
			_extra_check.disabled = p.coins < Config.lupa_cost
			if _extra_check.disabled:
				_extra_check.button_pressed = false
			_extra_check.show()
			_param_row.show()


func _wild_params(card: CardData) -> Dictionary:
	match card.effect:
		"bribe":
			return {"amount": int(_amount.value)}
		"peek":
			return {"buy_extra": _extra_check.button_pressed}
	return {}


# ---------------------------------------------------------------------------
# Eventos, avisos y textos
# ---------------------------------------------------------------------------

## Lee los eventos del motor: los públicos van al registro de la barra de pistas; los privados
## se guardan para mostrarlos solo cuando ese jugador vea su mano.
func _consume_events() -> void:
	for ev in _engine.take_events():
		var text := _describe(ev)
		if text == "":
			continue
		var to := int(ev["to"])
		if to < 0:
			_log.append(text)
			while _log.size() > LOG_LINES:
				_log.pop_front()
		else:
			_notes[to].append(text)


func _describe(ev: Dictionary) -> String:
	match str(ev["type"]):
		"turn_skipped":
			return tr("EV_TURN_SKIPPED") % _pname(ev["player"])
		"card_played":
			var key := "EV_INTERRUPTED" if ev.get("interrupt", false) else "EV_CARD_PLAYED"
			return tr(key) % [_pname(ev["player"]), _ctitle(ev["card"])]
		"wild_played":
			var key := "EV_WILD_RESPONSE" if ev.get("response", false) else "EV_WILD_PLAYED"
			return tr(key) % [_pname(ev["player"]), _ctitle(ev["card"])]
		"points":
			return tr("EV_POINTS") % [_pname(ev["player"]), int(ev["delta"])]
		"wild_cancelled":
			return tr("EV_CANCELLED") % _ctitle(ev["card"])
		"blocked":
			return tr("EV_BLOCKED") % _pname(ev["player"])
		"block_negated":
			return tr("EV_BLOCK_NEGATED") % _pname(ev["player"])
		"steal_blocked":
			return tr("EV_STEAL_BLOCKED")
		"steal_failed":
			return tr("EV_STEAL_FAILED")
		"card_stolen":
			return tr("EV_STOLEN") % _pname(ev["player"])
		"benefits_cancelled":
			return tr("EV_BENEFITS_CANCELLED") % _pname(ev["player"])
		"verdict_result":
			return tr("EV_VERDICT_OK" if ev["correct"] else "EV_VERDICT_BAD") % _pname(ev["player"])
		"contempt_transfer":
			return tr("EV_CONTEMPT") % [_pname(ev["from"]), _pname(ev["to_player"])]
		"appeal_granted":
			return tr("EV_APPEAL") % int(ev["seconds"])
		"bribe_answered":
			return tr("EV_BRIBE_ANSWERED")
		"wild_swapped":
			return tr("EV_WILD_SWAPPED") % _pname(ev["player"])
		"time_up":
			return tr("EV_TIME_UP") % _pname(ev["player"])
		# --- Privados (ev["to"] es el único jugador que los ve) ---
		"stolen_card":
			var title := _ctitle(ev["card"])
			return tr("EV_YOU_STOLE") % title if int(ev["to"]) == int(ev["by"]) else tr("EV_YOU_WERE_ROBBED") % title
		"peek":
			var titles: Array[String] = []
			for id in ev["wilds"]:
				titles.append(_ctitle(id))
			return tr("EV_PEEK") % (", ".join(titles) if not titles.is_empty() else tr("EV_PEEK_NONE"))
		"wild_received":
			return tr("EV_WILD_RECEIVED") % _ctitle(ev["card"])
		"bribe_decided":
			return tr("EV_BRIBE_ACCEPTED") % int(ev["lost"]) if ev["accepted"] else tr("EV_BRIBE_REJECTED")
	return ""


func _pname(index: Variant) -> String:
	var p := _engine.player_by_index(int(index))
	return p.display_name if p != null else "?"


func _ctitle(id: Variant) -> String:
	var c := _engine.catalog.by_id(str(id))
	return c.title if c != null else str(id)


## Avisos privados pendientes de `p`, en un solo texto (y los borra).
func _take_notes(p: PlayerData) -> String:
	var list: Array = _notes[p.index]
	var text := "\n".join(list)
	list.clear()
	return text


func _apply_log_to_hint() -> void:
	if _log.is_empty():
		return
	var lines := "\n".join(_log)
	_hint.text = lines if _hint.text == "" else _hint.text + "\n" + lines


## "Ana +1, Beto -2" (o "sin cambios") para explicar qué pasa si el juez decide algo.
func _effects_text(who: PlayerData, rival: PlayerData, self_pts: int, rival_pts: int) -> String:
	var parts: Array[String] = []
	if self_pts != 0:
		parts.append("%s %+d" % [who.display_name, self_pts])
	if rival_pts != 0:
		parts.append("%s %+d" % [rival.display_name, rival_pts])
	return ", ".join(parts) if not parts.is_empty() else tr("NO_CHANGE")


func _stance_text(p: PlayerData) -> String:
	if not _engine.stance_choices.has(p):
		return ""
	return tr("STANCE_AGREE") if _engine.stance_choices[p] else tr("STANCE_DISAGREE")


## Posturas visibles para todos: solo cuando ya se revelaron y hay debate.
func _stances_text() -> Dictionary:
	var out := {}
	if _engine.phase == Phase.STANCE or not _engine.stances_opposite:
		return out
	for p in _engine.debaters:
		out[p] = _stance_text(p)
	return out


# ---------------------------------------------------------------------------
# Utilidades de interfaz
# ---------------------------------------------------------------------------

func _refresh_scoreboard() -> void:
	var stances := _stances_text()
	for p in GameState.players:
		var is_judge: bool = p == _engine.judge
		var role := tr("ROLE_JUDGE") if is_judge else str(stances.get(p, ""))
		_panels[p].refresh(role, is_judge)


## Actualiza el cronómetro y el reloj de la partida.
func _update_labels() -> void:
	if _engine == null:
		return
	if _engine.turn_index > 0:
		_round_label.text = tr("TURN_CLOCK") % [_engine.turn_index, _mmss(_engine.clock)]
	else:
		_round_label.text = tr("BEFORE_DEBATE")
	var counting: bool = _engine.phase in [Phase.SPEECH, Phase.ANSWER, Phase.RESPONSE]
	if counting:
		var t := _engine.time_left()
		_timer_label.text = _mmss(ceilf(t))
		if t <= 10.0:
			_timer_label.add_theme_color_override("font_color", TIME_UP_COLOR)
		else:
			_timer_label.remove_theme_color_override("font_color")
	else:
		_timer_label.text = ""
		_timer_label.remove_theme_color_override("font_color")
	# El juez puede terminar la partida después de N minutos (solo mientras alguien habla).
	_judge_end_button.visible = _engine.phase == Phase.SPEECH and _engine.can_judge_end() and not _overlay.visible \
		and (not _online or _me == _engine.judge)


func _mmss(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [floori(s / 60.0), s % 60]


func _set_action(text: String, callable: Callable, enabled := true) -> void:
	_action_button.text = text
	_action_button.disabled = not enabled
	_action = callable
	_action_button.show()


## Limpia todo lo que dependía del estado anterior. La mesa 3D no se borra aquí: cada estado
## la sincroniza con lo que corresponde.
func _reset_hud() -> void:
	_selected_card = null
	_ctx = Ctx.NONE
	_skip_button.hide()
	_judge_end_button.hide()
	_interrupt_button.hide()
	_swap_button.hide()
	_agree_button.hide()
	_disagree_button.hide()
	_param_row.hide()
	_action_button.show()
	_center_panel.hide()
	_judge_panel.hide()
	_info.hide()
	_overlay.hide()
	_overlay_button2.hide()
	_clear(_judge_panel)
	_stage.hide_hand()
	_stage.select_card(null)
	_stage.focus_cards([])
	_stage.set_active_player(null)


func _sync_table() -> void:
	var normals := {}
	var wilds := {}
	for p in _engine.debaters:
		normals[p] = p.last_normal
		wilds[p] = p.last_wild
	_stage.sync_table(normals, wilds, true, true)


func _clear(container: Node) -> void:
	for n in container.get_children():
		container.remove_child(n)
		n.queue_free()


func _add_text(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(560, 0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	_judge_panel.add_child(label)


func _button_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	return row


func _button(text: String, callable: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(120, 52)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(callable)
	return b
