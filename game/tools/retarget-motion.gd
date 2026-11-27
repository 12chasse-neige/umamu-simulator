extends RefCounted

const RunnerClip := preload("res://game/runner/pose/runner-clip.gd")
const BONES := RunnerClip.BODY_BONES
const FORWARD_GAITS := [&"walk", &"jog", &"run", &"sprint"]
const MATCH_BONES := [&"Head", &"Knee_L", &"Knee_R", &"Ankle_L", &"Ankle_R",
	&"Toe_L", &"Toe_R", &"Wrist_L", &"Wrist_R"]


# Sample the baked source before retargeting. Frame times stay at the source rate.
func build(source: Node3D, display: Node3D, action: StringName = &"run",
		pick: Dictionary = {}) -> Dictionary:
	var source_rigs := source.find_children("*", "Skeleton3D", true, false)
	var target_rigs := display.find_children("*", "Skeleton3D", true, false)
	var players := source.find_children("*", "AnimationPlayer", true, false)
	if source_rigs.size() != 1 or target_rigs.is_empty() or players.size() != 1:
		return {}
	var source_rig := source_rigs[0] as Skeleton3D
	var target_rig := target_rigs[0] as Skeleton3D
	var player := players[0] as AnimationPlayer
	if player.get_animation_list().size() != 1 or not _has_body_tracks(player.get_animation(player.get_animation_list()[0])):
		return {}
	var rest_source := _rest(source_rig)
	var rest_target := _rest(target_rig)
	if rest_source.is_empty() or rest_target.is_empty():
		return {}
	var frames := _sample(source_rig, player)
	if frames.size() < 3:
		return {}
	var run := action == &"run"
	var window := _stride(frames) if run else _reference_window(frames, pick)
	if window.is_empty():
		return {}
	var first := int(window[0])
	var last := int(window[1])
	var loop := run or pick.has("loop_frames")
	var start_time := first / RunnerClip.SOURCE_FPS if loop else float(pick.get("start", 0.0))
	var end_time := last / RunnerClip.SOURCE_FPS if loop else float(pick.get("end", last / RunnerClip.SOURCE_FPS))
	var duration := end_time - start_time
	var start: Vector3 = frames[first].hip
	var displacement: Vector3 = (frames[last].hip - start).slide(Vector3.UP)
	var travel := displacement.length()
	var source_span: float = rest_source[&"Head"].origin.y - rest_source[&"Ankle_L"].origin.y
	var target_span: float = rest_target[&"Head"].origin.y - rest_target[&"Ankle_L"].origin.y
	var forward_gait := action in FORWARD_GAITS
	if (forward_gait and travel <= 0.01) or source_span <= 0.01 or target_span <= 0.01:
		return {}
	# Align ground travel to runner +Z while retaining the source heading
	# changes in turns and the original facing for contact-driven actions.
	var align := Basis(Vector3.UP, -atan2(displacement.x, displacement.z)) if forward_gait else Basis.IDENTITY
	var scale := target_span / source_span
	var per_rig_unit := scale / target_rig.global_basis.get_scale().x
	var rotations := _target_frames(target_rig, rest_target)
	var animation := Animation.new()
	animation.resource_name = String(action)
	animation.length = duration if run else (frames.size() - 1) / RunnerClip.SOURCE_FPS
	animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var ids := {}
	for bone: StringName in BONES:
		ids[bone] = _track(animation, bone, Animation.TYPE_ROTATION_3D)
	var hip_track := _track(animation, &"Hip", Animation.TYPE_POSITION_3D)
	var hip_index := target_rig.find_bone(&"Hip")
	var hip_rest := target_rig.get_bone_rest(hip_index).origin
	var hip_parent: Basis = rotations[&"Hip"].parent_rest
	var first_key := first if run else 0
	var last_key := last if run else frames.size() - 1
	for frame in range(first_key, last_key + 1):
		var time := (frame - first_key) / RunnerClip.SOURCE_FPS
		var source_pose: Dictionary = frames[frame].pose
		var deltas := {}
		for bone: StringName in BONES:
			var animated: Transform3D = source_pose[bone]
			var rest: Transform3D = rest_source[bone]
			deltas[bone] = align * animated.basis * rest.basis.inverse()
		for bone: StringName in BONES:
			var target: Dictionary = rotations[bone]
			var basis: Basis = deltas[bone] * (rest_target[bone] as Transform3D).basis
			var parent: Basis = deltas.get(target.ancestor, Basis.IDENTITY) * target.parent_rest
			var rotation := (parent.inverse() * basis).get_rotation_quaternion()
			animation.track_insert_key(ids[bone], time, rotation.normalized())
		var hip: Vector3 = frames[frame].hip
		var residual: Vector3 = hip - start.slide(Vector3.UP) - Vector3.UP * rest_source[&"Hip"].origin.y
		if run:
			residual -= displacement * (time / duration)
		animation.track_insert_key(hip_track, time, hip_rest + hip_parent.inverse() * align * residual * per_rig_unit)
	var result := {
		"animation": animation,
		"loop_frames": [first, last] if loop else [],
		"cycle": duration,
		"start": 0.0 if run else start_time,
		"end": duration if run else end_time,
	}
	if forward_gait:
		result["speed_per_rig_unit"] = travel * per_rig_unit / duration
	if run:
		result["same_foot_window"] = window[2]
	return result


