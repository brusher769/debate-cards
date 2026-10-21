# Servidor dedicado del juego para Render (o cualquier sitio que corra Docker).
# Descarga Godot para Linux, importa el proyecto y arranca res://scenes/server.tscn sin pantalla.
# El puerto lo da Render en la variable PORT (server_main.gd la lee). Ver DESPLIEGUE_RENDER.md.
FROM debian:bookworm-slim

# Debe ser la misma versión de Godot con la que se hace el juego.
ARG GODOT_VERSION=4.6.1

RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates wget unzip libfontconfig1 \
	&& rm -rf /var/lib/apt/lists/*

RUN wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" -O /tmp/godot.zip \
	&& unzip -q /tmp/godot.zip -d /tmp \
	&& mv "/tmp/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot \
	&& chmod +x /usr/local/bin/godot \
	&& rm /tmp/godot.zip

WORKDIR /app
COPY . .

# Genera la carpeta .godot (clases con class_name y recursos importados) antes de arrancar.
RUN godot --headless --path . --import

ENV PORT=7777
EXPOSE 7777
CMD ["godot", "--headless", "--path", ".", "res://scenes/server.tscn"]
