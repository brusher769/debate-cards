#!/usr/bin/env bash
# Prueba del juego en línea SIN pantalla: un servidor de verdad y 3 clientes (bots) que se conectan
# por red (localhost), crean/entran a una sala, chatean, mandan "voz" y juegan partidas completas.
#
#   GODOT=/ruta/a/godot bash tests/run_online_test.sh          # partidas completas (por defecto)
#   GODOT=/ruta/a/godot bash tests/run_online_test.sh leave    # uno se va en plena partida
#   GODOT=/ruta/a/godot bash tests/run_online_test.sh abuse    # mensajes inválidos contra el servidor
#   GODOT=/ruta/a/godot bash tests/run_online_test.sh host     # un jugador aloja la sala (sin servidor aparte)
#
# Imprime "ONLINE OK" si todo salió bien (código de salida 0). En Windows se corre con Git Bash.

GODOT="${GODOT:-godot}"
SCENARIO="${1:-full}"
GAMES="${GAMES:-2}"
TIMEOUT="${TIMEOUT:-120}"
VERBOSE="${VERBOSE:-}"
cd "$(dirname "$0")/.." || exit 1
PORT=$((20000 + RANDOM % 20000))
TMP="$(mktemp -d)"
CODE_FILE="$TMP/code.txt"

pause() { timeout "$1" tail -f /dev/null > /dev/null 2>&1; }

SERVER_PID=""
if [ "$SCENARIO" != "host" ]; then
	"$GODOT" --headless --path . res://scenes/server.tscn -- --port=$PORT --quit-after=240 > "$TMP/server.log" 2>&1 &
	SERVER_PID=$!
	for i in $(seq 1 100); do
		grep -q "SERVIDOR LISTO" "$TMP/server.log" 2>/dev/null && break
		pause 0.2
	done
	if ! grep -q "SERVIDOR LISTO" "$TMP/server.log"; then
		echo "ONLINE FALLO: el servidor no arrancó"; cat "$TMP/server.log"; kill $SERVER_PID 2>/dev/null; exit 1
	fi
else
	: > "$TMP/server.log"
fi

COMMON="--address=127.0.0.1 --port=$PORT --code-file=$CODE_FILE --games=$GAMES --timeout=$TIMEOUT $VERBOSE"
LEAVE=""
[ "$SCENARIO" = "leave" ] && LEAVE="--leave-at-turn=3"
if [ "$SCENARIO" = "abuse" ]; then
	# Un solo cliente que manda mensajes inválidos: el servidor tiene que rechazarlos todos.
	"$GODOT" --headless --path . res://tests/net_bot.tscn -- $COMMON --name=Abuso --abuse > "$TMP/bot1.log" 2>&1
	R1=$?
	kill $SERVER_PID 2>/dev/null
	wait $SERVER_PID 2>/dev/null
	echo "--- cliente ---"; grep -E "BOT_|fallo" "$TMP/bot1.log" | head
	if [ $R1 -eq 0 ] && grep -q "BOT_ABUSE_OK" "$TMP/bot1.log"; then echo "ONLINE OK (abuse)"; exit 0; fi
	echo "ONLINE CON FALLOS (logs en $TMP)"; exit 1
fi
HOSTFLAG=""
[ "$SCENARIO" = "host" ] && HOSTFLAG="--host"
"$GODOT" --headless --path . res://tests/net_bot.tscn -- $COMMON --name=Ana --create $HOSTFLAG > "$TMP/bot1.log" 2>&1 &
P1=$!
"$GODOT" --headless --path . res://tests/net_bot.tscn -- $COMMON --name=Beto --forge > "$TMP/bot2.log" 2>&1 &
P2=$!
"$GODOT" --headless --path . res://tests/net_bot.tscn -- $COMMON --name=Caro $LEAVE > "$TMP/bot3.log" 2>&1 &
P3=$!

wait $P1; R1=$?
wait $P2; R2=$?
wait $P3; R3=$?
[ -n "$SERVER_PID" ] && kill $SERVER_PID 2>/dev/null
[ -n "$SERVER_PID" ] && wait $SERVER_PID 2>/dev/null

STATUS=0
[ "$SCENARIO" = "host" ] && cp "$TMP/bot1.log" "$TMP/server.log"
echo "--- servidor ---"; grep "^\[servidor\]" "$TMP/server.log" | head -30
for n in 1 2 3; do echo "--- bot $n ---"; grep -E "BOT_|rechazada" "$TMP/bot$n.log" | head -12; done

if [ "$SCENARIO" = "leave" ]; then
	grep -q "BOT_LEFT Caro" "$TMP/bot3.log" || { echo "ONLINE FALLO: Caro no salió"; STATUS=1; }
	grep -q "BOT_CLOSED Ana" "$TMP/bot1.log" || { echo "ONLINE FALLO: Ana no se enteró de que cerraron la sala"; STATUS=1; }
	grep -q "BOT_CLOSED Beto" "$TMP/bot2.log" || { echo "ONLINE FALLO: Beto no se enteró de que cerraron la sala"; STATUS=1; }
	grep -q "sala .* cerrada" "$TMP/server.log" || { echo "ONLINE FALLO: el servidor no cerró la sala"; STATUS=1; }
else
	for n in 1 2 3; do
		grep -q "BOT_DONE .* games=$GAMES " "$TMP/bot$n.log" || { echo "ONLINE FALLO: el bot $n no terminó las $GAMES partidas"; STATUS=1; }
		grep -q "BOT_FAIL" "$TMP/bot$n.log" && { echo "ONLINE FALLO: el bot $n falló"; STATUS=1; }
		# Cada bot recibió los 3 saludos del chat y trozos de voz de los otros dos.
		grep -q "chat=3 " "$TMP/bot$n.log" || { echo "ONLINE FALLO: el bot $n no recibió los 3 mensajes de chat"; STATUS=1; }
		grep -qE "voice_bytes=([1-9][0-9]*) " "$TMP/bot$n.log" || { echo "ONLINE FALLO: el bot $n no recibió voz"; STATUS=1; }
	done
	[ "$(grep -c 'fin de la partida' "$TMP/server.log")" -ge "$GAMES" ] || { echo "ONLINE FALLO: el servidor no terminó $GAMES partidas"; STATUS=1; }
fi
[ $R1 -ne 0 ] && [ "$SCENARIO" != "leave" ] && STATUS=1
if [ $STATUS -eq 0 ]; then echo "ONLINE OK ($SCENARIO)"; else echo "ONLINE CON FALLOS (logs en $TMP)"; fi
exit $STATUS
