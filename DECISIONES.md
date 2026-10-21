# Decisiones

Aquí se anotan los huecos que tenía `REGLAS_DEBATE.md` y qué se decidió (siempre lo más simple),
más las decisiones de arquitectura. Todo lo marcado como **Regla** se puede cambiar en los datos
(`data/config.json`, `data/cards.json`); lo marcado como **Código** vive en
`scripts/core/debate_engine.gd`.

## Arquitectura

- **Se mantuvo lo que ya existía**: la escena 3D de la mesa, los menús, las opciones (idioma,
  relación de aspecto, volumen), el flujo de posturas y la pantalla de relevo. Solo se
  reemplazaron las reglas (turnos, cartas, comodines, monedas, soborno) y lo que dependía de
  ellas. El prompt pedía interfaz 2D sin 3D; como la sala 3D ya estaba hecha y funcionando se
  conservó (`Stage3D` no conoce las reglas, así que se puede cambiar por una vista 2D sin tocar
  el motor).
- **Carpetas**: se conservó `scripts/core` (reglas), `scripts/ui` (interfaz), `scenes`, `data` y
  `tests` en vez de crear `logic/` y `ui/` nuevas. Equivalencias con el prompt:
  `logic/` = `scripts/core/`, `ui/` = `scripts/ui/`.
- **Motor de reglas puro** (`DebateEngine`): no usa nodos. Todo lo que hace un jugador es una
  *acción* (un `Dictionary`); `apply(accion)` la valida y devuelve `{"ok", "error"}`; los
  resultados salen como *eventos* (cada uno con `"to"`: `-1` público, o el único jugador que lo
  ve). `view_for(jugador)` devuelve solo lo que ese jugador puede saber. Así el servidor de la
  fase online puede reutilizar el motor tal cual.
- **Datos en JSON**: cartas normales y comodines (`data/cards.json`), preguntas de cada modo
  (`topics_normal.json`, `topics_indefendible.json`) y los parámetros del apartado 14
  (`data/config.json`, con los mismos nombres que en las reglas).
- **Comodines 12 y 13 sin cambiar código**: un comodín nuevo es un objeto más en la lista
  `wild` de `cards.json`. Puede reutilizar cualquiera de los efectos que el motor ya conoce
  (`bribe`, `steal`, `block`...) con otros números, textos o parejas de respuesta
  (`answerable_by`). Un efecto totalmente nuevo sí necesita código; el validador avisa.
- **Jugador `PlayerData`**: guarda mano, comodines, monedas y efectos activos. El juez es un
  `PlayerData` más, sin cartas.
- **Se quitó** `Judge` / `HumanJudge` / `RoundManager` / `Scoring` / `Deck`: eran de las reglas
  anteriores. Copia de respaldo en `_reglas_anteriores/` (Godot la ignora por su `.gdignore`;
  puedes borrarla cuando quieras). Un juez de IA futuro solo tendría que mandar las acciones
  `score`, `decide`, `bribe_decision` y `appeal_time` del juez.

## Huecos de las reglas

Turnos y cartas normales

- **Turno bloqueado (Cautela)**: el turno del rival se pierde por completo (no habla ni puntúa) y
  juega otra vez quien puso la Cautela. *Código.*
- **Sin cartas para jugar**: el fin por «sin cartas» se comprueba al empezar el turno de alguien.
  Cuenta como «sin carta jugable» quien solo conserva Refutar y/o Objeción (esas cartas solo se
  juegan durante la intervención del rival, no en tu turno). También se comprueba justo después
  de un Soborno aceptado (te quita 2 cartas a mitad de tu turno). *Código.*
- **Refutar y Objeción cuentan como el turno de quien las juega**: no se puede refutar en tu
  propio turno. Tras una Refutar, habla quien refutó (1 min) y el siguiente turno es del
  interrumpido; así los turnos siempre se alternan. La cadena máxima es 2 Refutar seguidas
  (`refutacion_cadena_max`). *Regla + código.*
- **Objeción procedente**: quien objetó toma la palabra 1 minuto sin gastar otra carta. Esa
  palabra **no la puntúa el juez** y cuenta como su turno. La intervención interrumpida sí la
  puntúa el juez (por lo que alcanzó a decir). *Código.*
- **Objeción no procedente**: quien objetó pierde 1 y la intervención del rival sigue con el
  tiempo que le quedaba.
- **Interrupciones**: la intervención interrumpida se cierra y la puntúa el juez antes de que
  hable quien interrumpió.
- **Apelación**: se juega como carta del turno; el juez concede 0, 30 o 60 s extra
  (`apelacion_opciones_seg`) que se suman a `duracion_turno_seg`, y después puntúa.
- **Interrogar, Definición y Desafío**: los tres piden respuesta del rival tras hablar, con
  `tiempo_interrogar_respuesta_seg` (30 s) cada uno (las reglas solo fijan el tiempo de Interrogar).
  Incriminación y Trampa lógica no tienen fase de respuesta.
