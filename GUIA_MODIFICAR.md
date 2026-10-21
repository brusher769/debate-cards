# Guía para modificar Debate de Cartas

Ejemplos concretos para tocar cartas, comodines, preguntas, reglas y apariencia sin tocar código.
Las reglas del juego están en [REGLAS_DEBATE.md](REGLAS_DEBATE.md); para entender por qué el código
está armado así, ver [CLAUDE.md](CLAUDE.md); lo que se decidió donde las reglas no decían nada,
está en [DECISIONES.md](DECISIONES.md).

Después de cualquier cambio, corre el validador para asegurarte de que no rompiste nada:

```bash
godot --headless --path . res://tests/validate_data.tscn
```

y, si tocaste textos de cartas, mira que sigan cabiendo en la carta (necesita ventana):

```bash
godot --path . res://tests/cards_preview.tscn
```

## Cambiar los números de las reglas

Todo vive en `data/config.json`, con los mismos nombres que en el apartado 14 de las reglas. Si el
archivo no existe o le falta una clave, el juego usa el valor por defecto (los de hoy), así que
nunca se rompe por un cambio a medias.

| Clave | Qué controla |
|---|---|
| `cartas_normales_por_mano` | cartas normales (distintas) que recibe cada debatiente |
| `comodines_por_mano` | comodines que recibe cada debatiente |
| `monedas_iniciales` / `monedas_maximas` | monedas de inicio y tope al empezar (5 + monedas de sobornos) |
| `costo_cambiar_comodin` | monedas que cuesta cambiar el comodín por otro al azar |
| `costo_lupa_comodin_extra` | monedas que cuesta el comodín extra de la Lupa |
| `duracion_turno_seg` | segundos de cada intervención |
| `ventana_respuesta_comodin_seg` | segundos que tiene el rival para responder a un comodín |
| `end_min_puntos` / `end_min_minutos` | para poder usar END: puntos propios, o minutos de partida |
| `juez_puede_terminar_minutos` | pasado este tiempo el juez puede terminar la partida |
| `tiempo_interrogar_respuesta_seg` | segundos para responder Interrogar, Definición y Desafío |
| `puntos_juez` | los únicos puntajes del juez: `[5, -2, -1]` |
| `penalizacion_max_con_soborno` | lo máximo que el juez puede quitarle a quien lo sobornó |
| `penalizacion_veredicto_fallido` | puntos que recibe quien juega Veredicto sin haber soborno |
| `apelacion_opciones_seg` | tiempos extra que el juez puede conceder con Apelación |
| `refutacion_cadena_max` | máximo de Refutar seguidas |
| `inocente_perdida_max` | lo máximo que se puede perder mientras Inocente está activo |

Los textos de las cartas y de la guía usan marcadores como `{end_points}` o `{pass_rival}`, así que
si cambias un número, el texto de la carta se actualiza solo la próxima vez que arranque una
partida.

## Agregar una carta normal

Edita `data/cards.json` y agrega un objeto a la lista `normal`. El `id` no se puede repetir.
Cada mano recibe `cartas_normales_por_mano` cartas **distintas**, así que siempre debe haber al
menos ese número de cartas normales en total (el validador lo revisa).

**De puntaje libre** (el juez da +5, -2 o -1):

```json
{ "id": "anecdota", "name": "Anécdota", "name_en": "Anecdote", "scoring": "free", "timing": "turn", "effect": "speak",
  "text": "Cuentas algo que te pasó y apoya tu postura.", "text_en": "You tell something that happened to you and supports your position." }
```

**De decisión** (el juez solo dice «procede» o «no procede» y los puntos son fijos; `self` es
quien juega la carta y `rival` su rival):

```json
{ "id": "dilema", "name": "Dilema", "name_en": "Dilemma", "scoring": "decision", "timing": "turn", "effect": "decision",
  "pass": { "self": 1, "rival": -1 }, "fail": { "self": -2, "rival": 0 },
  "text": "Planteas un dilema. Procede: rival {pass_rival}, tú {pass_self}. No procede: tú {fail_self}.",
  "text_en": "You pose a dilemma. Upheld: rival {pass_rival}, you {pass_self}. Overruled: you {fail_self}." }
```

Campos útiles:

- `timing`: `"turn"` (se juega en tu turno) o `"interrupt"` (durante la intervención del rival,
  como Refutar y Objeción).
- `effect`: `speak` (hablas y el juez puntúa), `decision`, `refute`, `objection` o `appeal`.
  Estos son los comportamientos que el motor ya sabe ejecutar.
- `answer: true`: tras hablar, el rival tiene `tiempo_interrogar_respuesta_seg` para responder
  (como Interrogar).
