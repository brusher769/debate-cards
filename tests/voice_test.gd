extends Node
## Prueba de la voz SIN micrófono: el códec (ida y vuelta de audio sintético) y la reproducción
## de lo que llega. La captura del micrófono real no se puede probar aquí.
##   godot --headless --path . res://tests/voice_test.tscn
## Imprime "VOZ OK" si todo pasó.

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FALLO: ", msg)


func _ready() -> void:
	_test_mulaw()
	_test_roundtrip(44100.0)
	_test_roundtrip(48000.0)
	_test_silence()
	_test_playback()
	_test_mic_setting()
	print("VOZ OK" if _failures == 0 else "VOZ CON FALLOS: %d" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


## μ-law: el error de cada muestra es pequeño respecto de su tamaño.
func _test_mulaw() -> void:
	for v in range(-32000, 32001, 250):
		var back := VoiceCodec._decode_sample(VoiceCodec._encode_sample(v))
		_check(absi(back - v) <= maxi(70, int(absf(v) * 0.07)), "μ-law: %d volvió como %d" % [v, back])
	_check(VoiceCodec._decode_sample(VoiceCodec._encode_sample(0)) == 0, "el silencio (0) vuelve como 0")


## Un tono de 440 Hz a la frecuencia de captura sale y vuelve a 16 kHz casi igual.
func _test_roundtrip(mix_rate: float) -> void:
	var n := VoiceCodec.frames_per_chunk(mix_rate)
	var frames := PackedVector2Array()
	for i in n:
		var s := 0.5 * sin(TAU * 440.0 * i / mix_rate)
		frames.append(Vector2(s, s))
	var bytes := VoiceCodec.encode(frames, mix_rate)
	_check(bytes.size() == VoiceCodec.RATE * VoiceCodec.FRAME_MS / 1000, "%d Hz: un trozo de 20 ms son 320 bytes (son %d)" % [mix_rate, bytes.size()])
	var decoded := VoiceCodec.decode(bytes)
	var err := 0.0
	for i in decoded.size():
		var want := 0.5 * sin(TAU * 440.0 * i / VoiceCodec.RATE)
		err += (decoded[i].x - want) * (decoded[i].x - want)
	var rms := sqrt(err / decoded.size())
	_check(rms < 0.03, "%d Hz: el tono vuelve con poco error (rms %.4f)" % [mix_rate, rms])
	# Un solo canal (izquierdo) también se mezcla bien.
	var left := PackedVector2Array()
	for f in frames:
		left.append(Vector2(f.x * 2.0, 0.0))
	_check(VoiceCodec.encode(left, mix_rate).size() == bytes.size(), "canal izquierdo solo: mismo tamaño")


func _test_silence() -> void:
	var quiet := PackedVector2Array()
	quiet.resize(882)
	_check(VoiceCodec.encode(quiet, 44100.0).is_empty(), "el silencio no se manda")
	_check(VoiceCodec.encode(PackedVector2Array(), 44100.0).is_empty(), "un trozo vacío no se manda")


## Lo que llega por red se reproduce sin errores y crea un reproductor por jugador.
func _test_playback() -> void:
	var frames := PackedVector2Array()
	for i in 882:
		var s := 0.4 * sin(TAU * 300.0 * i / 44100.0)
		frames.append(Vector2(s, s))
	var bytes := VoiceCodec.encode(frames, 44100.0)
	var got: Array[int] = []
	Voice.speaking.connect(func(slot: int) -> void: got.append(slot))
	for i in 3:
		Voice._on_voice(1, bytes)
	Voice._on_voice(2, bytes)
	_check(Voice._voices.has(1) and Voice._voices.has(2), "un reproductor por jugador que habla")
	_check(got == [1, 1, 1, 2], "se avisa quién habla (%s)" % str(got))


## Sin "audio/driver/enable_input" el micrófono no se abre y se explica por qué.
func _test_mic_setting() -> void:
	var enabled: bool = ProjectSettings.get_setting("audio/driver/enable_input", false)
	if enabled:
		return # con la opción activada, abrir el micrófono depende del equipo: no se prueba aquí
	_check(not Voice.set_mic(true), "sin enable_input no se abre el micrófono")
	_check(Voice.last_error == "MIC_NEEDS_SETTING" and not Voice.mic_open, "y queda el motivo")
	_check(Voice.set_mic(false), "cerrarlo siempre se puede")
