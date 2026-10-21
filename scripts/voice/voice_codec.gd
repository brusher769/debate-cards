class_name VoiceCodec
extends RefCounted
## Códec de voz sencillo para mandar audio por la red (fase 5): mono, 16 kHz y 8 bits con la curva
## μ-law (G.711), unos 16 KB/s por quien habla. Es más simple que WebRTC y suficiente para hablar;
## no tiene cancelación de eco ni ajuste automático de volumen. Sin nodos ni audio real, así se
## puede probar sin micrófono (tests/voice_test.tscn).

## Frecuencia de la voz que viaja por la red.
const RATE := 16000
## Duración de cada trozo que se manda, en milisegundos (20 ms = 320 muestras = 320 bytes).
const FRAME_MS := 20
const BIAS := 0x84
const CLIP := 32635


## Cuántas muestras (a `mix_rate`) forman un trozo de FRAME_MS.
static func frames_per_chunk(mix_rate: float) -> int:
	return int(mix_rate * FRAME_MS / 1000.0)


## Convierte un trozo capturado (estéreo, a `mix_rate`) en bytes para mandar: mezcla a mono,
## baja a RATE y comprime a 8 bits. Devuelve un arreglo vacío si el trozo es casi silencio
## (así no se gasta red mientras nadie habla).
static func encode(frames: PackedVector2Array, mix_rate: float, silence_level := 0.01) -> PackedByteArray:
	var out := PackedByteArray()
	if frames.is_empty():
		return out
	var count := int(frames.size() * RATE / mix_rate)
	out.resize(count)
	var loud := 0.0
	for i in count:
		# Interpolación lineal entre las dos muestras más cercanas del original.
		var pos := float(i) * mix_rate / RATE
		var i0 := mini(int(pos), frames.size() - 1)
		var i1 := mini(i0 + 1, frames.size() - 1)
		var t := pos - float(i0)
		var a := (frames[i0].x + frames[i0].y) * 0.5
		var b := (frames[i1].x + frames[i1].y) * 0.5
		var s := lerpf(a, b, t)
		loud = maxf(loud, absf(s))
		out[i] = _encode_sample(int(clampf(s, -1.0, 1.0) * 32767.0))
	if loud < silence_level:
		return PackedByteArray()
	return out


## Convierte bytes recibidos en muestras listas para un AudioStreamGenerator de RATE Hz.
static func decode(data: PackedByteArray) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(data.size())
	for i in data.size():
		var s := float(_decode_sample(data[i])) / 32768.0
		out[i] = Vector2(s, s)
	return out


static func _encode_sample(pcm: int) -> int:
	var sign_bit := (pcm >> 8) & 0x80
	if sign_bit != 0:
		pcm = -pcm
	pcm = mini(pcm, CLIP) + BIAS
	var exponent := 7
	var mask := 0x4000
	while exponent > 0 and (pcm & mask) == 0:
		exponent -= 1
		mask >>= 1
	var mantissa := (pcm >> (exponent + 3)) & 0x0F
	return (~(sign_bit | (exponent << 4) | mantissa)) & 0xFF


static func _decode_sample(byte: int) -> int:
	var u := (~byte) & 0xFF
	var negative := (u & 0x80) != 0
	var exponent := (u >> 4) & 0x07
	var mantissa := u & 0x0F
	var sample := (((mantissa << 3) + BIAS) << exponent) - BIAS
	return -sample if negative else sample
