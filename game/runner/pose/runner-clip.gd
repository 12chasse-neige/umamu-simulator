extends RefCounted

# Sample authored bone tracks without moving the gameplay capsule.
const CHARACTER_PATH := "res://art/special-week/special-week-trial.glb"
const LIBRARY_PATH := "res://art/special-week/motions.tres"
const INFO_PATH := "res://art/special-week/motions.json"
const ROSTER_MOTIONS_PATH := "res://art/characters/motions"
const ROSTER_RUNS_PATH := "res://art/characters/runs"
const TRIAL_FRAME_DIGEST := "9312a658625511a5bcf0253cf3be0d61140ce5bc"
const FADE := 0.19
const SOURCE_FPS := 30.0
const LOOP_JOIN := 2.0 / SOURCE_FPS
const IDLE_LOOP_JOIN := 6.0 / SOURCE_FPS
const TORSO := [&"Hip", &"Waist", &"Spine", &"Chest", &"Neck", &"Head"]
const ARMS := [
	&"Shoulder_L", &"Shoulder_R", &"Arm_L", &"Arm_R", &"Elbow_L", &"Elbow_R",
	&"Wrist_L", &"Wrist_R", &"Hand_Attach_L", &"Hand_Attach_R",
]
const LEGS := [
	&"Thigh_L", &"Thigh_R", &"Knee_L", &"Knee_R", &"Ankle_L", &"Ankle_R", &"Toe_L", &"Toe_R",
]
const BODY_BONES := TORSO + ARMS + LEGS

var pose: Dictionary[StringName, Quaternion] = {}
var pelvis := Vector3.INF
var walk_sway := Vector3.ZERO
var weight := 0.0
var action := &""

var _library: AnimationLibrary
var _info: Dictionary = {}
var _tracks: Dictionary[StringName, Dictionary] = {}
var _hips: Dictionary[StringName, int] = {}
var _previous: Dictionary[StringName, Quaternion] = {}
var _previous_pelvis := Vector3.INF
var _previous_walk_sway := Vector3.ZERO
var _fade := 1.0
var _initial_weight := 0.0
var _metres_per_unit := 1.0


