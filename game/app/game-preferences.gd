extends RefCounted

const SETTINGS := "user://preferences.cfg"

static var show_npc_names := bool(read("interface", "show_npc_names", false))


static func read(section: String, key: String, fallback: Variant) -> Variant:
	var preferences := ConfigFile.new()
	preferences.load(SETTINGS)
	return preferences.get_value(section, key, fallback)


static func write(section: String, key: String, value: Variant) -> void:
	var preferences := ConfigFile.new()
	preferences.load(SETTINGS)
	preferences.set_value(section, key, value)
	preferences.save(SETTINGS)


static func set_show_npc_names(enabled: bool) -> void:
	show_npc_names = enabled
	write("interface", "show_npc_names", enabled)
