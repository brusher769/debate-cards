# Debate de Cartas

Juego de debate con cartas para 3 personas (Godot 4.3 o superior, GDScript, renderer
`gl_compatibility`, pensado para un PC modesto con Windows). Dos debatientes defienden posturas
opuestas sobre una pregunta y juegan cartas por turnos; el tercero es el juez. Las reglas están en
[REGLAS_DEBATE.md](REGLAS_DEBATE.md) (fuente de verdad) y lo que se decidió donde no decían nada, en
[DECISIONES.md](DECISIONES.md). Se juega de dos maneras: **en una sola pantalla** (escena 3D con
pantalla de relevo entre jugadores) o **en línea** (cada jugador en su computador, servidor
autoritativo, chat y voz).

Si vas a **modificar cartas, comodines, preguntas, reglas o apariencia sin tocar código**, empieza por
[GUIA_MODIFICAR.md](GUIA_MODIFICAR.md). Este archivo es para entender por qué el juego está hecho
como está y cómo tocar el código con seguridad.

## Arquitectura

```
scripts/core/   Reglas del juego. Sin nada de interfaz (ni Control ni Node3D salvo autoloads).
scripts/net/    Juego en línea: Net (servidor y cliente) y la escena del servidor.
scripts/voice/  Voz (fase 5): códec y captura/reproducción, aislado del resto.
scripts/ui/     Interfaz: menús, HUD 2D, escena 3D, cartas físicas, chat.
scenes/         main_menu, lobby, online, options, tutorial, table, server (+ ui/ con card_view y player_panel).
data/           cards.json, topics_normal.json, topics_indefendible.json, config.json, i18n.json.
assets/cards/   Carpeta para tus imágenes de cartas (cards.json -> campo "image").
tests/          Pruebas (ver más abajo).
_reglas_anteriores/   Copia de las reglas de antes del cambio (Godot la ignora); se puede borrar.
```

Las carpetas siguen siendo las de siempre (`scripts/core` hace de `logic/` y `scripts/ui` de `ui/`).

`scripts/ui/stage_3d.gd` (la escena 3D) **no conoce las reglas**: solo recibe datos (jugadores,
cartas) y avisa con la señal `card_clicked`. `scripts/core/` **no conoce la interfaz**. Si te
encuentras queriendo romper esa regla, la lógica debería estar en `table.gd` (que sí conoce a ambos
y hace de puente).

### El motor de reglas (`scripts/core/debate_engine.gd`)

`DebateEngine` es una clase de lógica pura que lleva UNA partida:

- **Todo son acciones**: cada jugador manda un `Dictionary` (`{"type": "play_card", "player": 1,
  "card": "argumentar"}`) a `engine.apply(accion)`, que la valida y devuelve `{"ok", "error"}`. Si no
  es válida no cambia nada. La lista de acciones está al principio del archivo.
- **El tiempo** avanza con `engine.tick(delta)`: el motor lleva el reloj de la partida, el de cada
  intervención y la ventana de respuesta a comodines.
- **Lo que pasa sale como eventos** (`take_events()`): cada uno con `"to"` = `-1` (público) o el
  único jugador que lo ve (lo que te da la Lupa, la decisión del juez sobre tu soborno...).
- **Fases** (`engine.phase`): `STANCE -> STANCE_RESULT -> PLAY -> (SPEECH -> ANSWER -> RESOLVE) -> ...
  -> OVER`, con `RESPONSE`, `BRIBE` y `APPEAL` como pausas dentro de un turno. Una intervención
  (`_line`) es una carta jugada: se habla (`SPEECH`), a veces responde el rival (`ANSWER`) y decide
  el juez (`RESOLVE`); Refutar y Objeción se insertan en esa fila.
- **Información oculta**: `view_for(jugador)` y `snapshot_for(jugador)` devuelven solo lo que ese
  jugador puede saber. Las pruebas comprueban que la mano, monedas y comodín del rival nunca salen.
- **Motor espejo** (`DebateEngine.create_mirror` + `load_snapshot`): en línea el cliente reconstruye
  un motor con la foto que manda el servidor; no aplica reglas, así la misma mesa sirve en local y en
  línea.
- **Reglas en datos**: los números salen de `Config` (`data/config.json`) y las cartas de `CardData`
  (`data/cards.json`). El motor solo conoce *efectos* (`bribe`, `steal`, `block`...); un comodín
  nuevo con un efecto existente se agrega solo en el JSON.

Otras piezas de `scripts/core/`:

- **Config** (autoload): lee `data/config.json` con los mismos nombres del apartado 14 de las reglas
  y expone `Config.markers()`, los números que pueden usar entre llaves los textos de cartas y guía.
- **Settings** (autoload): idioma, relación de aspecto, pantalla completa y volumen, guardados en
  `user://settings.cfg` (`persist = false` desactiva el guardado; las pruebas lo usan). Registra las
  traducciones de `data/i18n.json` en `TranslationServer`.
