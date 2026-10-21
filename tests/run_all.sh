#!/usr/bin/env bash
# Corre TODAS las pruebas del proyecto, una tras otra, y al final dice cuáles pasaron.
#
#   GODOT=/ruta/a/godot bash tests/run_all.sh            # todo (las de pantalla abren ventanas)
#   HEADLESS_ONLY=1 GODOT=... bash tests/run_all.sh      # solo las que no necesitan pantalla
#
# En Windows se corre con Git Bash y GODOT apunta al ejecutable de consola (*_console.exe).
# Código de salida 0 = todo bien.

GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.." || exit 1
export GODOT
FAILED=()
RESULTS=()

run() { # nombre, texto que debe aparecer, comando...
	local name="$1"; local expect="$2"; shift 2
	local out
	out="$("$@" 2>&1)"
	if echo "$out" | grep -q "$expect"; then
		RESULTS+=("OK      $name")
	else
		RESULTS+=("FALLÓ   $name")
		FAILED+=("$name")
		echo "=== $name ==="; echo "$out" | tail -25
	fi
}

"$GODOT" --headless --path . --import > /dev/null 2>&1

run "datos (validate_data)"      "VALIDACION OK"   "$GODOT" --headless --path . res://tests/validate_data.tscn
run "reglas (rules_test)"        "REGLAS OK"       "$GODOT" --headless --path . res://tests/rules_test.tscn
run "simulación (300 partidas)"  "SIMULACION OK"   "$GODOT" --headless --path . res://tests/simulate.tscn
run "voz (voice_test)"           "VOZ OK"          "$GODOT" --headless --path . res://tests/voice_test.tscn
run "en línea: partidas"         "ONLINE OK (full)"  env GAMES=2 TIMEOUT=90 bash tests/run_online_test.sh
run "en línea: uno se va"        "ONLINE OK (leave)" env TIMEOUT=60 bash tests/run_online_test.sh leave
run "en línea: mensajes inválidos" "ONLINE OK (abuse)" env TIMEOUT=60 bash tests/run_online_test.sh abuse
run "en línea: un jugador aloja"  "ONLINE OK (host)"  env GAMES=2 TIMEOUT=90 bash tests/run_online_test.sh host

if [ -z "$HEADLESS_ONLY" ]; then
	run "mesa (ui_smoke, español)"           "UI OK"    "$GODOT" --path . res://tests/ui_smoke.tscn
	run "mesa (ui_smoke, inglés 4:3)"        "UI OK"    env TEST_LANG=en TEST_ASPECT=4:3 "$GODOT" --path . res://tests/ui_smoke.tscn
	run "mesa (ui_smoke, Lo Indefendible)"   "UI OK"    env TEST_MODE=indefendible "$GODOT" --path . res://tests/ui_smoke.tscn
	run "menús (menu_smoke)"                 "MENU OK"  "$GODOT" --path . res://tests/menu_smoke.tscn
	run "cartas (cards_preview)"             "CARTAS OK" "$GODOT" --path . res://tests/cards_preview.tscn
	run "vista 3D (stage_preview)"           "PREVIEW OK" "$GODOT" --path . res://tests/stage_preview.tscn
	run "en línea con ventana (online_ui)"   "ONLINE UI OK" env BOT_TIMEOUT=60 bash tests/run_online_ui_test.sh
fi

echo
echo "================ RESUMEN ================"
printf '%s\n' "${RESULTS[@]}"
if [ ${#FAILED[@]} -eq 0 ]; then echo "TODO OK"; exit 0; else echo "HAY ${#FAILED[@]} PRUEBA(S) CON FALLOS"; exit 1; fi