- `seconds`: duración propia de la intervención (por defecto `duracion_turno_seg`).
- Marcadores en `text`: `{pass_self}`, `{pass_rival}`, `{fail_self}`, `{fail_rival}` y los de
  `config.json` (`{turn_seconds}`, `{answer_seconds}`, `{end_points}`...; lista completa en
  `Config.markers()` de `scripts/core/config.gd`).

Para **cambiar un valor** (por ejemplo, que Incriminación quite 3 en vez de 2) solo cambia el
número en `pass`/`fail`: el texto de la carta se actualiza solo.

## Agregar un comodín (por ejemplo el 12 y el 13)

Agrega un objeto a la lista `wild`. Un comodín usa uno de los efectos que el motor ya conoce
(`effect`) con sus propios textos y parejas de respuesta:

```json
{ "id": "cautela_fuerte", "name": "Cautela fuerte", "name_en": "Strong caution", "effect": "block", "timing": "turn",
  "answerable_by": ["cancel"],
  "text": "Bloqueas el siguiente turno del rival. Solo Impugnación lo detiene.",
  "text_en": "You block the rival's next turn. Only Challenge ruling stops it." }
```

| `effect` | Qué hace |
|---|---|
| `bribe` | Soborno (`params.lose_cards`: cartas que pierde quien soborna) |
| `verdict` | Veredicto |
| `steal` | Roba una carta normal al azar |
| `block` | Bloquea el siguiente turno del rival (Cautela) |
| `innocent` | Protege del bloqueo y limita las pérdidas (`params.duration_turns`) |
| `secret` | Solo como respuesta: anula un robo |
| `cancel` | Impugnación: anula un comodín (como respuesta) o los beneficios activos del rival |
| `contempt` | Desacato: la próxima resolución del juez sobre ti pasa al rival |
| `precedent` | Jurisprudencia |
| `end` | END |
| `peek` | Lupa |

- `timing`: `"turn"` (en tu turno, antes de tu carta normal), `"any"` (en cualquier momento, como
  Veredicto) o `"none"` (solo como respuesta, como Secreto).
- `answerable_by`: qué efectos de comodín del rival pueden responderle durante la ventana de
  respuesta (`[]` = no se puede responder, como END). Impugnación (`"cancel"`) suele estar en todos.
- Un efecto **totalmente nuevo** (que no esté en la tabla) sí necesita código en
  `scripts/core/debate_engine.gd` (`_apply_wild`); el validador te avisa si escribes uno que no
  existe.

Si quieres que un comodín aparezca más seguido no hace falta nada especial: cada mano recibe uno
al azar de toda la lista.

## Quitar una carta

Borra su objeto de `data/cards.json`. Si quitas cartas normales, revisa que sigan alcanzando para
repartir manos (el validador te avisa).

## Ponerle imagen a una carta

1. Copia tu imagen (PNG o JPG) dentro de `assets/cards/`.
2. En la carta, agrega el campo `"image"` con la ruta `res://`:

```json
{ "id": "ejemplo", "name": "Ejemplo", "scoring": "free", "timing": "turn", "effect": "speak",
  "text": "Presentas un ejemplo concreto.", "image": "res://assets/cards/ejemplo.png" }
```

3. Corre `godot --headless --path . --import` una vez para que Godot importe la imagen nueva
   (si vas a abrir el editor igualmente, esto lo hace solo).

## Agregar preguntas

Hay un archivo por modo:

- `data/topics_normal.json`: preguntas muy random y polémicas pero graciosas. Cada debatiente
  elige en secreto «De acuerdo» o «En desacuerdo»; si eligen lo mismo no hay debate y sale otra.
- `data/topics_indefendible.json`: preguntas muy difíciles de defender, pero no imposibles. Aquí
  el juego reparte las posturas al azar: puede tocarte defender algo que no compartes.

Agrega un objeto a la lista `topics`, con la frase en español (`es`) y en inglés (`en`):

```json
{ "es": "¿Los helados de vainilla son mejores que los de chocolate?", "en": "Is vanilla ice cream better than chocolate?" }
```

Conviene que cada pregunta se pueda contestar con acuerdo o desacuerdo, y que no ataque a grupos de
personas. No repitas el texto exacto de una que ya esté (el validador lo marca). También se acepta
un texto suelto entre comillas: se muestra igual en todos los idiomas.

## Idioma, opciones y guía del menú

El juego arranca en el **menú principal** (Entrar a la sala, Cómo jugar, Opciones, Salir).

- **Opciones** guarda idioma, relación de aspecto (Automática, 16:9, 16:10, 4:3, 21:9), pantalla
  completa y volumen en un archivo del usuario (`user://settings.cfg`; en Windows,
  `%APPDATA%\Godot\app_userdata\Debate de Cartas\settings.cfg`). Borrar ese archivo restaura todo.
