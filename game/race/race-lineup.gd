extends RefCounted

const Roster := preload("res://game/ui/character-roster.gd")
const RIVALS := 8


class Rival:
	var path: String
	var title: String
	var academy_number: int

	func _init(model: String, name_value: String, number := 0) -> void:
		path = model
		title = name_value
		academy_number = number

	func display_title() -> String:
		if academy_number > 0:
			return TranslationServer.translate("Academy runner %d") % academy_number
		return title


static func available(player_path: String) -> Array[Rival]:
	var candidates: Array[Rival] = []
	for path in Roster.paths():
		if path != player_path:
			candidates.append(Rival.new(path, Roster.display_name(path)))
	var missing := RIVALS - candidates.size()
	for index in maxi(missing, 0):
		candidates.append(Rival.new("", "Academy runner %d" % (index + 1), index + 1))
	return candidates