func _has_body_tracks(animation: Animation) -> bool:
	var rotations := {}
	var hip_translation := false
	for index in animation.get_track_count():
		var path := animation.track_get_path(index)
		if path.get_subname_count() != 1 or animation.track_get_key_count(index) == 0:
			continue
		var bone := path.get_subname(0)
		match animation.track_get_type(index):
			Animation.TYPE_ROTATION_3D:
				if bone in BONES:
					rotations[bone] = true
			Animation.TYPE_POSITION_3D:
				if bone == &"Hip":
					hip_translation = true
	return rotations.size() == BONES.size() and hip_translation


func _reference_window(frames: Array[Dictionary], pick: Dictionary) -> Array:
	var last_frame := frames.size() - 1
	var fps := RunnerClip.SOURCE_FPS
	var window: Array = pick.get("loop_frames", [0, last_frame])
	var start := float(pick.get("start", 0.0))
	var end := float(pick.get("end", last_frame / fps))
	if pick.has("loop_frames"):
		if window.size() != 2 or fmod(float(window[0]), 1.0) != 0.0 or fmod(float(window[1]), 1.0) != 0.0:
			return []
		start = float(window[0]) / fps
		end = float(window[1]) / fps
	if start < 0.0 or end > last_frame / fps + 0.0001 or end - start < 0.10:
		return []
	return [roundi(start * fps), roundi(end * fps)]


static func load_scene(path: String) -> Node3D:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(path, state) != OK:
		return null
	return document.generate_scene(state, RunnerClip.SOURCE_FPS, false, false) as Node3D


func _rest(rig: Skeleton3D) -> Dictionary:
	var rest := {}
	for bone: StringName in BONES:
		var index := rig.find_bone(bone)
		if index == -1:
			return {}
		rest[bone] = (rig.global_transform * rig.get_bone_global_rest(index)).orthonormalized()
	return rest


