extends Node
## Autoload "Voice": voz dentro del juego (fase 5), aislada en su propio módulo. Captura el
## micrófono, manda trozos de VoiceCodec por Net (el servidor los reenvía a los demás de la sala)
## y reproduce lo que llega, una voz por jugador. Mientras no se active el micrófono no hace nada.
##
## ESTADO: la parte de red y el códec están probados (tests/voice_test.tscn y el escenario de
## voz de tests/run_online_test.sh). NO se probó con un micrófono real. Qué falta para una voz
## "de verdad": cancelación de eco y de ruido (hoy conviene usar auriculares), un búfer que
## absorba el retraso de red (hoy se reproduce apenas llega), y WebRTC si algún día se quiere voz
## directa entre jugadores sin pasar por el servidor. Para usar el micrófono hay que activar
## "audio/driver/enable_input" (Ajustes del proyecto > Audio > Driver > Enable Input) y reiniciar.

## Alguien habla: `slot` es su lugar en la sala.
signal speaking(slot: int)
signal mic_changed(active: bool)

const MIC_BUS := "VoiceInput"
const PLAYBACK_BUFFER_SECONDS := 0.4

## true mientras el micrófono está abierto y mandando voz.
var mic_open := false
## Texto del último problema (por ejemplo, que enable_input esté apagado); vacío si todo bien.
var last_error := ""

var _capture: AudioEffectCapture
var _mic_player: AudioStreamPlayer
var _voices := {} # lugar en la sala -> {"player": AudioStreamPlayer, "playback": AudioStreamGeneratorPlayback}


func _ready() -> void:
	Net.voice_received.connect(_on_voice)
	Net.room_closed.connect(func(_r: String) -> void: set_mic(false))
	Net.disconnected.connect(func() -> void: set_mic(false))


## Abre o cierra el micrófono. Devuelve false (y deja el motivo en last_error) si no se pudo abrir.
func set_mic(open: bool) -> bool:
	if open == mic_open:
		return true
	last_error = ""
	if open:
		if not ProjectSettings.get_setting("audio/driver/enable_input", false):
			last_error = "MIC_NEEDS_SETTING"
			return false
		_start_capture()
	else:
		_stop_capture()
	mic_open = open
	mic_changed.emit(open)
	return true


func _process(_delta: float) -> void:
	if not mic_open or _capture == null:
		return
	var per_chunk := VoiceCodec.frames_per_chunk(AudioServer.get_mix_rate())
	while _capture.get_frames_available() >= per_chunk:
		var bytes := VoiceCodec.encode(_capture.get_buffer(per_chunk), AudioServer.get_mix_rate())
		if not bytes.is_empty() and Net.room_code != "":
			Net.send_voice(bytes)


func _start_capture() -> void:
	var bus := AudioServer.get_bus_index(MIC_BUS)
	if bus == -1:
		AudioServer.add_bus()
		bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, MIC_BUS)
		_capture = AudioEffectCapture.new()
		AudioServer.add_bus_effect(bus, _capture)
		# Se silencia la salida del bus para no oírse a uno mismo; la captura sigue funcionando.
		AudioServer.set_bus_mute(bus, true)
	else:
		_capture = AudioServer.get_bus_effect(bus, 0) as AudioEffectCapture
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = MIC_BUS
	add_child(_mic_player)
	_mic_player.play()


func _stop_capture() -> void:
	if _mic_player != null:
		_mic_player.stop()
		_mic_player.queue_free()
		_mic_player = null
	if _capture != null:
		_capture.clear_buffer()


## Llegó un trozo de voz de otro jugador: se reproduce en su propio reproductor.
func _on_voice(slot: int, data: PackedByteArray) -> void:
	var voice: Dictionary = _voices.get(slot, {})
	if voice.is_empty():
		var generator := AudioStreamGenerator.new()
		generator.mix_rate = VoiceCodec.RATE
		generator.buffer_length = PLAYBACK_BUFFER_SECONDS
		var player := AudioStreamPlayer.new()
		player.stream = generator
		add_child(player)
		player.play()
		voice = {"player": player, "playback": player.get_stream_playback()}
		_voices[slot] = voice
	var playback: AudioStreamGeneratorPlayback = voice["playback"]
	var frames := VoiceCodec.decode(data)
	if playback != null and playback.get_frames_available() >= frames.size():
		playback.push_buffer(frames)
	speaking.emit(slot)
