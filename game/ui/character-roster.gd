extends RefCounted

const Runner := preload("res://game/runner/runner.gd")
const MODEL_FOLDER := "res://art/characters"
const DISPLAY_NAMES := {
	"mayano-top-gun-halloween": "Mayano Top Gun (Halloween)",
	"meisho-doto-halloween": "Meisho Doto (Halloween)",
	"mejiro-mcqueen": "Mejiro McQueen",
	"super-creek-mummy": "Super Creek (Mummy)",
	"tm-opera-o": "T.M. Opera O",
}


static func paths() -> Array[String]:
	var installed: Array[String] = []
	for special_week in [Runner.LOCAL_CHARACTER, Runner.FULL_CHARACTER]:
		if ResourceLoader.exists(special_week, "PackedScene"):
			installed.append(special_week)
			break
	var files := ResourceLoader.list_directory(MODEL_FOLDER)
	files.sort()
	for file in files:
		if file.ends_with(".glb"):
			var path := MODEL_FOLDER.path_join(file)
			if ResourceLoader.exists(path, "PackedScene"):
				installed.append(path)
	return installed


static func display_name(path: String) -> String:
	if path.is_empty():
		return TranslationServer.translate("Runner proxy")
	if path == Runner.LOCAL_CHARACTER or path == Runner.FULL_CHARACTER:
		return TranslationServer.translate("Special Week")
	var slug := path.get_file().get_basename()
	return TranslationServer.translate(DISPLAY_NAMES.get(slug, slug.capitalize()))
