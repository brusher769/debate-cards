extends Node
## Autoload "Net": la capa de red del juego en línea (WebSocket, multijugador de alto nivel de Godot).
##
## Se usa WebSocket (y no ENet/UDP) para poder alojar el servidor en servicios web como Render,
## que solo dejan pasar HTTP/WebSocket. El cliente acepta una URL completa ("wss://algo.onrender.com")
## o "dirección:puerto" para la red local (se convierte en "ws://dirección:puerto").
##
## El mismo script corre en el servidor y en los clientes (las funciones @rpc tienen que existir
## igual en todos):
##   - SERVIDOR (start_server): tiene las salas, cada una con su GameRoom y su DebateEngine de
##     verdad. Es AUTORITATIVO: valida cada acción con el motor, guarda las manos y manda a cada
##     jugador solo su propia foto del estado (DebateEngine.snapshot_for). Ningún cliente puede ver
##     la mano ni el comodín del rival, ni lo que el juez decidió sobre un soborno.
##   - CLIENTE (connect_to): manda acciones (c_*) y recibe fotos y eventos (s_*), que copia en un
##     motor espejo (`mirror`). La mesa de siempre (table.gd) lo dibuja igual que en local.
##   - ANFITRIÓN (host_here): un jugador hace de servidor y de jugador a la vez (para jugar sin
##     alquilar un servidor).
##
## Convención de nombres: c_* = del cliente al servidor; s_* = del servidor a los clientes.
## Con la variable de entorno NET_DEBUG=1 se imprime cada acción que manda un cliente y cada una que
## recibe el servidor (útil para ver qué pasa en una partida atascada).

signal connected ## el cliente conectó con el servidor
signal connection_failed
signal disconnected ## se perdió la conexión con el servidor
signal joined(info: Dictionary) ## entraste a una sala (la creaste o te uniste)
signal room_updated(info: Dictionary) ## cambió quién está en la sala
signal error_received(message: String)
signal game_started ## el servidor empezó una partida
signal state_received ## llegó una foto nueva del estado (ya está copiada en `mirror`)
signal chat_received(sender: String, text: String)
signal room_closed(reason: String) ## la sala se cerró (alguien se fue) o saliste de ella
signal voice_received(slot: int, data: PackedByteArray)

const DEFAULT_PORT := 7777
const MAX_CLIENTS := 60
## Versión del protocolo: si cambia el formato de los mensajes, súbela para que un cliente viejo
## no se conecte a un servidor nuevo.
const PROTOCOL := 1
const CODE_LETTERS := "ABCDEFGHJKLMNPQRSTUVWXYZ" # sin I ni O para no confundirlas con 1 y 0
const CODE_LENGTH := 4
const ROOM_SIZE := 3
const RESYNC_SECONDS := 5.0
const MAX_NAME := 16
const MAX_CHAT := 200
## Segundos que se espera al servidor antes de rendirse.
const CONNECT_TIMEOUT := 8.0
## Con una URL (servidor en internet) se espera más: el plan gratis de Render apaga el servidor si
## nadie lo usa y tarda cerca de un minuto en despertarlo.
const CONNECT_TIMEOUT_URL := 75.0
## Tamaño de los búferes de WebSocket (bytes). Los de Godot por defecto (64 KB) se quedan cortos
## para las fotos del estado y la voz.
const WS_BUFFER := 512 * 1024

# --- Estado del cliente ---
## Tu lugar en la sala (0, 1 o 2); -1 si no estás en ninguna.
var my_slot := -1
var room_code := ""
## {"code", "mode", "names": [String], "host_slot", "playing", "games"}
var room_info := {}
var mirror: DebateEngine
## true si los datos (cartas y reglas) de este cliente no son los mismos que los del servidor.
var data_mismatch := false

# --- Estado del servidor ---
var _is_server := false
var _rooms := {} # código -> ServerRoom
var _peer_room := {} # id de par -> código de sala
var _rng := RandomNumberGenerator.new()
var _connected_signals := false
var _connecting_until := 0.0 ## instante (en segundos) en que se da por fallida la conexión; 0 = no se está conectando