- **GameState** (autoload): la sala de esta pantalla (jugadores, modo, partida en curso). En local
  usa un `GameRoom`; en línea guarda el motor espejo (`use_online`).
- **GameRoom**: 3 jugadores que juegan varias partidas seguidas: reparte los roles al azar, las
  monedas de sobornos no descubiertos y las preguntas del modo. La usan GameState y el servidor.
- **CardCatalog / CardData**: las 13 cartas normales y los comodines de `cards.json`. `CardData`
  reemplaza los marcadores `{...}` de los textos con los números de `Config` y de la propia carta.
- **PlayerData**: mano, comodines, monedas y efectos activos de un jugador.

### La mesa (`scripts/ui/table.gd`)

Une el motor con la escena 3D y el HUD; no tiene reglas propias. Cada vez que el motor avisa
(`changed`) redibuja según `engine.phase`. En **una pantalla** hay una pantalla de relevo
("Pásale el control a X") antes de cada mano o decisión privada, y el reloj del motor se detiene
mientras está a la vista. En **línea** (`GameState.is_online()`) no hay relevo: cada uno ve su mano
si es su turno y un aviso de a quién se espera si no lo es, y las acciones van a `Net.send_action`.

### El juego en línea (`scripts/net/net.gd`, autoload `Net`)

Multijugador de alto nivel de Godot (ENet/UDP). El mismo script corre en el servidor y en los
clientes; `c_*` son funciones que el cliente manda al servidor y `s_*` las que el servidor manda a
los clientes.

- **Servidor autoritativo**: tiene las salas (cada una con su `GameRoom` y su `DebateEngine`),
  valida cada acción con el motor y **pone él el índice del jugador** (nadie puede actuar por otro).
  A cada jugador le manda su foto (`snapshot_for`) y solo los eventos que puede ver.
- **Sala con código** de 4 letras, 3 jugadores por sala; el anfitrión (quien la creó) empieza cada
  partida y los roles se reparten al azar entre partidas de la misma sala. Si alguien se va en plena
  partida, la sala se cierra para todos (no hay reconexión).
- **Tres formas de jugar**: servidor dedicado (`godot --headless --path . res://scenes/server.tscn
  -- --port=7777`, o `Debate.exe --headless -- --server`), o un jugador que aloja desde el propio
  juego («Alojar la sala en este PC»), y los demás se conectan a su dirección.
- **Chat** (`chat_panel.gd`): mensajes de texto reenviados por el servidor a la sala.
- **Voz** (`scripts/voice/`, autoload `Voice`): códec μ-law 16 kHz (`voice_codec.gd`) y captura del
  micrófono con reenvío por el servidor. La red y el códec están probados; **el micrófono real no**
  (ver la cabecera de `voice_chat.gd` para lo que falta).

### Piezas de `scripts/ui/`

- **main_menu.gd / lobby.gd / online.gd / options.gd / tutorial.gd**: las pantallas de menú.
  `online.gd` es la conexión, la sala de espera y el paso a la mesa. `tutorial.gd` muestra páginas
  `HELP_n_TITLE`/`HELP_n_BODY` de `i18n.json` con los números de `Config.markers()`.
- **stage_3d.gd**: la sala, la mesa, las tres figuras, las cartas y la cámara. Construida por
  código con primitivas — ver el banner "AJUSTES VISUALES" al inicio del archivo antes de tocar
  colores, cámaras, tamaño de mesa o posiciones.
- **card_3d.gd**: la carta física en 3D. Su cara es `card_view.tscn` (un Control 2D) dibujada en
  un `SubViewport`, así el diseño de la carta se define una sola vez y sirve para 2D y 3D.
- **card_view.gd** / **card_view.tscn**: el dibujo de una `CardData` (categoría, nombre, texto).

## Datos que se editan sin tocar código

- **data/config.json**: los parámetros del apartado 14 de las reglas (ver GUIA_MODIFICAR.md). Si falta
  el archivo o una clave, `Config` usa el valor por defecto que trae el propio script.
- **data/cards.json**: listas `normal` (13 cartas) y `wild` (comodines, caben más). Ver GUIA_MODIFICAR.md.
- **data/topics_normal.json / topics_indefendible.json**: las preguntas de cada modo.
- **data/i18n.json**: textos de interfaz y de la guía por idioma. Las cartas llevan `name_en`/`text_en`
  y las preguntas `{"es", "en"}` en sus propios JSON.

## Cómo correr las pruebas

Necesitas Godot 4.3 o superior (se probó con 4.6.1). Sustituye `godot` por la ruta a tu ejecutable
(en Windows, el `_console.exe` muestra la salida en el terminal).

