# Subir el servidor a Render

El juego en línea usa **WebSocket**, así que el servidor puede vivir gratis en
[Render](https://render.com). Render arma la imagen con el `Dockerfile` de la raíz del proyecto
(descarga Godot 4.6.1 para Linux y arranca `res://scenes/server.tscn` sin pantalla).

## 1. Crear el servicio

1. Entra a <https://dashboard.render.com> con tu cuenta de GitHub.
2. Arriba a la derecha: **New +** → **Web Service**.
3. Si no ves `debate-cards` en la lista, pulsa **Configure account** y dale acceso a ese repositorio
   (Render solo ve los repos que le autorices).
4. Selecciona `brusher769/debate-cards` y rellena:
   - **Name**: `debate-cards` (de aquí sale la dirección: `debate-cards.onrender.com`).
   - **Language / Runtime**: **Docker** (lo detecta solo por el `Dockerfile`).
   - **Branch**: `main`.
   - **Root Directory**: déjalo **vacío** (el `Dockerfile` está en la raíz).
   - **Instance Type**: **Free**.
   - No hace falta Build Command ni Start Command: los pone el `Dockerfile`.
   - No agregues la variable `PORT`: Render la pone sola y el servidor la lee.
5. **Create Web Service**. La primera construcción tarda unos minutos. Está listo cuando en
   **Logs** aparece:

   ```
   [servidor] SERVIDOR LISTO en el puerto TCP 10000 (WebSocket) ...
   ```

## 2. Conectarse desde el juego

En **Jugar en línea**, en el campo del servidor, escribe la dirección de Render con `wss://`
delante (sin puerto):

```
wss://debate-cards.onrender.com
```

Uno crea la sala (sin marcar «Alojar la sala en este PC») y pasa el código a los otros dos, que
escriben la misma dirección y el código.

## 3. Cosas a saber

- **Se duerme**: en el plan gratis, Render apaga el servidor tras unos 15 minutos sin uso. La primera
  conexión después lo despierta y puede tardar cerca de un minuto; el juego espera hasta 75 segundos
  antes de decir que no pudo conectar. Si falla, vuelve a intentarlo.
- **Al dormirse se pierden las salas** (viven en memoria): conviene que el primero en entrar espere a
  que conecte antes de pasar el código.
- **Actualizar**: cada `git push` a `main` vuelve a construir y reiniciar el servidor (Render lo hace
  solo). Todos los jugadores deben tener la misma versión del juego que el servidor: si cambias
  `cards.json` o `config.json`, la sala de espera avisa de la diferencia.
- **Versión de Godot**: el `Dockerfile` usa la 4.6.1 (`ARG GODOT_VERSION`). Si cambias de versión
  de Godot, cámbiala también ahí.

## Jugar en red local (sin Render)

Sigue funcionando como antes: marca «Alojar la sala en este PC» y los demás escriben
`dirección:puerto` (por ejemplo `192.168.1.20:7777`). Ahora el puerto es **TCP** (antes UDP): si
el firewall de Windows pregunta, permite la conexión.