- Los textos de la interfaz (menús, botones, mensajes de la partida, la guía) están en
  `data/i18n.json`, un bloque por idioma con las **mismas claves**. Para cambiar una frase, edita
  su valor en cada idioma; los `%s` y `%d` los rellena el código, no los quites ni los cambies de
  orden.
- **La guía «Cómo jugar»** son las claves `HELP_1_TITLE`, `HELP_1_BODY`, `HELP_2_TITLE`... de ese
  mismo archivo. Dentro del texto puedes usar los marcadores de `Config.markers()` (por ejemplo
  `{turn_seconds}`, `{coins_start}`, `{end_points}`): se reemplazan por los números de
  `data/config.json`. Para agregar una página, suma las dos claves en cada idioma y sube `PAGES`
  en `scripts/ui/tutorial.gd`.
- **Agregar un idioma** (por ejemplo portugués, `pt`): agrégalo a `LANGUAGES` en
  `scripts/core/settings.gd` (`"pt": "Português"`), copia el bloque `"es"` de `data/i18n.json` como
  `"pt"` y tradúcelo, y agrega `name_pt`/`text_pt` a las cartas y `"pt"` a las preguntas. El
  validador te dice qué falta.
- **Volumen**: controla el volumen general (bus Master). Hoy el juego no tiene música ni efectos;
  al mover el control suena un tono corto de prueba. Cuando agregues sonidos, este control ya
  los afecta.

## Cambiar colores y cámaras

Todo está agrupado al inicio de `scripts/ui/stage_3d.gd`, bajo el comentario
`AJUSTES VISUALES`:

- `PLAYER_COLORS`: color de cada jugador (posición 0, 1, 2 según el orden de la sala).
- `SEAT_POS` / `SEAT_YAW`: dónde se sienta cada asiento y hacia dónde mira.
- `TABLE_SIZE`: ancho x profundidad del tablero de la mesa.
- `SLOT_X` / `SLOT_Z`: dónde caen sobre la mesa la última carta normal y el último comodín de cada
  jugador.
- `VIEWS`: posición y punto de mira de cada cámara (`overview`, `table`, `judge`, `hand_0`,
  `hand_1`).
- `HAND_SPACING` / `HAND_MAX_WIDTH`: separación de las cartas de la mano.

Cambia los valores, guarda, y revisa el resultado con:

```bash
SHOT_DIR=capturas godot --path . res://tests/stage_preview.tscn
```

(crea la carpeta `capturas` antes, o cambia la ruta; no necesita `--headless` porque genera
mallas 3D reales).

## Reemplazar las figuras por modelos propios

Las tres figuras (dos debatientes y el juez) se arman por código en
`Stage3D._build_figure(seat: int)`, con primitivas (cajas, cápsulas, esferas). Para usar tus
propios modelos `.glb`/`.gltf`:

1. En `_build_figure()`, en vez de armar el cuerpo con `_box()` / `_add_mesh()` con
   `CapsuleMesh`/`SphereMesh`, carga tu escena con `load("res://assets/.../figura.glb").instantiate()`
   y agrégala a `root`.
2. Conserva estas tres cosas que el resto del código espera de vuelta en el diccionario:
   - `"body_mat"`: un `StandardMaterial3D` cuyo `albedo_color` se recolorea según el jugador
	 (`set_roles()` lo hace solo). Si tu modelo trae su propio material, duplícalo
	 (`material.duplicate()`) y devuélvelo aquí.
   - `"plate"`: un `Label3D` con el nombre y rol del jugador flotando sobre la figura.
   - `"ring"`: el anillo de luz que se prende bajo quien está actuando (puede ser el mismo
	 `MeshInstance3D` que ya arma el código, solo re-posiciónalo si tu modelo es más alto o más
	 bajo que la cápsula actual).
3. `root.position` y `root.rotation.y` ya los pone `_build_figure()` con `SEAT_POS`/`SEAT_YAW`:
   no hace falta tocarlos.

## Automatizar al juez (por ejemplo con una IA)

El juez no es una clase aparte: es un jugador más del motor y lo único que hace son cuatro
acciones (`scripts/core/debate_engine.gd`, arriba del archivo). Un juez automático solo tiene que
mirar `engine.phase` y responder con `engine.apply(...)`:

```gdscript
match engine.phase:
	DebateEngine.Phase.RESOLVE:
		var card: CardData = engine.current_unit()["card"]
		if card.scoring == CardData.Scoring.DECISION:
			engine.apply({"type": "decide", "player": engine.judge.index, "passes": true})
		else:
			engine.apply({"type": "score", "player": engine.judge.index, "points": 5})
	DebateEngine.Phase.APPEAL:
		engine.apply({"type": "appeal_time", "player": engine.judge.index, "seconds": 30})
	DebateEngine.Phase.BRIBE:
		engine.apply({"type": "bribe_decision", "player": engine.judge.index, "accept": false})
```

