extends Node

const Preferences := preload("res://game/app/game-preferences.gd")
const CHINESE := "zh_CN"
const ENGLISH := "en"


func _enter_tree() -> void:
	var preferred: String = Preferences.read("interface", "language", CHINESE)
	TranslationServer.set_locale(ENGLISH if preferred == ENGLISH else CHINESE)


static func toggle() -> void:
	var locale := CHINESE if TranslationServer.get_locale() == ENGLISH else ENGLISH
	TranslationServer.set_locale(locale)
	Preferences.write("interface", "language", locale)
