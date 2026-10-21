#!/usr/bin/env bash
# Prueba de la INTERFAZ del juego en línea con pantalla: un servidor sin pantalla, dos bots sin
# pantalla y UNA ventana que hace de jugador humano (crea la sala, juega con clics).
#
#   GODOT=/ruta/a/godot bash tests/run_online_ui_test.sh
#   SHOT_DIR=/ruta/capturas GODOT=... bash tests/run_online_ui_test.sh    # con capturas
#
# GODOT_HEADLESS puede apuntar al ejecutable de consola (para servidor y bots); por defecto se usa GODOT.
# Imprime "ONLINE UI OK" si todo salió bien (código de salida 0).

GODOT="${GODOT:-godot}"
GODOT_HEADLESS="${GODOT_HEADLESS:-$GODOT}"
cd "$(dirname "$0")/.." || exit 1
PORT=$((20000 + RANDOM % 20000))
TMP="$(mktemp -d)"
CODE_FILE="$TMP/code.txt"

pause() { timeout "$1" tail -f /dev/null > /dev/null 2>&1; }

"$GODOT_HEADLESS" --headless --path . res://scenes/server.tscn -- --port=$PORT --quit-after=300 > "$TMP/server.log" 2>&1 &
SERVER_PID=$!
for i in $(seq 1 100); do
	grep -q "SERVIDOR LISTO" "$TMP/server.log" 2>/dev/null && break
	pause 0.2
done
grep -q "SERVIDOR LISTO" "$TMP/server.log" || { echo "ONLINE UI FALLO: el servidor no arrancó"; cat "$TMP/server.log"; kill $SERVER_PID 2>/dev/null; exit 1; }

COMMON="--address=127.0.0.1 --port=$PORT --code-file=$CODE_FILE --games=1 --timeout=${BOT_TIMEOUT:-150}"
"$GODOT_HEADLESS" --headless --path . res://tests/net_bot.tscn -- $COMMON --name=Beto > "$TMP/bot2.log" 2>&1 &
P2=$!
"$GODOT_HEADLESS" --headless --path . res://tests/net_bot.tscn -- $COMMON --name=Caro > "$TMP/bot3.log" 2>&1 &
P3=$!

"$GODOT" --path . res://tests/online_ui_smoke.tscn -- --address=127.0.0.1 --port=$PORT --code-file=$CODE_FILE > "$TMP/ui.log" 2>&1
RU=$?
wait $P2; R2=$?
wait $P3; R3=$?
kill $SERVER_PID 2>/dev/null
wait $SERVER_PID 2>/dev/null

echo "--- servidor ---"; grep "^\[servidor\]" "$TMP/server.log" | head -20
echo "--- ventana ---"; grep -E "ONLINE UI|FALLO|ERROR" "$TMP/ui.log" | head -20
for n in 2 3; do echo "--- bot $n ---"; grep -E "BOT_" "$TMP/bot$n.log" | head -5; done
STATUS=0
[ $RU -ne 0 ] && STATUS=1
grep -q "ONLINE UI OK" "$TMP/ui.log" || STATUS=1
grep -q "BOT_DONE Beto" "$TMP/bot2.log" || { echo "el bot Beto no terminó"; STATUS=1; }
grep -q "BOT_DONE Caro" "$TMP/bot3.log" || { echo "el bot Caro no terminó"; STATUS=1; }
grep -q "ERROR" "$TMP/ui.log" && { echo "hubo errores de Godot en la ventana"; STATUS=1; }
if [ $STATUS -eq 0 ]; then echo "ONLINE UI OK"; else echo "ONLINE UI CON FALLOS (logs en $TMP)"; fi
exit $STATUS
