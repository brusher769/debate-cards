# DEBATE DE CARTAS: Documento de reglas v1.0

Fuente de verdad del diseño. Todo lo marcado con ⚠️ es un supuesto que se tomó para cerrar el diseño; se puede cambiar editando los datos, no el código.

---

## 1. Concepto

Juego online de debate con cartas. Dos debatientes con posturas opuestas hablan (micrófono) o escriben (chat) por turnos y juegan cartas. Un tercer jugador es el **juez** (un humano, un amigo) y decide quién convence más. El juez no usa cartas ni comodines.

Filosofía: no es un TCG. Las cartas dan herramientas para generar discusión, caos y decisiones del juez. Lo que manda es el debate real, no la carta.

Tres capas: el debate (hablar), las cartas (estrategia) y el juez (interacción social, incluido el soborno).

---

## 2. Sala y roles

- Una sala = 3 jugadores conectados desde dispositivos distintos (código de sala).
- Por partida: 2 debatientes + 1 juez. El juez es **fijo durante esa partida**.
- Entre partidas de la misma sala, los roles rotan de forma **aleatoria** (el juez puede pasar a ser debatiente). ⚠️ Se reasignan al azar entre los 3.
- Modos de juego: **Normal** y **Lo Indefendible** (ver sección 9).

---

## 3. Preparación de una partida

Cada debatiente recibe:
- **5 cartas normales al azar, todas distintas entre sí** (de las 13). El rival puede tener las mismas.
- **1 comodín al azar** (de los 11 actuales).
- **5 monedas** 🪙. Excepción: quien venga de ser juez y tenga monedas de sobornos no descubiertos empieza con 5 + esas monedas, **máximo 10**. ⚠️ Si sigue siendo juez otra partida, conserva esas monedas hasta que juegue (siempre con tope 10).

La mano de 5 **no se repone** nunca.

Postura: aparece la pregunta en pantalla y cada debatiente elige en secreto Acuerdo o Desacuerdo; luego se revelan.
- Posturas opuestas: empieza el debate.
- Ambos de acuerdo o ambos en desacuerdo: no hay debate. ⚠️ Se saca otra pregunta.

Empieza el primer turno un debatiente al azar. ⚠️

---

## 4. Turnos

- Los debatientes se alternan.
- **No se puede pasar turno.** En tu turno debes jugar una carta normal sí o sí.
- Duración base de una intervención: **1 minuto** (la marca el reloj; si se acaba, el turno termina). ⚠️
- Tras la intervención, el juez puntúa (ver sección 5).
- Los comodines se juegan **además** de la carta normal del turno (son opcionales), salvo **Jurisprudencia**, que gasta el turno completo. ⚠️
- Un comodín se **revela públicamente** al jugarse. El rival tiene una **ventana de 10 segundos** para responder con su propio comodín si tiene uno compatible. ⚠️ Como cada uno tiene un solo comodín, no hay cadenas: un comodín contra un comodín y se acabó.
- Un comodín dura **1 turno** y luego queda gastado.

---

## 5. Puntuación

El juez usa solo estos valores por intervención: **+5 / −2 / −1**, según su valoración.

- Cartas de **puntuación libre** (el juez da +5/−2/−1): Argumentar, Buscar evidencia, Refutar, Contraargumentar, Replanteamiento, Ejemplo, Apelación (después de usar el tiempo concedido). ⚠️
- Cartas de **decisión** (el juez solo decide "procede / no procede" y los puntos son fijos): Objeción, Incriminación, Trampa lógica, Interrogar, Definición, Desafío.

Ganador: quien tenga **más puntos** al terminar. Si hay igualdad, la pantalla muestra **"Empate"** y no pasa nada más.

---

## 6. Cartas normales (13)