```bash
# Después de crear o renombrar scripts con class_name, o de tocar assets:
godot --headless --path . --import

# Datos: cards.json, topics_*.json, config.json e i18n.json (español, dice archivo e id) y que toda
# clave de traducción que usa el código exista. Los textos en inglés que falten salen como AVISO.
godot --headless --path . res://tests/validate_data.tscn

# Reglas sin pantalla: una comprobación por cada carta, comodín y condición de fin, más el motor
# espejo y la información oculta. Imprime "REGLAS OK (n comprobaciones)".
godot --headless --path . res://tests/rules_test.tscn

# 300 partidas de bots con acciones legales al azar: nunca deben atascarse. "SIMULACION OK".
godot --headless --path . res://tests/simulate.tscn

# Voz sin micrófono: el códec y la reproducción. "VOZ OK".
godot --headless --path . res://tests/voice_test.tscn

# En línea, sin pantalla (Git Bash): un servidor real y 3 bots que juegan por red. Escenarios:
# (nada) partidas completas con chat y voz, "leave" (uno se va) y "abuse" (mensajes inválidos).
GODOT=/ruta/a/godot bash tests/run_online_test.sh
```

`ui_smoke`, `menu_smoke`, `stage_preview`, `cards_preview` y `online_ui_smoke` necesitan render real:
**NO** uses `--headless` (ese modo no crea mallas 3D). En Windows basta con
`godot --path . res://tests/ui_smoke.tscn` — se abre una ventana y se cierra sola.

- `ui_smoke` juega una partida entera en una pantalla con clics sobre las cartas 3D (posturas,
  comodines, respuestas, interrupciones, soborno privado, Apelación...). Acepta `TEST_LANG=en`,
  `TEST_ASPECT=4:3` (o 16:10, 21:9) y `TEST_MODE=indefendible`. Imprime "UI OK".
- `menu_smoke` recorre el menú, opciones, la guía y la sala. Imprime "MENU OK".
- `cards_preview` comprueba que el texto de las 24 cartas quepa en la carta (es y en).
- `stage_preview` recorre las cámaras 3D y guarda capturas.
- `tests/run_online_ui_test.sh`: un servidor, dos bots y UNA ventana que hace de jugador humano
  contra ellos (crea la sala desde la pantalla «Jugar en línea» y juega con clics). "ONLINE UI OK".

Con la variable de entorno `SHOT_DIR` las pruebas con pantalla guardan una captura de cada estado.
Las pruebas ponen `Settings.persist = false`, así que **no tocan tus ajustes guardados**.

Todas las pruebas son **escenas**, no scripts sueltos con `--script`: así ven los autoloads (`Config`,
`GameState`, `Net`...), que un script corrido con `--script` no tiene.

## Trampas conocidas

- **Un error en `printerr` de una prueba no falla la prueba**: mira también las líneas `ERROR:` de la
  salida (por ejemplo un texto con más `%s` que argumentos solo imprime un error de Godot).
- **Orden de autoloads**: `Config`, `Settings`, `GameState`, `Net`, `Voice` en `project.godot`
  (`[autoload]`), porque `CardData`/`GameRoom` leen `Config` y `Settings.language`, `Net` usa
  `GameState` y `Voice` usa `Net`. Si agregas otro autoload que dependa de ellos, ponlo después.
- **Traducciones**: una clave que falta en `i18n.json` se ve cruda en pantalla; el validador revisa
  que es/en tengan las mismas claves y los mismos `%s`/`%d`/`{llaves}`, que los `{marcadores}` existan
  en `Config.markers()` y que toda clave usada en `tr("...")` o en un `text = "..."` de una escena
  exista. En código de reglas (sin `Node`) usa `TranslationServer.translate("CLAVE")`; en un `Node`
  basta `tr("CLAVE")`. Un `%` literal dentro de un texto que pase por `%` de GDScript debe escribirse
  `%%`. Los mensajes de error del servidor (`s_error`) salen en español.
- **Textos de cartas**: el tamaño físico de la carta es fijo (`Card3D.SIZE = Vector2(0.5, 0.7)`, cara a
  320x430). Un texto largo se recorta con «…»: `tests/cards_preview.tscn` lo detecta.
- **Señales de red y escenas**: conecta las señales de `Net` a *métodos* del nodo, no a lambdas: cuando
  el nodo se libera, Godot desconecta el método pero no una lambda (y el siguiente mensaje daría error).
- **`--headless --import` es obligatorio tras crear o renombrar un script con `class_name`**: si
  no, Godot no lo reconoce como clase global y las pruebas fallan con errores de tipo raros.
- **Las imágenes nuevas necesitan importarse antes de poder cargarse con `load()`**: corre
  `godot --headless --path . --import` una vez (el editor de Godot lo hace solo).
- **Ajustes guardados**: viven en `user://settings.cfg`, fuera del proyecto. Si una prueba se
  comporta raro con otro idioma o proporción, revisa que ponga `Settings.reset_to_defaults(false)`.
- **Sin sonido todavía**: el control de volumen ajusta el bus Master, pero el juego no tiene música ni
  efectos; al mover el control solo suena un tono de prueba. La voz en línea sí suena por ese bus.
- **Micrófono**: para abrirlo hay que activar `audio/driver/enable_input` en los Ajustes del proyecto
  y reiniciar; por defecto está apagado para no pedir permisos a quien solo juega en una pantalla.
