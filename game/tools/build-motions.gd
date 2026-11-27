extends SceneTree

# Build an AnimationLibrary of UniMate clips for the local character.
#
# Extract the 24 body animation tracks from the approved trial mesh. The JSON
# records the source batch, measured speed, and selected playback window.
#
# Usage:
#   godot --headless --path . --script res://game/tools/build-motions.gd -- \
#       <baked clip dir> <output.tres> [measurements.json] [picks.json]
#
# Looping picks use two matching frame indices at the source frame rate.
# Without it every clip is kept under its file stem.

const RunnerClip := preload("res://game/runner/pose/runner-clip.gd")
const ROOT := RunnerClip.CHARACTER_PATH


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() < 2:
		push_error("usage: build-motions.gd -- <clip dir> <output.tres> [measurements] [picks]")
		quit(2)
		return
	var directory := arguments[0]
	var destination := arguments[1]
	var measurements := _read_json(arguments[2]) if arguments.size() > 2 else {}
	var picks: Dictionary = _read_json(arguments[3]) if arguments.size() > 3 else {}
	var provenance := _read_json(directory.path_join("provenance.json"))
	if arguments.size() > 3 and picks.is_empty():
		push_error("No valid picks in %s" % arguments[3])
		quit(1)
		return
	var bones := _character_bones()
	if bones.is_empty():
		push_error("No skeleton in %s" % ROOT)
		quit(1)
		return
	var info := {}
	var library := AnimationLibrary.new()
	for entry in _sources(directory, picks):
		var action: String = entry[0]
		var stem: String = entry[1]
		var path := directory.path_join(stem + ".glb")
		if stem.is_absolute_path():
			path = stem + ".glb"
		if not FileAccess.file_exists(path):
			push_error("Missing %s" % path)
			quit(1)
			return
		var origin: Dictionary = provenance.get(stem, {})
		if not picks.is_empty() and (origin.get("frame_digest") != RunnerClip.TRIAL_FRAME_DIGEST
				or origin.get("joint_count") != RunnerClip.BODY_BONES.size()
				or origin.get("regenerated") != true
				or origin.get("baked_sha256") != FileAccess.get_sha256(path)):
			push_error("Missing or mismatched 24-joint generation provenance for %s" % action)
			quit(1)
			return
		var clip := _extract(path, bones)
		if clip == null:
			push_error("Expected 24 body rotations and hip translation in %s" % path)
			quit(1)
			return
		clip.resource_name = action
		library.add_animation(action, clip)
		var measured: Dictionary = measurements.get(stem, {})
		var options: Dictionary = entry[2]
		var chosen_start := float(options.get("start", 0.0))
		var chosen_end := float(options.get("end", clip.length))
		var loop_frames: Array = options.get("loop_frames", [])
		if not loop_frames.is_empty():
			if loop_frames.size() != 2 or fmod(float(loop_frames[0]), 1.0) != 0.0 or fmod(float(loop_frames[1]), 1.0) != 0.0:
				push_error("Expected matching source frame indices for %s" % action)
				quit(1)
				return
			chosen_start = float(loop_frames[0]) / RunnerClip.SOURCE_FPS
			chosen_end = float(loop_frames[1]) / RunnerClip.SOURCE_FPS
		if chosen_start < 0.0 or chosen_end > clip.length + 0.001 or chosen_end - chosen_start < 0.10:
			push_error("Invalid playback window for %s" % action)
			quit(1)
			return
		info[String(action)] = {
			"source": stem,
			"generation": origin,
			"cycle": chosen_end - chosen_start,
			"loop_frames": loop_frames,
			"speed": float(options.get("speed", measured.get("cycle_speed", measured.get("ground_speed_mps", 0.0)))),
			"start": chosen_start,
			"end": chosen_end,
			"reverse": bool(options.get("reverse", false)),
			"weight": float(options.get("weight", 1.0)),
			"contact_phase": float(options.get("contact_phase", 0.5)),
			"lean": float(measured.get("lean_median_deg", 0.0)),
			"length": clip.length,
		}
		if options.has("takeoff_phase"):
			info[String(action)]["takeoff_phase"] = clampf(float(options["takeoff_phase"]), 0.0, 1.0)
		print("%s <- %s  %.3f s  %d tracks" % [action, stem.get_file(), clip.length, clip.get_track_count()])
	if library.get_animation_list().is_empty():
		push_error("No clips built")
		quit(1)
		return
	var report := JSON.stringify(info, "  ") + "\n"
	var info_path := destination.get_basename() + ".json"
	var file := FileAccess.open(info_path, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()
	var error := ResourceSaver.save(library, destination)
	print("%d clips -> %s and %s (%s)" % [
		library.get_animation_list().size(), destination, info_path, error_string(error)])
	quit(0 if error == OK else 1)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


# [action, file stem] pairs: the picks mapping, or every clip under its stem.
func _sources(directory: String, picks: Dictionary) -> Array:
	var entries := []
	if not picks.is_empty():
		for action in picks:
			var choice: Variant = picks[action]
			var options: Dictionary = choice if choice is Dictionary else {"source": choice}
			var batch := String(options.get("batch", ""))
			var source := String(options["source"])
			entries.append([String(action), source if batch.is_empty() else batch.path_join(source), options])
	else:
		for name in DirAccess.get_files_at(directory):
			if name.ends_with(".glb"):
				entries.append([name.get_basename(), name.get_basename(), {}])
	entries.sort_custom(func(a, b): return a[0] < b[0])
	return entries


func _character_bones() -> Dictionary:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(ROOT, state) != OK:
		return {}
	var model := document.generate_scene(state)
	var rigs := model.find_children("*", "Skeleton3D", true, false)
	if rigs.is_empty():
		model.queue_free()
		return {}
	var rig := rigs[0] as Skeleton3D
	if rig.get_bone_count() != RunnerClip.BODY_BONES.size():
		model.free()
		return {}
	var bones := {}
	for index in rig.get_bone_count():
		bones[rig.get_bone_name(index)] = true
	model.queue_free()
	return bones


func _extract(path: String, bones: Dictionary) -> Animation:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(path, state) != OK:
		return null
	# Keep constant head, toe and hand rotations from the trial as well.
	var model := document.generate_scene(state, RunnerClip.SOURCE_FPS, false, false)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	var rigs := model.find_children("*", "Skeleton3D", true, false)
	if players.is_empty() or rigs.is_empty():
		model.queue_free()
		return null
	var player := players[0] as AnimationPlayer
	var rig := rigs[0] as Skeleton3D
	if rig.get_bone_count() != bones.size() or player.get_animation_list().size() != 1:
		model.free()
		return null
	var source := player.get_animation(player.get_animation_list()[0]).duplicate(true) as Animation
	var clip := Animation.new()
	clip.length = source.length
	clip.loop_mode = Animation.LOOP_LINEAR
	for track in source.get_track_count():
		var bone := _bone_of(source.track_get_path(track))
		if bone not in RunnerClip.BODY_BONES or not bones.has(bone):
			continue
		var type := source.track_get_type(track)
		if type != Animation.TYPE_ROTATION_3D and type != Animation.TYPE_POSITION_3D:
			continue
		if type == Animation.TYPE_POSITION_3D and bone != &"Hip":
			continue
		var target := clip.add_track(type)
		clip.track_set_path(target, NodePath("Skeleton3D:" + String(bone)))
		clip.track_set_interpolation_type(target, Animation.INTERPOLATION_LINEAR)
		clip.track_set_interpolation_loop_wrap(target, true)
		for key in source.track_get_key_count(track):
			var value = source.track_get_key_value(track, key)
			if type == Animation.TYPE_ROTATION_3D:
				value = (value as Quaternion).normalized()
			clip.track_insert_key(target, source.track_get_key_time(track, key), value)
	model.free()
	if clip.get_track_count() != RunnerClip.BODY_BONES.size() + 1:
		return null
	if clip.find_track(^"Skeleton3D:Hip", Animation.TYPE_POSITION_3D) == -1:
		return null
	for bone: StringName in RunnerClip.BODY_BONES:
		if clip.find_track(NodePath("Skeleton3D:" + String(bone)), Animation.TYPE_ROTATION_3D) == -1:
			return null
	return clip


func _bone_of(path: NodePath) -> StringName:
	var text := String(path)
	var cut := maxi(text.rfind("/"), text.rfind(":"))
	return StringName(text.substr(cut + 1))
