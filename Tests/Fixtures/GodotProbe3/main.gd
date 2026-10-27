extends Node2D
# EverPlay's Godot 3 probe: shows "Gold: 37", writes user://probe.txt (the game's Saves folder in
# EverPlay), counts clicks (taps arrive as mouse clicks) and quits after 30 seconds.

var gold = 37
var clicks = 0
var label

func _ready():
	var background = ColorRect.new()
	background.color = Color(0.25, 0.19, 0.13)
	background.rect_size = Vector2(1280, 720)
	add_child(background)
	label = Label.new()
	label.rect_position = Vector2(80, 200)
	label.rect_scale = Vector2(6, 6)
	add_child(label)
	_show()
	_write("start gold %d godot %s" % [gold, Engine.get_version_info().string])
	get_tree().create_timer(30.0).connect("timeout", self, "_finish")

func _show():
	label.text = "Gold: %d\nClicks: %d" % [gold, clicks]

func _input(event):
	if event is InputEventMouseButton and event.pressed:
		clicks += 1
		_show()
		_write("click %d button %d" % [clicks, event.button_index])

func _write(line):
	var file = File.new()
	if file.file_exists("user://probe.txt"):
		file.open("user://probe.txt", File.READ_WRITE)
		file.seek_end()
	else:
		file.open("user://probe.txt", File.WRITE)
	file.store_line(line)
	file.close()

func _finish():
	_write("quit")
	get_tree().quit()