func bind(rig: Skeleton3D, library_path: String = LIBRARY_PATH,
		info_path: String = INFO_PATH, metres_per_unit: float = 1.0) -> bool:
	if not ResourceLoader.exists(library_path):
		return false
	_library = load(library_path) as AnimationLibrary
	if _library == null:
		return false
	_metres_per_unit = metres_per_unit
	if uses_roster_motions():
		_info = _library.get_meta(&"roster_motions")
	elif _library.has_meta(&"generated_run"):
		_info["run"] = _library.get_meta(&"generated_run")
	else:
		var file := FileAccess.open(info_path, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_info = parsed
	for name: StringName in _library.get_animation_list():
		var animation := _library.get_animation(name)
		var tracks: Dictionary[StringName, int] = {}
		for track in animation.get_track_count():
			var path := animation.track_get_path(track)
			if path.get_subname_count() != 1:
				continue
			var bone := path.get_subname(0)
			if bone not in BODY_BONES or rig.find_bone(bone) == -1:
				continue
			match animation.track_get_type(track):
				Animation.TYPE_ROTATION_3D:
					tracks[bone] = track
				Animation.TYPE_POSITION_3D:
					if bone == &"Hip":
						_hips[name] = track
		_tracks[name] = tracks
	return true


func has(name: StringName) -> bool:
	return _tracks.has(name) and not _tracks[name].is_empty()


func has_generated_run() -> bool:
	var info: Dictionary = _info.get("run", {})
	return _tracks.get(&"run", {}).size() == BODY_BONES.size() and _hips.has(&"run") \
		and float(info.get("speed_per_rig_unit", 0.0)) > 0.0 and float(info.get("cycle", 0.0)) > 0.0


func uses_roster_motions() -> bool:
	return _library != null and _library.has_meta(&"roster_motions")


func speed(name: StringName, fallback: float) -> float:
	var info: Dictionary = _info.get(String(name), {})
	var native := float(info.get("speed_per_rig_unit", 0.0)) * _metres_per_unit
	if has(name) and native > 0.0:
		return native
	var measured := float(info.get("speed", 0.0))
	return measured if has(name) and measured >= 0.25 else fallback


func period(name: StringName, fallback: float) -> float:
	if not has(name):
		return fallback
	var animation := _library.get_animation(name)
	return float(_info.get(String(name), {}).get("cycle", animation.length))


func contact_phase(name: StringName, fallback: float) -> float:
	return float(_info.get(String(name), {}).get("contact_phase", fallback))


func jump_takeoff_phase() -> float:
	return float(_info.get("jump", {}).get("takeoff_phase", 0.19))


func reset() -> void:
	pose.clear()
	_previous.clear()
	pelvis = Vector3.INF
	walk_sway = Vector3.ZERO
	weight = 0.0
	action = &""
	_fade = 1.0


func sample(name: StringName, phase: float, loop: bool, delta: float) -> void:
	if not has(name):
		name = &""
	if name != action:
		_previous = pose.duplicate()
		_previous_pelvis = pelvis
		_previous_walk_sway = walk_sway
		_initial_weight = weight
		action = name
		_fade = 0.0
	_fade = minf(1.0, _fade + delta / FADE)
	var mix := smoothstep(0.0, 1.0, _fade)
	weight = lerpf(_initial_weight, 0.0 if action == &"" else float(_info.get(String(action), {}).get("weight", 1.0)), mix)
	if action == &"":
		if weight <= 0.0:
			pose.clear()
			pelvis = Vector3.INF
			walk_sway = Vector3.ZERO
		return
	var animation := _library.get_animation(action)
	var info: Dictionary = _info.get(String(action), {})
	var start := clampf(float(info.get("start", 0.0)), 0.0, animation.length - 0.05)
	var end := clampf(float(info.get("end", animation.length)), start + 0.05, animation.length)
	var length := period(action, end - start) if loop else end - start
	var progress := fposmod(phase, 1.0) if loop else clampf(phase, 0.0, 1.0)
	if info.get("reverse", false):
		progress = 1.0 - progress
	var time := start + progress * length
	# Blend corresponding frames from the two ends of the recorded cycle.
	# Both sides approach the same pose and use the nearby source velocities.
	var edge := minf(progress, 1.0 - progress) * length
	var join := LOOP_JOIN
	if action == &"idle" and loop:
		# Idle has room to close its pose over a longer interval at native speed.
		var source_margin := minf(start, animation.length - (start + length))
		join = maxf(join, minf(IDLE_LOOP_JOIN, minf(length * 0.25, source_margin)))
	var seam := (1.0 - smoothstep(0.0, join, edge)) * 0.5 if loop else 0.0
	var seam_time := clampf(time + (length if progress < 0.5 else -length), 0.0, animation.length)
	var tracks := _tracks[action]
	pose.clear()
	for bone: StringName in tracks:
		var track: int = tracks[bone]
		var rotation := animation.rotation_track_interpolate(track, time)
		if seam > 0.0:
			rotation = rotation.slerp(animation.rotation_track_interpolate(track, seam_time), seam)
		if _previous.has(bone):
			rotation = (_previous[bone] as Quaternion).slerp(rotation, mix)
		pose[bone] = rotation
	pelvis = Vector3.INF
	walk_sway = Vector3.ZERO
	if _hips.has(action):
		var track := _hips[action]
		var source_pelvis := animation.position_track_interpolate(track, time)
		var seam_pelvis := Vector3.ZERO
		pelvis = source_pelvis
		if seam > 0.0:
			seam_pelvis = animation.position_track_interpolate(track, seam_time)
			pelvis = pelvis.lerp(seam_pelvis, seam)
		if _previous_pelvis.is_finite():
			pelvis = _previous_pelvis.lerp(pelvis, mix)
		if action == &"walk" and loop:
			# Retain the motion within the stride after the capsule supplies
			# the net travel. Close that residual in the same source frames.
			var first := animation.position_track_interpolate(track, start)
			var last := animation.position_track_interpolate(track, start + length)
			walk_sway = source_pelvis - first.lerp(last, progress)
			if seam > 0.0:
				var other_progress := (seam_time - start) / length
				walk_sway = walk_sway.lerp(seam_pelvis - first.lerp(last, other_progress), seam)
	walk_sway = _previous_walk_sway.lerp(walk_sway, mix)