| # | Carta | Efecto |
|---|---|---|
| 1 | 🗣️ **Argumentar** | Presentas tu argumento sobre el tema. 1 minuto. |
| 2 | 🔎 **Buscar evidencia** | Presentas evidencia (enlace, y en fases posteriores imagen) para respaldar tu posición. El juez la valora. |
| 3 | ⚔️ **Refutar** | Se juega durante la intervención del rival: termina su turno de inmediato y tú tienes 1 minuto para refutar. El rival puede responder con su propia Refutar si la conserva (cadena de máximo 2). |
| 4 | ⚖️ **Objeción** | Se juega durante la intervención del rival. El juez decide si procede. **Procede:** el turno del rival termina, rival −1, tú +1 y tomas la palabra 1 minuto sin gastar otra carta. ⚠️ **No procede:** tú −1. |
| 5 | 📣 **Apelación** | Pides tiempo adicional al juez para continuar tu argumento. El juez decide: 0 s, +30 s o +1 min. El juez puntúa después. ⚠️ |
| 6 | 🕵️ **Incriminación** | Señalas un error concreto del rival (evidencia, afirmación, concepto). **Procede:** rival −2. **No procede:** tú −3. |
| 7 | 🎯 **Contraargumentar** | Esperas a que el rival termine y atacas la conclusión de su argumento. 1 minuto. Puntúa el juez. |
| 8 | ❓ **Interrogar** | Le haces al rival una pregunta obligatoria sobre su argumento; tiene 30 s para responder. El juez decide si la pregunta era válida. **Procede:** rival −1. **No procede:** tú −1. |
| 9 | 🧠 **Definición** | Obligas al rival a definir un concepto que usó. Procede: rival −1. No procede: tú −1. |
| 10 | 🔄 **Replanteamiento** | Reformulas o precisas tu argumento anterior. Puntúa el juez. |
| 11 | 🧨 **Desafío** | "Demuestra que eso es cierto." El rival debe justificar. Procede (no lo defiende): rival −1. No procede: tú −1. |
| 12 | 🪤 **Trampa lógica** | Señalas una contradicción o salto lógico. **Procede:** rival −2. **No procede:** tú −1. |
| 13 | 📝 **Ejemplo** | Presentas un ejemplo concreto que respalda tu postura. El juez valora si apoya el argumento. |

---

## 7. Comodines (11 + 2 futuros)

El sistema debe permitir añadir 2 comodines más sin cambiar código (datos aparte).

| Comodín | Tipo | Efecto |
|---|---|---|
| 💰 **Soborno** | Proactivo | Ofreces monedas (tú decides cuántas) al juez. El juez, en privado, **acepta o rechaza**. Si acepta: pierdes 2 cartas normales al azar y, durante el resto de la partida, a ti el juez **no puede bajarte más de −1** por intervención. ⚠️ El rival ve que jugaste Soborno pero no el monto ni la decisión. ⚠️ Si el juez acepta y no lo descubren, las monedas pasan a la siguiente partida de la sala (ver sección 8). |
| ⚖️ **Veredicto** | Reactivo | Se juega contra un posible soborno. Si el juez **sí aceptó** un soborno: el juez va a la cárcel y **gana automáticamente** quien usó Veredicto. Si el juez **no** fue sobornado (o rechazó): quien usó Veredicto recibe **−2**. Se puede jugar en cualquier momento de la partida. Sin condición de puntos: gana aunque quien sobornó tenga más puntos, siempre que el juez esté en prisión (es decir, que sí aceptó el soborno). |
| 🃏 **Robar carta** | Proactivo | Robas una carta **normal** al azar del rival (no comodines). Puede darte una carta repetida (excepción a la regla de no repetir). El rival pierde esa carta. |
| 🧊 **Cautela** | Proactivo | Bloquea el siguiente turno del rival: no puede usar cartas en ese turno. |
| 🛡️ **Inocente** | Reactivo/Proactivo | Durante 1 turno te protege del bloqueo (Cautela) y limita cualquier pérdida de puntos a **−1**. |
| 🔐 **Secreto** | Reactivo | Nadie puede robarte cartas. Neutraliza Robar carta. |
| ⚔️ **Impugnación** | Reactivo/Proactivo | Elimina automáticamente cualquier comodín o beneficio activo del rival, o un bloqueo que te hayan puesto a ti. ⚠️ No deshace un Soborno ya aceptado ni sus consecuencias. |
| 👊 **Desacato** | Proactivo | En la siguiente resolución del juez sobre ti, los puntos que ibas a recibir (positivos **y** negativos) se transfieren al rival. |
| 📜 **Jurisprudencia** | Proactivo | Gastas **tu turno** en Jurisprudencia. El rival juega. En **tu siguiente turno** repites el efecto de la **última carta normal** que jugaste, sin gastar esa carta otra vez pero sí gastando ese turno. ⚠️ Solo copia cartas normales. |
| 🛑 **END** | Proactivo | Termina la partida de inmediato y se comparan puntos. Se puede usar si se cumple **una** de estas dos condiciones: tener **20 o más puntos** (partida rápida) o que hayan pasado **5 minutos** desde que empezó la partida (con cualquier puntaje). No se puede responder. ⚠️ |
| 🔍 **Lupa** | Proactivo | Ves el comodín del rival. Además puedes **comprar un comodín extra al azar por 1 moneda**. Es el único comodín que puede dar acceso a otro después de usarse. ⚠️ |

