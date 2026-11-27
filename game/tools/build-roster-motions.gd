extends SceneTree

const RunnerClip := preload("res://game/runner/pose/runner-clip.gd")
const RetargetMotion := preload("res://game/tools/retarget-motion.gd")
const DISPLAY_DIR := "res://art/characters"
const PICKS_PATH := "res://design/unimate/locomotion/picks.json"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or args.size() > 2:
		push_error("Usage: build-roster-motions.gd -- <roster-status.json> [output directory]")
		quit(2)
		return
	var roster := _read_json(args[0])
	var picks := _read_json(PICKS_PATH)
	var destination := ProjectSettings.globalize_path(args[1] if args.size() == 2 else RunnerClip.ROSTER_MOTIONS_PATH)
	if roster.is_empty() or picks.is_empty() or DirAccess.make_dir_recursive_absolute(destination) != OK:
		push_error("Roster status, picks or output directory is unavailable")
		quit(1)
		return
	var count := 0
	var failed := false
	for slug: String in roster:
		var entry: Dictionary = roster[slug]
		if slug == "special-week" or entry.get("state") != "complete":
			continue
		if not _build_character(slug, entry["output"], picks, destination):
			push_error("Could not pack the complete generated set for %s" % slug)
			failed = true
		else:
			count += 1
	print("Packed %d roster libraries with %d actions each." % [count, picks.size()])
	quit(1 if failed or count == 0 else 0)


func _build_character(slug: String, output: String, picks: Dictionary, destination: String) -> bool:
	var report := _read_json(output.path_join("generation.json"))
	var provenance := _read_json(output.path_join("baked/provenance.json"))
	var manifest := _read_json(output.path_join("manifest.json"))
	if not report.get("reference_motions", false):
		return false
	var display := RetargetMotion.load_scene(DISPLAY_DIR.path_join(slug + ".glb"))
	if display == null:
		return false
	root.add_child(display)
	var library := AnimationLibrary.new()
	var info := {}
	for take: Dictionary in report.get("cases", []):
		if not _pack_take(take, output, display, picks, report["frame_digest"],
				provenance, manifest.get("samples", {}), library, info):
			display.free()
			return false
	display.free()
	if info.size() != picks.size():
		return false
	library.set_meta(&"roster_motions", info)
	var stem := destination.path_join(slug)
	if ResourceSaver.save(library, stem + ".res") != OK:
		return false
	var file := FileAccess.open(stem + ".json", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(info, "  ", true, true) + "\n")
	print("%s: %d actions, %.3f s run" % [slug, info.size(), info["run"]["cycle"]])
	return true


func _pack_take(take: Dictionary, output: String, display: Node3D, picks: Dictionary,
		digest: String, provenance: Dictionary, samples: Dictionary,
		library: AnimationLibrary, info: Dictionary) -> bool:
	var filenames: Array = take.get("samples", [])
	if filenames.size() != 1:
		return false
	var filename := String(filenames[0])
	var stem := filename.get_basename()
	var baked := output.path_join("baked").path_join(stem + ".glb")
	var raw := output.path_join("motions").path_join(filename)
	var origin: Dictionary = provenance.get("candidates/" + stem, {})
	var sample: Dictionary = samples.get(filename, {})
	var recipe: Dictionary = take.get("reference_noise", {})
	if digest.is_empty() or origin.get("frame_digest") != digest or sample.get("frame_digest") != digest \
			or int(origin.get("joint_count", 0)) != RunnerClip.BODY_BONES.size() or not origin.get("regenerated", false) \
			or sample.get("reference_source") != take.get("reference_source") \
			or recipe.is_empty() or sample.get("reference_noise") != recipe \
			or not _matches_hash(baked, origin.get("baked_sha256", "")) \
			or not _matches_hash(raw, origin.get("motion_sha256", "")) \
			or origin.get("motion_sha256") != sample.get("sha256"):
		push_error("Missing or mismatched generation provenance for %s" % baked)
		return false
	var source := RetargetMotion.load_scene(baked)
	if source == null:
		return false
	root.add_child(source)
	var retarget := RetargetMotion.new()
	var ok := true
	for action: String in take.get("actions", {}):
		var pick: Dictionary = picks.get(action, {})
		if info.has(action) or pick.get("source") != take.get("reference_source"):
			ok = false
			break
		var result := retarget.build(source, display, action, pick)
		if result.is_empty() or library.add_animation(action, result["animation"]) != OK:
			ok = false
			break
		result.erase("animation")
		for key in ["reverse", "weight", "contact_phase", "takeoff_phase"]:
			if pick.has(key):
				result[key] = pick[key]
		result["source"] = stem
		result["generation"] = origin
		result["reference_source"] = take["reference_source"]
		result["reference_noise"] = recipe
		info[action] = result
	source.free()
	return ok


func _matches_hash(path: String, expected: String) -> bool:
	return expected.length() == 64 and FileAccess.get_sha256(path) == expected


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