## Datos de una sala en el servidor.
class ServerRoom extends RefCounted:
	var code := ""
	var mode := "normal"
	var peers: Array[int] = [] ## id de par de cada lugar (el índice es el lugar en la sala)
	var names: Array[String] = []
	var host_peer := 0
	var playing := false
	var game_room: GameRoom
	var dirty := false
	var sync_accum := 0.0
	var over_logged := false


func _ready() -> void:
	_rng.randomize()


# ---------------------------------------------------------------------------
# Arranque: servidor, anfitrión y cliente
# ---------------------------------------------------------------------------

## Empieza a atender salas en `port` (TCP, WebSocket). Devuelve OK o el error de Godot.
func start_server(port := DEFAULT_PORT) -> Error:
	var peer := _new_peer()
	var err := peer.create_server(port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_is_server = true
	_connect_signals()
	return OK


## Como start_server, pero quien lo llama también juega (sale por `connected` enseguida).
func host_here(port := DEFAULT_PORT) -> Error:
	var err := start_server(port)
	if err == OK:
		connected.emit.call_deferred()
	return err


## Se conecta a un servidor. `address` puede ser una URL completa ("wss://algo.onrender.com"; entonces
## `port` no se usa) o una dirección ("192.168.1.20"). El resultado llega por las señales
## connected / connection_failed.
func connect_to(address: String, port := DEFAULT_PORT) -> Error:
	var is_url := address.contains("://")
	var url := address if is_url else "ws://%s:%d" % [address, port]
	var peer := _new_peer()
	var err := peer.create_client(url)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_is_server = false
	_connect_signals()
	_connecting_until = Time.get_ticks_msec() / 1000.0 + (CONNECT_TIMEOUT_URL if is_url else CONNECT_TIMEOUT)
	return OK


func _new_peer() -> WebSocketMultiplayerPeer:
	var peer := WebSocketMultiplayerPeer.new()
	peer.inbound_buffer_size = WS_BUFFER
	peer.outbound_buffer_size = WS_BUFFER
	return peer


## Corta la conexión (o apaga el servidor) y olvida la sala.
func shutdown() -> void:
	_connecting_until = 0.0
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_is_server = false
	_rooms.clear()
	_peer_room.clear()
	_reset_client()


func is_server() -> bool:
	return _is_server


## Huella de las cartas y las reglas de este cliente; sirve para avisar si el servidor tiene otras.
static func data_version() -> String:
	return (FileAccess.get_md5("res://data/cards.json") + FileAccess.get_md5("res://data/config.json")).md5_text()


func _connect_signals() -> void:
	if _connected_signals:
		return
	_connected_signals = true
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## WebSocket no tiene un tope de conexiones como ENet: el servidor corta a los que sobran.
func _on_peer_connected(id: int) -> void:
	if _is_server and multiplayer.get_peers().size() > MAX_CLIENTS:
		(multiplayer.multiplayer_peer as WebSocketMultiplayerPeer).disconnect_peer(id)


func _on_connected_to_server() -> void:
	_connecting_until = 0.0
	connected.emit()


func _on_connection_failed() -> void:
	_connecting_until = 0.0
	connection_failed.emit()


func _on_server_disconnected() -> void:
	_reset_client()
	disconnected.emit()


func _reset_client() -> void:
	my_slot = -1
	room_code = ""
	room_info = {}
	mirror = null
	data_mismatch = false


# ---------------------------------------------------------------------------
# API del cliente (lo que llama la interfaz)
# ---------------------------------------------------------------------------

func create_room(player_name: String, mode: String) -> void:
	c_create_room.rpc_id(1, player_name, mode, PROTOCOL)


func join_room(code: String, player_name: String) -> void:
	c_join_room.rpc_id(1, code, player_name, PROTOCOL)


## Solo el anfitrión de la sala, con los 3 jugadores dentro (o al terminar una partida, para otra).
func start_game() -> void:
	c_start_game.rpc_id(1)


## Manda una acción del motor (ver DebateEngine). El servidor pone tu lugar en "player": no se puede
## actuar en nombre de otro.
func send_action(action: Dictionary) -> void:
	if OS.get_environment("NET_DEBUG") != "":
		print("[cliente %d] envío %s" % [multiplayer.get_unique_id(), action])
	c_action.rpc_id(1, action)


func send_chat(text: String) -> void:
	c_chat.rpc_id(1, text)


func send_voice(data: PackedByteArray) -> void:
	c_voice.rpc_id(1, data)


func leave_room() -> void:
	if room_code != "":
		c_leave.rpc_id(1)
	_reset_client()


func is_host() -> bool:
	return my_slot >= 0 and int(room_info.get("host_slot", -1)) == my_slot


# ---------------------------------------------------------------------------
# Cliente -> servidor (se ejecutan en el servidor)
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func c_create_room(player_name: String, mode: String, protocol: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	if _check_protocol(peer, protocol) or _in_room(peer):
		return
	var r := ServerRoom.new()
	r.code = _new_code()
	r.mode = mode if GameRoom.MODES.has(mode) else "normal"
	r.host_peer = peer
	_add_member(r, peer, player_name)
	_rooms[r.code] = r
	_log("sala %s creada (modo %s)" % [r.code, r.mode])
	_after_join(r, peer)


@rpc("any_peer", "call_local", "reliable")
func c_join_room(code: String, player_name: String, protocol: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	if _check_protocol(peer, protocol) or _in_room(peer):
		return
	var r: ServerRoom = _rooms.get(code.strip_edges().to_upper())
	if r == null:
		_fail(peer, "No existe la sala «%s»." % code)
	elif r.playing or r.game_room != null:
		_fail(peer, "Esa sala ya empezó a jugar.")
	elif r.peers.size() >= ROOM_SIZE:
		_fail(peer, "La sala está llena.")
	else:
		_add_member(r, peer, player_name)
		_log("%s entró a la sala %s" % [r.names[r.peers.size() - 1], r.code])
		_after_join(r, peer)


@rpc("any_peer", "call_local", "reliable")
func c_start_game() -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	var r := _room_of(peer)
	if r == null:
		return
	if peer != r.host_peer:
		_fail(peer, "Solo quien creó la sala puede empezar la partida.")
	elif r.peers.size() != ROOM_SIZE:
		_fail(peer, "Hacen falta %d jugadores." % ROOM_SIZE)
	elif r.playing and r.game_room.engine.phase != DebateEngine.Phase.OVER:
		_fail(peer, "La partida sigue en curso.")
	else:
		_start_game(r)


@rpc("any_peer", "call_local", "reliable")
func c_action(action: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	var r := _room_of(peer)
	if r == null or not r.playing:
		_fail(peer, "No hay una partida en curso.")
		return
	if action.size() > 12:
		_fail(peer, "Acción inválida.")
		return
	# El servidor decide quién actúa: siempre el lugar del que mandó el mensaje.
	action["player"] = r.peers.find(peer)
	if OS.get_environment("NET_DEBUG") != "":
		_log("acción de %s: %s" % [r.names[action["player"]], action])
	var result := r.game_room.engine.apply(action)
	if not result["ok"]:
		_fail(peer, str(result["error"]))
		return
	_broadcast_state(r)


@rpc("any_peer", "call_local", "reliable")
func c_chat(text: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	var r := _room_of(peer)
	if r == null:
		return
	var clean := text.strip_edges().left(MAX_CHAT)
	if clean == "":
		return
	var slot := r.peers.find(peer)
	for p in r.peers:
		s_chat.rpc_id(p, slot, r.names[slot], clean)


@rpc("any_peer", "call_local", "reliable")
func c_leave() -> void:
	if not multiplayer.is_server():
		return
	_remove_peer(_sender(), "%s salió de la sala.")


## La voz se manda sin garantía de entrega (si se pierde un trozo, no se espera): el servidor
## solo la reenvía a los demás jugadores de la sala.
@rpc("any_peer", "call_local", "unreliable")
func c_voice(data: PackedByteArray) -> void:
	if not multiplayer.is_server() or data.size() > 4096:
		return
	var peer := _sender()
	var r := _room_of(peer)
	if r == null:
		return
	var slot := r.peers.find(peer)
	for p in r.peers:
		if p != peer:
			s_voice.rpc_id(p, slot, data)


# ---------------------------------------------------------------------------
# Servidor -> cliente (se ejecutan en los clientes)
# ---------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func s_joined(slot: int, info: Dictionary) -> void:
	my_slot = slot
	room_code = str(info["code"])
	room_info = info
	data_mismatch = str(info.get("data_version", "")) != data_version()
	joined.emit(info)


@rpc("authority", "call_local", "reliable")
func s_room_updated(info: Dictionary) -> void:
	room_info = info
	room_updated.emit(info)


@rpc("authority", "call_local", "reliable")
func s_error(message: String) -> void:
	error_received.emit(message)


@rpc("authority", "call_local", "reliable")
func s_game_started() -> void:
	if mirror == null:
		mirror = DebateEngine.create_mirror(CardCatalog.load_default())
	GameState.use_online(mirror, my_slot)
	game_started.emit()


@rpc("authority", "call_local", "reliable")
func s_state(snapshot: Dictionary, events: Array) -> void:
	if mirror == null:
		return
	# Los eventos llegan antes que la foto: la interfaz los lee cuando la foto avisa que cambió.
	mirror.push_events(events)
	mirror.load_snapshot(snapshot)
	state_received.emit()


@rpc("authority", "call_local", "reliable")
func s_chat(_slot: int, sender: String, text: String) -> void:
	chat_received.emit(sender, text)


@rpc("authority", "call_local", "reliable")
func s_room_closed(reason: String) -> void:
	_reset_client()
	room_closed.emit(reason)


@rpc("authority", "call_local", "unreliable")
func s_voice(slot: int, data: PackedByteArray) -> void:
	voice_received.emit(slot, data)


# ---------------------------------------------------------------------------
# Servidor: salas, partidas y reloj
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	# Si el servidor no contesta a tiempo, se da por fallida la conexión.
	if _connecting_until > 0.0 and Time.get_ticks_msec() / 1000.0 > _connecting_until:
		_connecting_until = 0.0
		if multiplayer.multiplayer_peer != null:
			multiplayer.multiplayer_peer.close()
			multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		connection_failed.emit()
	# El espejo corre su reloj solo para mostrarlo (las reglas las resuelve el servidor).
	if mirror != null:
		mirror.tick(delta)
	if not _is_server:
		return
	for r: ServerRoom in _rooms.values():
		if not r.playing or r.game_room.engine.phase == DebateEngine.Phase.OVER:
			continue
		r.game_room.engine.tick(delta)
		r.sync_accum += delta
		if r.dirty or r.sync_accum >= RESYNC_SECONDS:
			_broadcast_state(r)


func _start_game(r: ServerRoom) -> void:
	if r.game_room == null:
		r.game_room = GameRoom.new()
		r.game_room.all_languages = true # cada cliente muestra la pregunta en su idioma
		r.game_room.setup(r.names, r.mode)
	r.game_room.start_game()
	r.game_room.engine.changed.connect(func() -> void: r.dirty = true)
	r.playing = true
	_log("sala %s: empieza la partida %d" % [r.code, r.game_room.games_played])
	for p in r.peers:
		s_game_started.rpc_id(p)
	_broadcast_state(r)
	_broadcast_room(r)


## Manda a cada jugador de la sala SU foto del estado y los eventos que puede ver.
func _broadcast_state(r: ServerRoom) -> void:
	var engine := r.game_room.engine
	var events := engine.take_events()
	r.dirty = false
	r.sync_accum = 0.0
	for slot in r.peers.size():
		var mine := events.filter(func(ev: Dictionary) -> bool: return int(ev["to"]) == -1 or int(ev["to"]) == slot)
		s_state.rpc_id(r.peers[slot], engine.snapshot_for(engine.player_by_index(slot)), mine)
	if engine.phase == DebateEngine.Phase.OVER and not r.over_logged:
		r.over_logged = true
		_log("sala %s: fin de la partida (%s)" % [r.code, engine.result["reason"]])
	elif engine.phase != DebateEngine.Phase.OVER:
		r.over_logged = false


func _room_info(r: ServerRoom) -> Dictionary:
	return {
		"code": r.code, "mode": r.mode, "names": r.names.duplicate(),
		"host_slot": r.peers.find(r.host_peer), "playing": r.playing,
		"games": r.game_room.games_played if r.game_room != null else 0,
		"data_version": data_version(), "protocol": PROTOCOL,
	}


func _broadcast_room(r: ServerRoom) -> void:
	var info := _room_info(r)
	for p in r.peers:
		s_room_updated.rpc_id(p, info)


func _after_join(r: ServerRoom, peer: int) -> void:
	s_joined.rpc_id(peer, r.peers.find(peer), _room_info(r))
	_broadcast_room(r)


func _add_member(r: ServerRoom, peer: int, player_name: String) -> void:
	var clean := player_name.strip_edges().left(MAX_NAME)
	if clean == "":
		clean = "Jugador %d" % (r.peers.size() + 1)
	# Nombres distintos: se confundirían en el marcador.
	var unique := clean
	var n := 2
	while r.names.has(unique):
		unique = "%s (%d)" % [clean, n]
		n += 1
	r.peers.append(peer)
	r.names.append(unique)
	_peer_room[peer] = r.code


func _on_peer_disconnected(peer: int) -> void:
	if _is_server:
		_remove_peer(peer, "%s se desconectó.")


## Saca a un jugador de su sala. Si la partida ya empezó, se cierra la sala para todos.
func _remove_peer(peer: int, reason_format: String) -> void:
	var r := _room_of(peer)
	if r == null:
		return
	var slot := r.peers.find(peer)
	var who := r.names[slot]
	_peer_room.erase(peer)
	if r.playing or r.game_room != null:
		for p in r.peers:
			if p != peer:
				_peer_room.erase(p)
				s_room_closed.rpc_id(p, reason_format % who)
		_rooms.erase(r.code)
		_log("sala %s cerrada: %s" % [r.code, reason_format % who])
		return
	r.peers.remove_at(slot)
	r.names.remove_at(slot)
	if r.peers.is_empty():
		_rooms.erase(r.code)
		_log("sala %s vacía: se borra" % r.code)
		return
	if r.host_peer == peer:
		r.host_peer = r.peers[0]
	# Los lugares se renumeran; cada jugador se entera de su nuevo lugar.
	for i in r.peers.size():
		s_joined.rpc_id(r.peers[i], i, _room_info(r))


func _room_of(peer: int) -> ServerRoom:
	return _rooms.get(_peer_room.get(peer, ""))


func _in_room(peer: int) -> bool:
	if _peer_room.has(peer):
		_fail(peer, "Ya estás en una sala.")
		return true
	return false


## true (y avisa) si el cliente usa otra versión del protocolo.
func _check_protocol(peer: int, protocol: int) -> bool:
	if protocol != PROTOCOL:
		_fail(peer, "Tu juego y el servidor son de versiones distintas (%d y %d)." % [protocol, PROTOCOL])
		return true
	return false


func _new_code() -> String:
	while true:
		var code := ""
		for i in CODE_LENGTH:
			code += CODE_LETTERS[_rng.randi() % CODE_LETTERS.length()]
		if not _rooms.has(code):
			return code
	return ""


func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id() # 0 = llamada local (el anfitrión)


func _fail(peer: int, message: String) -> void:
	var room := _room_of(peer)
	var who := ""
	if room != null:
		who = " (%s, sala %s)" % [room.names[room.peers.find(peer)], room.code]
	_log("rechazo a %d%s: %s" % [peer, who, message])
	s_error.rpc_id(peer, message)


func _log(text: String) -> void:
	print("[servidor] ", text)