Para que la mesa no muestre los botones del juez, ocúltalos en `_show_resolve()`,
`_show_appeal()` y `_reveal_bribe()` de `scripts/ui/table.gd` y llama al código de arriba desde
`_sync()`.

## Jugar en línea con amigos

En el menú principal, **Jugar en línea**. Cada jugador escribe su nombre y la dirección del
servidor (`dirección:puerto`, o una URL como `wss://debate-cards.onrender.com`); uno pulsa **Crear sala** y les pasa el código de 4 letras a los otros
dos, que lo escriben y pulsan **Unirse a la sala**. Cuando están los tres, quien creó la sala
pulsa **Empezar partida**. Hay chat de texto y un interruptor de micrófono.

**¿Qué servidor?** Tres formas:

1. **Uno de ustedes aloja la sala**: al crearla marca «Alojar la sala en este PC»; el juego muestra
   la dirección (por ejemplo `192.168.1.20:7777`) a la que se conectan los demás. Si están en
   la misma casa/red basta con eso y con permitir el juego en el firewall de Windows. Si están en
   redes distintas, esa persona tiene que abrir el puerto TCP 7777 en su router, o usar una VPN
   de juegos (Tailscale, ZeroTier, Hamachi) y pasar la dirección de la VPN.
2. **Servidor dedicado** (por ejemplo un VPS barato con Linux): copia el proyecto (o el juego
   exportado), instala Godot sin ventana y déjalo corriendo:

   ```bash
   godot --headless --path . res://scenes/server.tscn -- --port=7777
   # con un juego exportado:  ./Debate --headless -- --server --port=7777
   ```

   Abre el puerto TCP 7777 en el firewall del servidor. Todos los jugadores usan la dirección
   pública del servidor. Puede atender varias salas a la vez.
3. **Render (gratis)**: el `Dockerfile` del proyecto ya lo deja listo; los pasos están en
   [DESPLIEGUE_RENDER.md](DESPLIEGUE_RENDER.md). Los jugadores escriben `wss://<nombre>.onrender.com`.

Cosas que conviene saber:

- Si alguien se desconecta en plena partida, la sala se cierra para todos (no hay reconexión).
- Todos deben tener las mismas cartas y reglas que el servidor (`data/cards.json` y
  `data/config.json`); la sala de espera avisa si no coinciden.
- **Voz**: el interruptor «Micrófono» solo funciona si activas «Enable Input»
  (`audio/driver/enable_input`) en Proyecto > Ajustes del proyecto > Audio > Driver y reinicias. Es
  experimental (sin cancelación de eco, mejor con auriculares); mientras tanto se puede jugar con
  voz externa. Detalles en [DECISIONES.md](DECISIONES.md).
- Para ver qué pasa en el servidor, corre el cliente o el servidor con la variable de entorno
  `NET_DEBUG=1`: imprime cada acción que se manda y se recibe.

## Abrir el proyecto en el editor, jugar y acomodar diseños

- **Importar**: en el gestor de proyectos de Godot, botón *Importar* y elige
  `E:\debate-cards\project.godot`.
- **Jugar todo el juego**: F5 (o el botón ▶ de arriba a la derecha). Arranca en el menú
  principal: *Entrar a la sala* → nombres → *Empezar partida*.
- **Ver y acomodar una pantalla sola**: abre la escena en el editor (doble clic en
  `scenes/main_menu.tscn`, `options.tscn`, `tutorial.tscn`, `lobby.tscn` o `table.tscn`) y pulsa
  F6 (*Ejecutar escena actual*). `table.tscn` crea sola una partida de prueba si la abres así.
- **Dónde está cada diseño**: los botones y paneles de la partida (barra de arriba, marcadores,
  botones de abajo, pantalla de relevo) están en `scenes/table.tscn`, dentro del nodo `HUD`; la
  carta en `scenes/ui/card_view.tscn`; la sala 3D (mesa, figuras, cámaras) se ajusta en
  `scripts/ui/stage_3d.gd`, en el bloque `AJUSTES VISUALES`.
- **Pestañas del editor**: `2D` es para los menús y el HUD (son escenas 2D). `3D` muestra la
  sala solo cuando tienes abierta `scenes/table.tscn` (se dibuja sola; las piezas se arman por
  código, así que no salen en el árbol de nodos ni se pueden mover con el mouse: se ajustan en
  `stage_3d.gd`). `Juego` muestra el juego mientras lo ejecutas con F5 o F6.
