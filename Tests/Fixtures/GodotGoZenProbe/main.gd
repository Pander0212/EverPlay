extends Node2D
# EverPlay's GoZen probe: opens res://clip.mp4 (H.264 + AAC, our own test pattern) with the GoZen
# plug-in like games do, decodes frames, shows the first one and writes the result to user://probe.txt.

var label: Label

func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color(0.1, 0.2, 0.15)
	background.size = Vector2(1280, 720)
	add_child(background)
	label = Label.new()
	label.position = Vector2(80, 520)
	label.add_theme_font_size_override("font_size", 48)
	add_child(label)
	if not ClassDB.class_exists("GoZenVideo"):
		_finish("no gozen")
		return
	var video: Object = ClassDB.instantiate("GoZenVideo")
	var opened = video.call("open", "res://clip.mp4")
	var frames := 0
	for i in 10:
		if video.call("next_frame", false):
			frames += 1
	var y: Image = video.call("get_y_data")
	var size: Vector2i = video.call("get_resolution")
	if y and not y.is_empty():
		var picture := TextureRect.new()
		picture.texture = ImageTexture.create_from_image(y)
		picture.position = Vector2(80, 60)
		picture.scale = Vector2(2, 2)
		add_child(picture)
	var audio_ok := ClassDB.class_exists("AudioStreamFFmpeg")
	_finish("gozen open %s frames %d res %dx%d y %s audio_class %s" % [str(opened), frames, size.x, size.y, str(y.get_size()) if y else "none", str(audio_ok)])

func _finish(line: String) -> void:
	label.text = line
	var file := FileAccess.open("user://probe.txt", FileAccess.WRITE)
	file.store_line("start gold 37 " + line)
	file.close()
	get_tree().create_timer(15.0).timeout.connect(_quit)

func _quit() -> void:
	var file := FileAccess.open("user://probe.txt", FileAccess.READ_WRITE)
	file.seek_end()
	file.store_line("quit")
	file.close()
	get_tree().quit()