Parejas de respuesta previstas: Cautela ← Inocente / Impugnación; Robar carta ← Secreto; Soborno ← Veredicto.

---

## 8. Monedas 🪙

- Cada debatiente empieza con **5** (ver excepción en sección 3).
- **Cambiar comodín:** cuesta 1 moneda, da uno nuevo al azar, solo si **aún no has usado** el tuyo. Si ya lo usaste, no puedes comprar otro (excepción: Lupa).
- **Soborno:** las monedas ofrecidas salen de las del debatiente y van al juez.
- Soborno aceptado y no descubierto: las monedas se guardan para el juez en la sala; si en una partida posterior pasa a ser debatiente empieza con **5 + monedas del soborno, máximo 10**.

---

## 9. Modos

**Normal:** pregunta aleatoria de una lista (temas muy random y polémicos, no ofensivos). Postura elegida en secreto por cada debatiente; si coinciden, no hay debate (se saca otra pregunta).

**Lo Indefendible:** pregunta muy difícil de defender, pero no imposible. La postura se **asigna al azar** por el juego (una a favor y otra en contra), puede tocarte defender algo que no compartes. Ese es el chiste.

Las listas de preguntas son archivos de datos editables (uno por modo).

---

## 10. Fin de partida

La partida termina cuando ocurre **cualquiera** de estas:

1. **Sin cartas:** al jugador al que le toca no le queda ninguna carta normal para jugar. ⚠️
2. **END** jugado por un debatiente (con ≥20 puntos, o después de 5 min de partida).
3. **Veredicto** acertado (gana automáticamente quien lo jugó).
4. **El juez decide terminar**, de forma opcional, después de 10 minutos de partida. Es un poder del juez (por trolear o para que la partida no se vuelva monótona) y no es obligatorio. (parámetro configurable)

Al final: pantalla con puntos de cada uno y ganador o "Empate".

---

## 11. Online

- Sala con código; 3 jugadores en dispositivos distintos.
- Servidor autoritativo: valida reglas, guarda las manos y solo envía a cada cliente su propia mano más la información pública.
- Comunicación: micrófono para quien tenga; **chat de texto** para quien no.
- Plataforma: PC primero (Windows), luego otras.
- Interfaz 2D en el MVP.

---

## 12. Fuera del MVP

- Modelado 3D y arte en Blender.
- Editor de cartas propio.
- Imágenes personalizadas en cartas.
- Comodines 12 y 13.
- Versión de celular.

---

## 13. Supuestos ⚠️ para revisar

| # | Supuesto tomado |
|---|---|
| 1 | Partida termina cuando al jugador al que le toca no le quedan cartas normales. |
| 2 | Comodines se juegan junto a la carta normal; solo Jurisprudencia gasta turno. |
| 3 | Ventana de 10 s para responder a un comodín. |
| 4 | Veredicto se puede usar una vez, cuando quieras (confirmado: sin condición de puntos; gana si el juez sí aceptó el soborno). |
| 5 | El límite −1 del soborno aplica al que sobornó, hasta fin de partida. |
| 6 | El monto y la decisión del soborno son ocultos para el rival. |
| 7 | Objeción procedente da la palabra 1 minuto sin gastar otra carta. |
| 8 | Apelación se juega en tu turno para extender tu argumento; luego puntúa el juez. |
| 9 | Si ambos eligen la misma postura, se saca otra pregunta. |
| 10 | Empieza un debatiente al azar y el reloj de turno es 1 min. |
| 11 | Lupa: ves el comodín rival + 1 comodín extra por 1 moneda. |
| 12 | Roles rotan al azar entre partidas y las monedas de soborno esperan al juez. |
| 13 | END no se puede contrarrestar. |
| 14 | Apelación cuenta como la carta del turno. |

---

## 14. Parámetros configurables (archivo de datos, no código)

```
cartas_normales_por_mano: 5
comodines_por_mano: 1
monedas_iniciales: 5
monedas_maximas: 10
costo_cambiar_comodin: 1
costo_lupa_comodin_extra: 1
duracion_turno_seg: 60
ventana_respuesta_comodin_seg: 10
end_min_puntos: 20
end_min_minutos: 5
juez_puede_terminar_minutos: 10
tiempo_interrogar_respuesta_seg: 30
puntos_juez: [5, -2, -1]
penalizacion_max_con_soborno: -1
penalizacion_veredicto_fallido: -2
```