- **Turno con Jurisprudencia**: gasta el turno entero. Solo se puede jugar si ya jugaste alguna
  carta normal (si no, no hay nada que repetir). Si en tu siguiente turno estás bloqueado, se
  pierde la repetición.

Comodines

- **Ventana de respuesta**: se abre **siempre** que se juega un comodín (salvo END), aunque el
  rival no tenga nada compatible, para que abrirla o no nunca delate lo que tiene. Dura
  `ventana_respuesta_comodin_seg`. Con pantalla compartida, el reloj se detiene mientras se pasa
  el control.
- **Cuándo se juega cada comodín** (`timing` en `cards.json`): `turn` = en tu turno antes de tu
  carta normal; `any` = en cualquier momento (Veredicto, también durante la intervención del
  rival); `none` = solo como respuesta (Secreto). Inocente, Impugnación y los demás con `turn`
  también valen como respuesta si aparecen en el `answerable_by` del comodín del rival.
- **Comodín contra comodín**: la respuesta actúa primero. Impugnación anula el comodín del rival;
  Inocente lo hace inútil contra Cautela; Secreto contra Robar carta; Veredicto como respuesta a
  un Soborno se evalúa cuando el juez decide.
- **Soborno**: el monto es de 1 a tus monedas. Si el juez **rechaza**, no se pierde nada (las
  monedas vuelven a quien sobornó). Si **acepta**: las monedas pasan al juez, quien sobornó pierde
  2 cartas al azar (`params.lose_cards`) y desde ese momento el juez no puede bajarle más de
  `penalizacion_max_con_soborno` por intervención (el tope se aplica a todo lo que decide el
  juez sobre él, también a decisiones como Incriminación fallida). El rival ve que se jugó
  Soborno pero no el monto ni la decisión, y tampoco cuántas monedas ni cuántas cartas tiene
  cada uno (por eso la interfaz no muestra las cartas ni monedas del rival).
- **Monedas del soborno**: si nadie descubre el soborno, el juez las guarda (`PlayerData.bank`) y,
  cuando le toque debatir, empieza con `monedas_iniciales` + esas monedas, máximo `monedas_maximas`.
  Si sigue siendo juez, las conserva. Si lo descubren (Veredicto acertado) las pierde.
- **Veredicto**: solo cuenta un soborno aceptado **del rival**. Si el que lo juega fue quien
  sobornó, falla. El descuento de `penalizacion_veredicto_fallido` lo limita Inocente (dice
  «cualquier pérdida») pero no el escudo del Soborno (ese solo actúa sobre lo que decide el juez).
- **Inocente**: dura hasta que termina el siguiente turno del rival (2 turnos contando el actual),
  `params.duration_turns`. Protege de Cautela (si la Cautela se juega mientras Inocente está
  activo) y limita cualquier pérdida a `inocente_perdida_max`.
- **Desacato**: la primera resolución del juez que le dé puntos (buenos o malos) al que lo jugó
  se los lleva el rival. Se aplica antes del tope de Inocente del que los recibe.
- **Impugnación proactiva** (en tu turno, sin ser respuesta): elimina Inocente, Desacato y una
  Jurisprudencia pendiente del rival, y un bloqueo sobre ti. No toca el escudo de un Soborno
  aceptado.
- **Robar carta**: roba una carta normal al azar (puede darte una repetida); si el rival no tiene,
  no pasa nada.
- **Lupa**: la compra del comodín extra se decide al jugarla (casilla «comprar extra»); el extra
  nunca es otra Lupa (evita cadenas infinitas).
- **Cambiar comodín**: solo en tu turno (antes de jugar tu carta), si no has jugado ningún comodín.
- **END**: con `end_min_puntos` puntos propios o pasados `end_min_minutos` minutos de debate (el
  reloj empieza al empezar el primer turno, no cuenta la elección de posturas).
- **Terminar por el juez** (opcional): después de `juez_puede_terminar_minutos`, con un botón que
  solo aparece mientras alguien habla.
- **Empate**: si los puntos son iguales, la pantalla dice «Empate» y no pasa nada más.

Sala

- **Roles**: en cada partida se reparten al azar entre los 3 jugadores (también en la primera).
- **Modo Lo Indefendible**: el juego reparte «de acuerdo» y «en desacuerdo» al azar; no hay
  elección secreta ni pregunta descartada.
- **Posturas**: los nombres son «De acuerdo» / «En desacuerdo» (antes «A favor» / «En contra»).

## Juego en línea (fases 3, 4 y 5)

