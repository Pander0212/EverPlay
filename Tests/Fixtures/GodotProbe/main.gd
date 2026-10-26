extends Node2D
# EverPlay's Godot probe: shows "Gold: 37", writes user://probe.txt (the game's Saves folder in
# EverPlay), counts clicks (taps arrive as mouse clicks) and quits after 30 seconds.

var gold := 37
var clicks := 0
var label: Label

func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color(0.13, 0.19, 0.25)
	background.size = Vector2(1280, 720)
	add_child(background)
	label = Label.new()
	label.position = Vector2(80, 240)
	label.add_theme_font_size_override("font_size", 96)
	add_child(label)
	_show()
	_write("start gold %d godot %s mix_rate %d" % [gold, Engine.get_version_info().string, AudioServer.get_mix_rate()])
	get_tree().create_timer(30.0).timeout.connect(_finish)

func _show() -> void:
	label.text = "Gold: %d\nClicks: %d" % [gold, clicks]

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		clicks += 1
		_show()
		_write("click %d button %d" % [clicks, event.button_index])

func _write(line: String) -> void:
	var file := FileAccess.open("user://probe.txt", FileAccess.READ_WRITE if FileAccess.file_exists("user://probe.txt") else FileAccess.WRITE)
	file.seek_end()
	file.store_line(line)
	file.close()

func _finish() -> void:
	_write("quit")
	get_tree().quit()
