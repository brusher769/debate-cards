extends Node
## Servidor dedicado: arranca Net como servidor y se queda atendiendo salas. No dibuja nada, así que
## sirve con --headless (por ejemplo en un VPS):
##
##   godot --headless --path . res://scenes/server.tscn -- --port=7777
##
## En un juego exportado: Debate.exe --headless -- --server --port=7777 (el menú principal detecta
## --server y cambia a esta escena). Opciones (después de "--"):
##   --port=N            puerto TCP del WebSocket (por defecto 7777, o la variable de entorno PORT)
##   --quit-after=N      apagarse solos a los N segundos (para pruebas)
##
## En Render (ver DESPLIEGUE_RENDER.md) el puerto lo elige Render y llega en la variable PORT.


func _ready() -> void:
	var port := Net.DEFAULT_PORT
	if OS.get_environment("PORT").is_valid_int():
		port = int(OS.get_environment("PORT"))
	var quit_after := 0.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = int(arg.get_slice("=", 1))
		elif arg.begins_with("--quit-after="):
			quit_after = float(arg.get_slice("=", 1))
	var err := Net.start_server(port)
	if err != OK:
		printerr("[servidor] no pude abrir el puerto %d (error %d). ¿Ya hay otro servidor usándolo?" % [port, err])
		get_tree().quit(1)
		return
	print("[servidor] SERVIDOR LISTO en el puerto TCP %d (WebSocket) (versión de datos %s)" % [port, Net.data_version().left(8)])
	if quit_after > 0.0:
		await get_tree().create_timer(quit_after).timeout
		print("[servidor] apagándose")
		get_tree().quit()
