extends SceneTree

const RetargetMotion := preload("res://game/tools/retarget-motion.gd")
const RunnerClip := preload("res://game/runner/pose/runner-clip.gd")
const DISPLAY_DIR := "res://art/characters"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or args.size() > 2:
		push_error("Usage: build-roster-runs.gd -- <roster-status.json> [output directory]")
		quit(2)
		return
	var roster := _read_json(args[0])
	if roster.is_empty():
		quit(1)
		return
	var directory := ProjectSettings.globalize_path(args[1] if args.size() == 2 else RunnerClip.ROSTER_RUNS_PATH)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("Could not open run clip directory %s" % directory)
		quit(1)
		return
	var failed := false
	var count := 0
	for slug: String in roster:
		var entry: Dictionary = roster[slug]
		if slug == "special-week" or entry.get("state") != "complete":
			continue
		if not _build_one(slug, entry["output"], directory):
			push_error("Could not build generated run for %s" % slug)
			failed = true
			continue
		count += 1
	print("Built %d generated roster runs." % count)
	quit(1 if failed or count == 0 else 0)


func _build_one(slug: String, output: String, directory: String) -> bool:
	var report := _read_json(output.path_join("generation.json"))
	var provenance := _read_json(output.path_join("baked/provenance.json"))
	var run_take := ""
	for candidate: Dictionary in report.get("cases", []):
		if candidate.get("id") == "run" and not candidate.get("samples", []).is_empty():
			run_take = String(candidate["samples"][0]).get_basename()
			break
	if run_take.is_empty():
		return false
	var clip_path := output.path_join("baked").path_join(run_take + ".glb")
	var origin: Dictionary = provenance.get("candidates/" + run_take, {})
	if not FileAccess.file_exists(clip_path) or origin.get("baked_sha256") != FileAccess.get_sha256(clip_path):
		return false
	if origin.get("frame_digest") != report.get("frame_digest") or int(origin.get("joint_count", 0)) != RunnerClip.BODY_BONES.size():
		return false
	var source := RetargetMotion.load_scene(clip_path)
	var display := RetargetMotion.load_scene(DISPLAY_DIR.path_join(slug + ".glb"))
	if source == null or display == null:
		if source != null:
			source.free()
		if display != null:
			display.free()
		return false
	root.add_child(source)
	root.add_child(display)
	var result := RetargetMotion.new().build(source, display)
	source.free()
	display.free()
	if result.is_empty():
		return false

	var library := AnimationLibrary.new()
	library.add_animation(&"run", result["animation"])
	result.erase("animation")
	result["source"] = run_take
	result["generation"] = origin
	result["reference_run"] = report.get("reference_run", false)
	library.set_meta(&"generated_run", result)
	var destination := directory.path_join(slug)
	if ResourceSaver.save(library, destination + ".res") != OK:
		return false
	var file := FileAccess.open(destination + ".json", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"run": result}, "  ") + "\n")
	print("%s: frames %s, %.3f s %s" % [slug, result["loop_frames"], result["cycle"],
		"same-foot cycle" if result["same_foot_window"] else "full take"])
	return true


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Missing %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
