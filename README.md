# Debate de Cartas

Juego de debate con cartas para 3 personas (Godot 4, GDScript, renderer `gl_compatibility`): dos
debatientes defienden posturas opuestas y juegan cartas por turnos; el tercero es el juez. Las
reglas completas están en [REGLAS_DEBATE.md](REGLAS_DEBATE.md).

## Cómo ejecutarlo

1. Abre `project.godot` con Godot 4.3 o superior (se probó con 4.6.1).
2. Pulsa **F5**. Arranca en el menú principal: *Entrar a la sala* → escribe los 3 nombres → elige
   el modo → *Empezar partida*. Es en una sola pantalla: aparece un aviso para pasar el control
   antes de cada mano, para que nadie vea las cartas de otro.

## Jugar en línea

Desde el menú, **Jugar en línea**: cada jugador entra desde su computador, uno crea la sala y
pasa el código a los otros dos. Hace falta un servidor:

```bash
godot --headless --path . res://scenes/server.tscn -- --port=7777
```

(en Render gratis, ver [DESPLIEGUE_RENDER.md](DESPLIEGUE_RENDER.md); en un VPS; o en el PC de un
amigo con el puerto TCP 7777 abierto). También se puede marcar
«Alojar la sala en este PC» al crearla y los demás se conectan a esa dirección. La sala tiene chat
de texto y un interruptor de micrófono (ver [DECISIONES.md](DECISIONES.md) sobre la voz).

## Qué se puede cambiar sin tocar código

Cartas, comodines, preguntas, números de las reglas y textos: ver
[GUIA_MODIFICAR.md](GUIA_MODIFICAR.md). Para entender cómo está armado el código, ver
[CLAUDE.md](CLAUDE.md), y para saber qué se decidió donde las reglas no decían nada,
[DECISIONES.md](DECISIONES.md).

## Pruebas

Sustituye `godot` por la ruta a tu ejecutable.

```bash
GODOT=/ruta/a/godot bash tests/run_all.sh                # todas, una tras otra, con resumen final
```

O una por una:

```bash
godot --headless --path . --import                      # tras crear scripts con class_name
godot --headless --path . res://tests/validate_data.tscn # revisa los JSON
godot --headless --path . res://tests/rules_test.tscn    # reglas: cada carta y comodín
godot --headless --path . res://tests/simulate.tscn      # 300 partidas de bots
godot --headless --path . res://tests/voice_test.tscn    # códec de voz
GODOT=/ruta/a/godot bash tests/run_online_test.sh        # servidor + 3 clientes por red (localhost)
godot --path . res://tests/ui_smoke.tscn                 # la mesa 3D (necesita ventana)
godot --path . res://tests/menu_smoke.tscn               # menús y opciones (necesita ventana)
godot --path . res://tests/cards_preview.tscn            # que el texto de las 24 cartas quepa
```