**Opción elegida (la recomendada en el prompt): servidor dedicado de Godot + ENet.** El mismo
proyecto ejecutado con `--headless` en un VPS barato (o en el PC de un amigo) atiende las salas por
el multijugador de alto nivel de Godot (UDP, puerto 7777 por defecto). Los jugadores solo necesitan
la dirección y el código de la sala. Ventajas: el servidor es autoritativo (guarda las manos), usa
el mismo `DebateEngine` y no hace falta abrir puertos en casa de todos. Como alternativa, un jugador
puede alojar la sala desde el propio juego («Alojar la sala en este PC»); entonces los demás se
conectan a su dirección y él debe abrir el puerto en su router y en el firewall de Windows.

**Cambio posterior: de ENet (UDP) a WebSocket (TCP).** Para alojar el servidor gratis en Render,
que solo deja pasar HTTP/WebSocket, `Net` usa `WebSocketMultiplayerPeer`. Las RPC y las salas no
cambiaron; lo único distinto: todo llega en orden y sin pérdidas (la voz «unreliable» también, con
algo más de retraso si la red va mal), el tope de 60 conexiones lo aplica `Net` a mano, el puerto
es TCP, y con una URL (`wss://…`) se esperan 75 s a que conecte porque Render despierta despacio.
El `Dockerfile` arranca el servidor en Render (pasos en `DESPLIEGUE_RENDER.md`); no se pudo probar
la imagen aquí (no hay Docker en este PC).

- **Servidor autoritativo**: `Net` (scripts/net/net.gd) tiene las salas; cada una con su `GameRoom` y su
  `DebateEngine`. Cada acción que llega la valida el motor y **el servidor pone el índice del
  jugador** (aunque un cliente mande otro). A cada jugador le manda solo su foto
  (`snapshot_for`) y los eventos que puede ver; el monto y la decisión de un soborno solo los ve
  el juez y quien sobornó.
- **Motor espejo en el cliente**: la mesa de siempre (`table.gd`) dibuja el motor espejo, así el
  juego en línea y el local comparten interfaz. La única diferencia es que en línea no hay pantalla
  de relevo: cada uno ve su mano en su turno y, si no es su turno, un aviso de a quién se espera.
- **Sala**: 3 jugadores, código de 4 letras (sin I ni O). Quien crea la sala es el anfitrión: empieza
  cada partida (y la siguiente, con los roles otra vez al azar y las monedas de sobornos no
  descubiertos guardadas en la sala). Si alguien se va o se desconecta, la sala se cierra para todos:
  **no hay reconexión** en esta versión.
- **Reloj**: lo lleva el servidor; los clientes lo muestran contando por su cuenta y lo corrigen con
  cada foto (el servidor la repite cada 5 s).
- **Preguntas**: el servidor las manda con todos los idiomas y cada jugador la lee en el suyo. Los
  mensajes de error del servidor salen en español.
- **Versiones**: un cliente con otra versión del protocolo no puede entrar; si sus cartas o reglas
  (`cards.json`, `config.json`) no son iguales a las del servidor, la sala de espera lo avisa (las
  reglas las aplica el servidor, pero los textos de las cartas los arma cada cliente).
- **Chat de texto** (fase 4): mensajes de hasta 200 letras reenviados a la sala por el servidor.
- **Voz** (fase 5), en su propio módulo (`scripts/voice/`): no se usó WebRTC porque Godot de
  escritorio no lo trae sin una extensión aparte. En su lugar el micrófono se captura, se comprime
  a 16 kHz y 8 bits (μ-law, ~16 KB/s por quien habla) y viaja por el mismo servidor, que solo lo
  reenvía. **Qué falta**: cancelación de eco y ruido (mejor con auriculares), un búfer que absorba
  el retraso de la red, y verlo funcionando con un micrófono real (no se pudo probar aquí). Para
  abrir el micrófono hay que activar «Enable Input» (`audio/driver/enable_input`) en los Ajustes del
  proyecto y reiniciar; se dejó apagado para no pedir permisos a quien solo juega en una pantalla.
  Mientras tanto se puede jugar con voz externa (Discord, etc.).
- **Qué se probó**: servidor real y 3 clientes reales por red en `localhost` (partidas completas,
  varias partidas seguidas, chat, reenvío de voz, desconexión a mitad de partida, mensajes
  inválidos y suplantación del juez) y la mesa en línea con ventana. **No** se probó entre dos
  computadores distintos ni por internet.

## Fases del prompt

| Fase | Estado |
|---|---|
| 0 Esqueleto | Hecha (README, DECISIONES, carpetas ya existentes). |
| 1 Motor de reglas + pruebas | Hecha: `tests/rules_test.tscn` y `tests/simulate.tscn`. |
| 2 Interfaz local | Hecha: los 3 roles en una sola pantalla con pantalla de relevo. |
| 3 Online | Hecha (servidor autoritativo, salas con código, roles al azar entre partidas). |
| 4 Chat | Hecha. |
| 5 Voz | Hecha en su módulo aislado; el micrófono real no está probado (ver arriba). |
| 6 Preguntas | Hecha: dos archivos, 30 preguntas cada uno, en español e inglés. |
