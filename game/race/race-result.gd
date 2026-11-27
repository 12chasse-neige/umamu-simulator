extends RefCounted

var title: String
var model: String
var seconds: float
var is_player: bool


func _init(name_value: String, path: String, time: float, player: bool) -> void:
	title = name_value
	model = path
	seconds = time
	is_player = player


static func clock(elapsed: float) -> String:
	var whole := floori(elapsed)
	var hundredths := floori(elapsed * 100.0) % 100
	return "%02d:%02d.%02d" % [floori(elapsed / 60.0), whole % 60, hundredths]