func _sample(rig: Skeleton3D, player: AnimationPlayer) -> Array[Dictionary]:
	var name := player.get_animation_list()[0]
	var length := player.get_animation(name).length
	player.play(name)
	var frames: Array[Dictionary] = []
	for frame in roundi(length * RunnerClip.SOURCE_FPS) + 1:
		player.seek(minf(frame / RunnerClip.SOURCE_FPS, length), true)
		rig.force_update_all_bone_transforms()
		var pose := {}
		for bone: StringName in BONES:
			pose[bone] = (rig.global_transform * rig.get_bone_global_pose(rig.find_bone(bone))).orthonormalized()
		var hip: Vector3 = pose[&"Hip"].origin
		var right: Vector3 = (pose[&"Thigh_L"].origin - pose[&"Thigh_R"].origin).slide(Vector3.UP).normalized()
		var forward := right.cross(Vector3.UP)
		var frame_basis := Basis(right, Vector3.UP, forward)
		var features := PackedVector3Array()
		for bone: StringName in MATCH_BONES:
			features.append(frame_basis.inverse() * (pose[bone].origin - hip))
		var ankles: Vector3 = pose[&"Ankle_L"].origin - pose[&"Ankle_R"].origin
		frames.append({"pose": pose, "hip": hip, "forward": forward,
			"separation": ankles.dot(forward), "features": features})
	player.stop()
	return frames


func _stride(frames: Array[Dictionary]) -> Array:
	var best := INF
	var window := [0, frames.size() - 1, false]
	var left := 0.0
	var right := 0.0
	for frame: Dictionary in frames:
		left = maxf(left, frame.separation)
		right = maxf(right, -frame.separation)
	var crossing_band := maxf(0.005, minf(left, right) * 0.075)
	for first in range(frames.size() - 2):
		var start: Dictionary = frames[first]
		if absf(start.separation) < crossing_band:
			continue
		var side := signf(start.separation)
		var crossings := 0
		for last in range(first + 1, frames.size() - 1):
			var finish: Dictionary = frames[last]
			if absf(finish.separation) >= crossing_band and signf(finish.separation) != side:
				side = signf(finish.separation)
				crossings += 1
			# Same foot forward, with exactly one opposite-foot step in between.
			if crossings > 2:
				break
			if crossings != 2 or absf(finish.separation) < crossing_band or last - first < 9:
				continue
			var travel: Vector3 = (finish.hip - start.hip).slide(Vector3.UP)
			var forward: Vector3 = (start.forward + finish.forward).normalized()
			if travel.dot(forward) <= 0.07:
				continue
			var score := _seam_score(frames, first, last)
			score += 0.15 * (1.0 - clampf(travel.normalized().dot(forward), -1.0, 1.0))
			score += 0.10 * (1.0 - start.forward.dot(finish.forward))
			if score < best:
				window = [first, last, true]
				best = score
	return window


func _seam_score(frames: Array[Dictionary], first: int, last: int) -> float:
	var start: PackedVector3Array = frames[first].features
	var finish: PackedVector3Array = frames[last].features
	var after_start: PackedVector3Array = frames[first + 1].features
	var after_end: PackedVector3Array = frames[last + 1].features
	var score := 0.0
	for index in start.size():
		score += start[index].distance_to(finish[index])
		score += 2.0 * (after_start[index] - start[index]).distance_to(after_end[index] - finish[index])
	return score / start.size()


func _target_frames(rig: Skeleton3D, body_rest: Dictionary) -> Dictionary:
	var frames := {}
	for bone: StringName in BONES:
		var parent := rig.get_bone_parent(rig.find_bone(bone))
		var parent_rest := rig.global_basis.orthonormalized()
		if parent != -1:
			parent_rest = (rig.global_basis * rig.get_bone_global_rest(parent).basis).orthonormalized()
		var ancestor := &""
		while parent != -1:
			var name := rig.get_bone_name(parent)
			if body_rest.has(name):
				ancestor = name
				break
			parent = rig.get_bone_parent(parent)
		frames[bone] = {"parent_rest": parent_rest, "ancestor": ancestor}
	return frames


func _track(animation: Animation, bone: StringName, type: Animation.TrackType) -> int:
	var index := animation.add_track(type)
	animation.track_set_path(index, NodePath("Skeleton3D:" + String(bone)))
	animation.track_set_interpolation_type(index, Animation.INTERPOLATION_LINEAR)
	return index
