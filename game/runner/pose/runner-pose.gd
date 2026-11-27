extends RefCounted

const Locomotion := preload("res://game/runner/runner-control.gd")
const SkirtClearance := preload("res://game/runner/pose/skirt-clearance.gd")
const RunnerClip := preload("res://game/runner/pose/runner-clip.gd")
const RunnerTail := preload("res://game/runner/pose/runner-tail.gd")

const WALK_SPEED := 1.35
const JOG_SPEED := 3.0
const SPRINT_SPEED := 6.2

# Full gait period, approximate stance fraction, swing clearance and torso pitch.
# The profile interpolates at the actual speed. Each leg is half a cycle apart.
const WALK := Vector4(1.04, 0.60, 0.078, 1.5)
const JOG := Vector4(0.64, 0.36, 0.195, 9.0)
const SPRINT := Vector4(0.48, 0.25, 0.30, 30.0)
const CROUCH := Vector4(1.16, 0.60, 0.070, 24.0)

const TORSO := [&"Hip", &"Waist", &"Chest", &"Neck", &"Head"]
const LIMBS := ["Thigh", "Knee", "Ankle", "Toe", "Arm", "Elbow", "Wrist", "Hand_Attach"]
const SIDES := ["L", "R"]
const FINGERS := ["Thumb", "Index", "Middle", "Ring", "Pinky"]
const POSE_BLEND_TIME := 0.16


class Foot:
	var planted := false
	var anchor := Vector3.ZERO
	var lift_off := Vector3.ZERO
	var last_base := Vector3.ZERO
	var has_position := false
	var has_floor := false
	var floor_y := INF
	var stop_from := Vector3.ZERO
	var displayed_ankle := Vector3.INF
	var displayed_toe := Vector3.INF


var rig: Skeleton3D
var _facing: Node3D
var _rig_base := Transform3D.IDENTITY
var _metres_per_unit := 1.0
var _indices: Dictionary[StringName, int] = {}
var _rest: Array[Transform3D] = []
var _global_rest: Array[Transform3D] = []
var _parents := PackedInt32Array()
var _rotations: Dictionary[int, Quaternion] = {}
var _poses: Dictionary[int, Transform3D] = {}
var _legs: Array[PackedInt32Array] = []
var _arms: Array[PackedInt32Array] = []
var _fingertips: Array[PackedInt32Array] = []
var _skirt_clearance := SkirtClearance.new()
var _clips := RunnerClip.new()
var _tail := RunnerTail.new()
var _uses_trial_skin := false
var _idle_hand_weight := 0.0
var _clip_clock := 0.0
var _gait_speeds: Array[float] = []
var _turn_action := &""
var _turn_time := 1.0
var _pivot_side := 0
var _pivot_anchor := Vector3.INF
var _pivot_yaw := 0.0
var _pivot_blend := 0.0
var _stairs_direction := 0
var _terrain_time := 0.0
var _support_side := -1
var _support_toe := Vector3.ZERO
var _support_offset := Vector3.ZERO
var _level_walk := 0.0
var _climb_clip_phase := 0.0
var _was_prone := false
var _last_stance := 0.0
var _feet: Array[Foot] = [Foot.new(), Foot.new()]
var _hip: int
var _hip_offset := Vector3.ZERO
var _settle_age := 1.0
var _settle_first := 0
var _moving := false
var _phase := 0.0
var _clock := 0.0
var _delta := 0.0
var _speed := 0.0
var _leading_leg := 0
var _crouch := 0.0
var _air := 0.0
var _flight_arm_weight := 0.0
var _arm_ascent := 0.0
var _reach_drop := 0.0
var _landing := 0.0
var _landing_age := 1.0
var _climb := 0.0
var _previous_rotations: Dictionary[int, Quaternion] = {}
var _previous_hip := Vector3.ZERO
var _blend_left := 0.0
var _last_yaw := 0.0
var _turn := 0.0
var _look_yaw := 0.0
var _boot_height: Array[float] = []


func bind(skeleton: Skeleton3D, facing: Node3D, model: Node3D,
		use_clips: bool = true, character_path: String = "") -> bool:
	rig = skeleton
	_facing = facing
	for index in rig.get_bone_count():
		_indices[rig.get_bone_name(index)] = index
	for name in TORSO:
		if not _indices.has(name):
			return false
	for side: String in SIDES:
		var joints := PackedInt32Array()
		for name: String in LIMBS:
			var index := rig.find_bone(name + "_" + side)
			if index == -1:
				return false
			joints.append(index)
		_legs.append(joints.slice(0, 4))
		_arms.append(joints.slice(4))
		var tips := PackedInt32Array()
		for finger: String in FINGERS:
			var tip := rig.find_bone(finger + "_03_" + side)
			if tip != -1:
				tips.append(tip)
		_fingertips.append(tips)
	# FBX-derived armatures can keep their source units and axes on a parent node.
	# Solve in the runner's metre-scale frame, then write the pose in native units.
	var rig_space := facing.global_transform.affine_inverse() * rig.global_transform
	var head := rig.get_bone_global_rest(_indices[&"Head"]).origin
	var ankle := rig.get_bone_global_rest(_legs[0][2]).origin
	var standing_span := (rig_space.basis * (head - ankle)).y
	if standing_span < 0.001:
		return false
	if standing_span < 0.75 or standing_span > 1.75:
		model.scale *= 1.22 / standing_span
		rig_space = facing.global_transform.affine_inverse() * rig.global_transform
	_metres_per_unit = rig_space.basis.get_scale().x
	_rig_base = rig_space.orthonormalized()
	for index in rig.get_bone_count():
		var local := rig.get_bone_rest(index)
		local.origin *= _metres_per_unit
		_rest.append(local)
		var rest_global := rig_space * rig.get_bone_global_rest(index)
		_global_rest.append(rest_global.orthonormalized())
		_parents.append(rig.get_bone_parent(index))
	for joints in _legs:
		_boot_height.append(_global_rest[joints[2]].origin.y)
	_hip = _indices[&"Hip"]
	_uses_trial_skin = use_clips
	if _uses_trial_skin:
		_clips.bind(rig)
	elif character_path.get_base_dir() == "res://art/characters":
		var slug := character_path.get_file().get_basename()
		var library := RunnerClip.ROSTER_MOTIONS_PATH.path_join(slug + ".res")
		if not _clips.bind(rig, library, "", _metres_per_unit):
			var run_library := RunnerClip.ROSTER_RUNS_PATH.path_join(slug + ".res")
			_clips.bind(rig, run_library, "", _metres_per_unit)
	_skirt_clearance.bind(rig)
	if use_clips:
		_skirt_clearance.load_cycles()
	for gait in Locomotion.GAITS.size():
		_gait_speeds.append(_clips.speed(Locomotion.GAITS[gait], Locomotion.SPEEDS[gait]))
	rig.reset_bone_poses()
	_tail.bind(model, rig, facing, _uses_trial_skin)
	_last_yaw = _facing.global_rotation.y
	return true


func reset() -> void:
	_forget_contacts()
	_speed = 0.0
	_phase = 0.0
	_settle_age = 1.0
	_moving = false
	_air = 0.0
	_flight_arm_weight = 0.0
	_arm_ascent = 0.0
	_reach_drop = 0.0
	_landing = 0.0
	_landing_age = 1.0
	_climb = 0.0
	_blend_left = 0.0
	_crouch = 0.0
	_idle_hand_weight = 0.0
	_turn = 0.0
	_look_yaw = 0.0
	_clips.reset()
	_tail.reset()
	_skirt_clearance.reset(rig)
	_clip_clock = 0.0
	_turn_action = &""
	_turn_time = 1.0
	_pivot_blend = 0.0
	_pivot_anchor = Vector3.INF
	_stairs_direction = 0
	_support_side = -1
	_support_offset = Vector3.ZERO
	_level_walk = 0.0
	_climb_clip_phase = 0.0
	_was_prone = false
	_last_stance = 0.0
	_last_yaw = _facing.global_rotation.y


func gait_speeds() -> Array[float]:
	return _gait_speeds


func gait_speed(gait: int) -> float:
	return _gait_speeds[gait]


func has_generated_run() -> bool:
	return _clips.has_generated_run()


func portrait() -> void:
	_begin(1.0 / 60.0)
	_torso(Vector3.ZERO, 0.0, 0.0, 0.0)
	for side in 2:
		_arm(side, 4.0, 15.0, 0.18)
		_fingers(side, 12.0)
	_finish()


func ground(
	body: CharacterBody3D, travel: Vector3, stance: float, land_impact: float,
	heading_error: float, stair_grade: float, delta: float, gait: int,
	control: Locomotion, run_requested: bool, run_cadence_scale: float
) -> void:
	var grounded: bool = body.on_walkable_ground()
	if _climb > 0.0 or (not grounded and _air == 0.0):
		_capture_transition()
	_begin(delta)
	_look_yaw = lerpf(_look_yaw, clampf(rad_to_deg(heading_error), -31.0, 31.0), 1.0 - exp(-13.0 * delta))
	_crouch = smoothstep(0.0, 1.0, stance)
	var prone := smoothstep(1.0, 2.0, stance)
	var jump_load := 1.0 - control.load_left / Locomotion.LOAD_TIME if control.flight == Locomotion.Flight.LOAD else 0.0
	_climb = 0.0
	_air = move_toward(_air, float(not grounded), delta / (0.07 if grounded else 0.11))
	if land_impact > 0.0:
		_landing = land_impact
		_landing_age = 0.0
	_landing_age += delta
	var distance := Vector2(travel.x, travel.z).length()
	var moving := distance > delta * 0.065
	if grounded and _moving and not moving and _speed > 0.18:
		_settle_age = 0.0
		_settle_first = 1 if _feet[0].planted else 0
		for foot in _feet:
			foot.stop_from = foot.last_base
	elif moving or not grounded:
		_settle_age = 1.0
	_moving = moving and grounded
	_settle_age += delta
	var previous_speed := _speed
	_speed = lerpf(_speed, minf(distance / delta, SPRINT_SPEED * 1.12), 1.0 - exp(-17.0 * delta))
	var effort := smoothstep(0.1, 0.87, _speed)
	# Keep the ordinary stride length as the capsule covers it more often.
	var stride_speed := _speed / run_cadence_scale
	var profile := _profile(stride_speed).lerp(CROUCH, _crouch)
	var stairs := smoothstep(0.08, 0.40, absf(stair_grade)) * (1.0 - _air)
	profile.x = lerpf(profile.x, 0.72, stairs)
	profile.y = lerpf(profile.y, 0.62, stairs)
	profile.z += stairs * (0.10 if stair_grade > 0.0 else 0.035)
	profile.w += stairs * (5.0 if stair_grade > 0.0 else -1.0)
	var gait_name := Locomotion.GAITS[gait]
	if stairs > 0.56:
		_stairs_direction = 1 if stair_grade > 0.0 else -1
	elif stairs < 0.20:
		_stairs_direction = 0
	if _stairs_direction != 0:
		gait_name = &"stairs-up" if _stairs_direction > 0 else &"stairs-down"
	var generated_run := run_requested and has_generated_run() and _moving and stance < 0.02 \
		and control.flight == Locomotion.Flight.GROUNDED and _stairs_direction == 0 and absf(heading_error) < 0.85
	if generated_run:
		gait_name = &"run"
	elif has_generated_run() and gait_name == &"run":
		gait_name = &"jog"
	var native_period := _clips.period(gait_name, profile.x)
	var native_stride := _clips.speed(gait_name, maxf(0.65, stride_speed)) * native_period
	if _stairs_direction != 0:
		# Walk one tread per footfall. At a run, cover more treads per
		# swing so horizontal momentum does not fast-forward the legs.
		native_stride = maxf(2.0 * body.tread_depth, stride_speed * 0.56)
	var stride := maxf(0.65, stride_speed) * profile.x
	if _clips.has(gait_name):
		stride = lerpf(stride, native_stride, smoothstep(0.12, 0.72, _speed) * (1.0 - _crouch))
	if _stairs_direction != 0:
		stride = native_stride
	if grounded:
		var phase_step := delta * run_cadence_scale / native_period if generated_run else minf(distance, SPRINT_SPEED * delta * 1.18) / stride
		_phase = fposmod(_phase + phase_step, 1.0)
		if _air == 0.0:
			_leading_leg = 0 if fposmod(_phase + 0.25, 1.0) < 0.5 else 1
	else:
		_forget_contacts()
	var cadence := _phase * TAU
	var run := smoothstep(WALK_SPEED, JOG_SPEED, _speed) * (1.0 - _crouch)
	var sprint := smoothstep(JOG_SPEED, SPRINT_SPEED, _speed) * (1.0 - _crouch)
	var weight_shift := sin(cadence - 0.35) * 0.025 * effort
	var acceleration := clampf((_speed - previous_speed) / maxf(delta, 0.001) * 0.24, -4.0, 4.0)
	var air_phase := clampf(0.5 - body.velocity.y / 12.0, 0.0, 1.0)
	var tuck := sin(air_phase * PI) * _air
	var push := (1.0 - smoothstep(0.0, 0.5, air_phase)) * _air
	var compression := smoothstep(0.0, 0.073, _landing_age) * (1.0 - smoothstep(0.073, 0.29, _landing_age))
	var dip := 0.15 * _landing * compression + 0.075 * jump_load
	var bob := lerpf(0.013, 0.035, run) * -cos(2.0 * cadence - 0.8) * effort
	var shift := Vector3(weight_shift, -0.025 - 0.285 * _crouch - 0.07 * run - dip + bob, -0.17 * _crouch + acceleration * 0.006)
	# Transfer weight before each heel strike and rise over the supporting foot.
	var walking := effort * (1.0 - run) * (1.0 - _air) * (1.0 - _crouch)
	shift.y -= 0.060 * walking * (0.5 + 0.5 * cos(2.0 * cadence))
	var lean := maxf(0.0, profile.w * lerpf(effort, 1.0, _crouch) + acceleration * 0.65 + dip * 57.0)
	lean = lerpf(lean, minf(lean, 12.0), tuck)
	var yaw := cos(cadence - 0.24) * lerpf(5.0, 8.0, run) * effort

	var targets: Array[Vector3] = []
	var pitch: Array[float] = []
	var floor_normals: Array[Vector3] = []
	for side in 2:
		_ground_foot(body, side, profile, stride, effort, tuck, targets, pitch, floor_normals)
	# When a foot is below the capsule, drop the pelvis enough to keep that leg in reach.
	var knee_y := shift.y
	for side in 2:
		var joints := _legs[side]
		# During walking, the incoming leg already needs room before heel strike.
		# Loading the reach correction only after contact pops the pelvis downward.
		if _air > 0.1:
			continue
		var thigh := _global_rest[joints[0]].origin + shift
		var offset := targets[side] - thigh
		var available := _length(joints[0], joints[1]) + _length(joints[1], joints[2]) - 0.008
		var vertical := sqrt(maxf(0.08, available * available - offset.x * offset.x - offset.z * offset.z))
		var phase := fposmod(_phase + side * 0.5, 1.0)
		var preparing := smoothstep(profile.y + (1.0 - profile.y) * 0.48, 0.95, phase)
		var support := 1.0 if _feet[side].planted else (1.0 - run) * preparing
		knee_y = minf(knee_y, shift.y + minf(0.0, targets[side].y + vertical - thigh.y) * support)
	var reach_drop := clampf(shift.y - knee_y, 0.0, 0.18)
	_reach_drop = lerpf(_reach_drop, reach_drop, 1.0 - exp(-16.0 * delta))
	shift.y -= lerpf(reach_drop, _reach_drop, walking)
	_sample_ground_action(gait_name, stance, control, grounded, heading_error, delta)
	_update_level_walk(body.global_position.y, floor_normals, stair_grade, heading_error, grounded, delta)
	# Extract authored vertical motion into the pose before contacts are solved.
	var direct_run := generated_run and _clips.action == &"run"
	if direct_run and _clips.pelvis.is_finite():
		var parent := _pose(_parents[_hip])
		var run_shift := parent.basis * (_clips.pelvis * _metres_per_unit - _rest[_hip].origin)
		shift = shift.lerp(run_shift, _clips.weight)
	elif _clips.pelvis.is_finite() and _clips.weight > 0.0 and _air < 0.12 and stance < 0.10:
		var parent := _pose(_parents[_hip])
		var clip_shift := parent.basis * (_clips.pelvis * _metres_per_unit - _rest[_hip].origin)
		shift.y = lerpf(shift.y, clampf(clip_shift.y, -0.16, 0.055), _clips.weight * (1.0 - 0.6 * stairs))
		var sway := parent.basis * (_clips.walk_sway * _metres_per_unit)
		shift = shift.lerp(Vector3(sway.x, clip_shift.y, sway.z), _level_walk * _clips.weight)
	shift.y -= 0.37 * prone
	if _clips.action == &"prone" and _clips.pelvis.is_finite():
		var clip_shift := _pose(_parents[_hip]).basis * (_clips.pelvis * _metres_per_unit - _rest[_hip].origin)
		shift.y = lerpf(shift.y, clampf(clip_shift.y, -0.72, -0.26), _clips.weight * prone)
	lean = lerpf(lean, 78.0, prone)
	_torso(shift, lean, yaw, -_turn * 8.0 + weight_shift * 92.0)
	var torso_strength := 0.45 if _clips.action in [&"turn-left", &"turn-right"] else 1.0
	if _stairs_direction != 0:
		torso_strength *= 0.60
	_apply_clip(RunnerClip.TORSO, torso_strength)
	if _was_prone and _clips.action != &"rise":
		# Reverse the face-down pose into a squat, then extend the knees
		# and bring the trunk upright in sync with capsule clearance.
		_lean(lerpf(22.0 * _crouch, 82.0, prone))
	elif _clips.weight < 0.5:
		_lean(lean)
	for side in 2:
		_leg(side, targets[side], pitch[side], floor_normals[side])
		var swing := -cos(cadence + side * PI - 0.22)
		var front := lerpf(28.0, 46.0, run) + 5.0 * sprint
		var rear := lerpf(29.0, 54.0, run) + 22.0 * sprint
		var upper_arm := swing * (front if swing > 0.0 else rear) * effort * (1.0 - 0.70 * _air)
		var raise := rad_to_deg(atan(0.85 * _crouch + 1.3 * tuck + 0.48 * push + dip * 4.0 - 0.80 * jump_load))
		# Open the trailing elbow so the wrist follows the upper arm behind the pelvis.
		var running_flex := lerpf(39.0 - 10.0 * sprint, 76.0 + 6.0 * sprint, smoothstep(-1.0, 0.87, swing))
		var flex := lerpf(14.0, running_flex, run * effort) + 11.0 * _crouch + 16.0 * tuck
		_arm(side, upper_arm + raise, flex, 0.16 + 0.20 * tuck)
		var curl := 22.0 * (1.0 - smoothstep(0.02, 0.18, _speed)) if _uses_trial_skin else 12.0 + 22.0 * run * effort
		_fingers(side, lerpf(curl, 28.0, _air))
	var flight_strength := 1.0 - 0.38 * smoothstep(0.25, 0.62,
		control.flight_age) if control.flight == Locomotion.Flight.DOUBLE_JUMP else 1.0
	_apply_clip(RunnerClip.LEGS, flight_strength)
	_apply_clip(RunnerClip.ARMS, flight_strength)
	var relaxing := _clips.action == &"idle" and grounded and stance < 0.02
	_idle_hand_weight = move_toward(_idle_hand_weight, float(relaxing), delta / 0.17)
	if _idle_hand_weight > 0.0:
		_relax_hands(smoothstep(0.0, 1.0, _idle_hand_weight))
	_flight_arm_weight = move_toward(_flight_arm_weight, float(not grounded or jump_load > 0.0),
		delta / (0.15 if grounded else 0.11))
	if _flight_arm_weight > 0.0:
		var ascent := clampf(body.velocity.y / Locomotion.TAKEOFF, -1.0, 1.0) if not grounded else -jump_load
		_arm_ascent = lerpf(_arm_ascent, ascent, 1.0 - exp(-15.0 * delta))
		_balance_jump_arms(smoothstep(0.0, 1.0, _flight_arm_weight), run * effort)
	if not direct_run and _clips.weight > 0.0 and grounded and prone < 0.12:
		_apply_ground_contacts(targets, pitch, floor_normals, profile.y, stairs)
	_settle_support_toe(grounded and stance < 0.02 and _stairs_direction == 0
		and _clips.action in [&"walk", &"jog"] and absf(heading_error) < 0.22, delta)
	if grounded and stance < 0.05:
		_turn_step(heading_error, delta)
	else:
		_pivot_blend = 0.0
	_blend_transition(delta)
	if grounded:
		# Start guiding the ankles as soon as the probe sees the flight,
		# including the last flat stride before the capsule crosses the edge.
		_follow_tread(absf(travel.y) > 0.002 or absf(stair_grade) > 0.025, delta)
	_skirt()
	_finish()
	var tail_effort := smoothstep(0.08, gait_speed(gait), _speed) * (1.0 - _crouch) * (1.0 - _air)
	_tail.step(_phase, gait, tail_effort, _turn, 4.0 * tail_effort + 12.0 * sprint + 18.0 * _crouch + 17.0 * tuck, delta)


# Cancel residual planar drift at the lowest shoe with a small translation
# of the rendered pelvis. Source rotations and capsule travel stay independent.
func _settle_support_toe(enabled: bool, delta: float) -> void:
	var side := -1
	var toes: Array[Vector3] = []
	if enabled:
		for leg in _legs:
			toes.append(_facing.to_global(_pose(leg[3]).origin))
		var lower := 0 if toes[0].y < toes[1].y else 1
		if _support_side >= 0 and toes[_support_side].y < toes[lower].y + 0.012:
			lower = _support_side
		if _feet[lower].has_floor and absf(toes[lower].y - _feet[lower].floor_y) < 0.020:
			side = lower
	if side >= 0:
		if side != _support_side:
			_support_toe = toes[side] + _support_offset * 0.35
		var correction := (_support_toe - toes[side]).slide(Vector3.UP).limit_length(0.055)
		_support_offset = _support_offset.move_toward(correction, 0.48 * delta)
	else:
		_support_offset = _support_offset.move_toward(Vector3.ZERO, 0.30 * delta)
	_support_side = side
	_hip_offset += _facing.global_basis.inverse() * _support_offset
	_poses.clear()


func _turn_step(heading_error: float, delta: float) -> void:
	var turning := absf(heading_error) > 0.85 or (_pivot_blend > 0.0 and absf(_turn) > 0.48)
	if turning and _pivot_blend == 0.0:
		var left := _feet[0].displayed_ankle
		var right := _feet[1].displayed_ankle
		if not left.is_finite() or not right.is_finite():
			return
		_pivot_side = 0 if left.y < right.y else 1
		_pivot_anchor = _feet[_pivot_side].displayed_ankle
		_pivot_yaw = _facing.rotation.y
		# Retire anchors from the incoming stride. The swing foot can now
		# travel with the heading while the lower foot supplies the push-off.
		for foot in _feet:
			foot.planted = false
			foot.has_position = false
	_pivot_blend = move_toward(_pivot_blend, float(turning), delta / (0.065 if turning else 0.18))
	if _pivot_blend <= 0.0:
		return
	var yaw := absf(angle_difference(_pivot_yaw, _facing.rotation.y))
	var hold := 1.0 - smoothstep(0.10, 0.62, yaw)
	for side in 2:
		var joints := _legs[side]
		var ankle := _pose(joints[2])
		var sign_x := 1.0 if side == 0 else -1.0
		var target := ankle.origin
		target.x = sign_x * clampf(sign_x * target.x, 0.066, 0.16)
		target.z = clampf(target.z, -0.18, 0.20)
		if side == _pivot_side and _pivot_anchor.is_finite():
			var anchor := _facing.to_local(_pivot_anchor)
			anchor.x = sign_x * maxf(0.055, sign_x * anchor.x)
			target = target.lerp(anchor, hold)
		else:
			target.y += 0.045 * sin(PI * clampf(yaw / 1.5, 0.0, 1.0))
		var goal := _facing.to_global(ankle.origin.lerp(target, _pivot_blend))
		var last := _feet[side].displayed_ankle
		if last.is_finite():
			goal = last.move_toward(goal, (2.1 + _speed) * delta)
		target = _facing.to_local(goal)
		target.x = sign_x * maxf(sign_x * target.x, 0.035 * _pivot_blend)
		_solve(joints, target, Vector3(sign_x * 0.12, 0.05, 1.0))
		var neutral := _global_rest[joints[2]].basis.get_rotation_quaternion()
		_orient(joints[2], ankle.basis.get_rotation_quaternion().slerp(neutral, 0.75 * _pivot_blend))


func _follow_tread(changing_height: bool, delta: float) -> void:
	_terrain_time = 0.24 if changing_height else maxf(0.0, _terrain_time - delta)
	for side in 2:
		var foot := _feet[side]
		var leg := _legs[side]
		var ankle := _pose(leg[2])
		var world := _facing.to_global(ankle.origin)
		if _terrain_time > 0.0 and foot.displayed_ankle.is_finite():
			# A new ray hit or a gait handoff can put the IK goal on the
			# next tread at once. Limit travel at both ends of the shoe.
			var limit := (1.65 + 1.6 * _speed) * delta
			var next := foot.displayed_ankle.move_toward(world, limit)
			if foot.displayed_toe.is_finite():
				var toe := _facing.to_global(_pose(leg[3]).origin) + next - world
				next += foot.displayed_toe.move_toward(toe, limit) - toe
			if next.distance_squared_to(world) > 0.000001:
				var knee := _pose(leg[1]).origin - _pose(leg[0]).origin
				_solve(leg, _facing.to_local(next), knee)
				_orient(leg[2], ankle.basis.get_rotation_quaternion())
				world = _facing.to_global(_pose(leg[2]).origin)
		foot.displayed_ankle = world
		foot.displayed_toe = _facing.to_global(_pose(leg[3]).origin)


func _capture_transition() -> void:
	_previous_rotations = _rotations.duplicate()
	_previous_hip = _hip_offset
	_blend_left = POSE_BLEND_TIME


func _blend_transition(delta: float) -> void:
	if _blend_left > 0.0:
		var blend := smoothstep(0.0, POSE_BLEND_TIME, _blend_left)
		for index in _rotations:
			if _previous_rotations.has(index):
				_rotations[index] = _rotations[index].slerp(_previous_rotations[index], blend)
		_hip_offset = _hip_offset.lerp(_previous_hip, blend)
		_blend_left = maxf(0.0, _blend_left - delta)
		_poses.clear()


func begin_climb_transfer() -> void:
	_capture_transition()


func climb(foot_holds: Array[Vector3], hand_holds: Array[Vector3], at_top: float, delta: float,
		on_wall: bool, clip: StringName, phase: float, travel_rate: float) -> void:
	if _climb == 0.0:
		_moving = false
		_settle_age = 1.0
		_capture_transition()
		_speed = 0.0
		_climb_clip_phase = phase
	_begin(delta)
	_forget_contacts()

	_look_yaw = move_toward(_look_yaw, 0.0, 130.0 * delta)
	_climb = move_toward(_climb, 1.0, delta / 0.20)
	_crouch = 0.0
	_air = 0.0
	_reach_drop = 0.0
	_landing = 0.0
	_landing_age = 1.0
	var inverse := _facing.global_transform.affine_inverse()
	var support := 0.0
	if on_wall:
		var grip := inverse * hand_holds[0]
		support = (1.0 - smoothstep(0.35, 1.26, grip.y)) * (1.0 - at_top)
	var loop := clip != &"mantle"
	if loop:
		_climb_clip_phase = fposmod(_climb_clip_phase + travel_rate * delta / _clips.period(clip, 1.0), 1.0)
		phase = _climb_clip_phase
	_clips.sample(clip, phase, loop, delta)
	var shift := Vector3(0.0, -0.08 - 0.30 * support, 0.015 + 0.10 * support)
	_torso(shift * _climb, (11.0 + 32.0 * support) * _climb, 0.0, 0.0)
	_apply_clip(RunnerClip.TORSO, 0.40 if on_wall else 0.22)
	_apply_clip(RunnerClip.LEGS, 0.7)
	_apply_clip(RunnerClip.ARMS, 0.7)
	if on_wall and support > 0.0 and _clips.uses_roster_motions():
		_fit_ledge_reach(hand_holds, inverse, at_top, support)
	for side in 2:
		var sign_value := 1.0 if side == 0 else -1.0
		var ankle := _global_rest[_legs[side][2]].origin
		var foot := inverse * foot_holds[side]
		var toe_brace := 0.0 if on_wall else _climb * (1.0 - at_top)
		foot.y += _boot_height[side] + 0.039 * toe_brace
		_leg(side, ankle.lerp(foot, _climb), 17.0 * toe_brace, Vector3.UP)
		var joints := _arms[side]
		var hand := inverse * hand_holds[side]
		hand.y -= 0.026 * (1.0 - at_top)
		var neutral := Vector3(sign_value * 0.15, 0.87, 0.04)
		var bend := Vector3(sign_value * 0.54, -1.0, -0.3)
		var bent_arm := (_pose(joints[1]).origin - _pose(joints[0]).origin).normalized()
		_solve(joints, neutral.lerp(hand, _climb), bend.lerp(bent_arm, _clips.weight * 0.47))
		var forearm := _pose(joints[2]).origin - _pose(joints[1]).origin
		_aim(joints[2], joints[3], forearm.normalized().lerp(Vector3(0.0, 0.56, 0.82), _climb * (1.0 - at_top)))
		_fingers(side, lerpf(12.0, 38.0, _climb * (1.0 - at_top)))
	_skirt()
	_blend_transition(delta)
	_finish()
	_tail.step(_phase, Locomotion.Gait.WALK, 0.0, 0.0, 14.0, delta)


func _fit_ledge_reach(hand_holds: Array[Vector3], inverse: Transform3D, at_top: float, support: float) -> void:
	var correction := Vector3.ZERO
	for side in 2:
		var arm := _arms[side]
		var reach := _length(arm[0], arm[1]) + _length(arm[1], arm[2]) - 0.001
		var target := inverse * hand_holds[side] - Vector3.UP * (0.026 * (1.0 - at_top))
		var offset := target - _pose(arm[0]).origin
		var excess := offset - offset.limit_length(reach)
		if excess.length_squared() > correction.length_squared():
			correction = excess
	_hip_offset += correction.limit_length(_length(_arms[0][0], _arms[0][1])) * support
	_poses.clear()


func vault(phase: float, handhold: Vector3, delta: float) -> void:
	_begin(delta)
	_forget_contacts()
	_clips.sample(&"vault", phase, false, delta)
	var tuck := sin(PI * phase)
	_torso(Vector3(0.0, -0.09 * tuck, 0.06 * tuck), 22.0 * tuck, 0.0, 0.0)
	for side in 2:
		var ankle := _global_rest[_legs[side][2]].origin
		_leg(side, ankle + Vector3(0, 0.29 * tuck, (0.27 - side * 0.12) * tuck), 16.0 * tuck, Vector3.UP)
		_arm(side, (37.0 - side * 16.0) * tuck, 26.0, 0.23)
	_apply_clip(RunnerClip.TORSO)
	_apply_clip(RunnerClip.LEGS)
	_apply_clip(RunnerClip.ARMS)
	var hip := _pose(_hip)
	var chest := _pose(_indices[&"Neck"]).origin - hip.origin
	var tilt := rad_to_deg(atan2(chest.z, chest.y))
	_lean(clampf(tilt, -10.0, 40.0))
	var brace := smoothstep(0.21, 0.36, phase) * (1.0 - smoothstep(0.53, 0.69, phase))
	if brace > 0.0:
		var arm := _arms[0]
		var contact := _facing.to_local(handhold) + Vector3(0.14, 0.08, 0.0)
		var wrist := _pose(arm[2]).origin
		_solve(arm, wrist.lerp(contact, brace), Vector3(0.52, 0.10, -0.40))
	_skirt()
	_finish()
	_tail.step(_phase, Locomotion.Gait.WALK, 0.0, 0.0, 11.0 * tuck, delta)


func kick(phase: float, ball_contact: Vector3, strike_phase: float, delta: float) -> void:
	_begin(delta)
	_forget_contacts()
	_speed = 0.0
	_moving = false
	_settle_age = 1.0
	_clips.sample(&"kick", phase, false, delta)
	var swing := sin(PI * phase)
	_torso(Vector3(-0.02 * swing, -0.045 * swing, 0.0), 8.0 * swing, 0.0, 0.0)
	for side in 2:
		var foot := _global_rest[_legs[side][2]].origin
		_leg(side, foot, 0.0, Vector3.UP)
		_arm(side, (1.0 if side == 0 else -1.0) * 16.0 * swing, 16.0, 0.19)
	_apply_clip(RunnerClip.TORSO)
	_apply_clip(RunnerClip.LEGS)
	_apply_clip(RunnerClip.ARMS)

	# Steer the generated swing into the actual ball only around the strike.
	var contact := 1.0 - smoothstep(0.0, 0.23, absf(phase - strike_phase))
	var joints := _legs[1]
	var ankle := _pose(joints[2])
	var toe := _pose(joints[3]).origin
	var target := _facing.to_local(ball_contact)
	_solve(joints, ankle.origin + (target - toe) * contact, Vector3(-0.12, 0.02, 1.0))
	_orient(joints[2], ankle.basis.get_rotation_quaternion())
	_skirt()
	_finish()
	_tail.step(_phase, Locomotion.Gait.WALK, 0.0, 0.0, 0.0, delta)


func kick_toe_position() -> Vector3:
	return _facing.to_global(_pose(_legs[1][3]).origin)


func _profile(speed: float) -> Vector4:
	if speed <= JOG_SPEED:
		return WALK.lerp(JOG, smoothstep(WALK_SPEED, JOG_SPEED, speed))
	return JOG.lerp(SPRINT, smoothstep(JOG_SPEED, SPRINT_SPEED, speed))


func _ground_foot(
	body: CharacterBody3D, side: int, profile: Vector4, stride: float, blend: float, tuck: float,
	targets: Array[Vector3], pitches: Array[float], normals: Array[Vector3]
) -> void:
	var transform := _facing.global_transform
	var inverse := transform.affine_inverse()
	var state := _feet[side]
	var sign_value := 1.0 if side == 0 else -1.0
	var foot_phase := fposmod(_phase + side * 0.5, 1.0)
	var stance := profile.y
	var rest := _global_rest[_legs[side][2]].origin
	var neutral := Vector3(rest.x + sign_value * (0.015 + 0.035 * _crouch), 0.0, rest.z)
	var excursion := stride * stance * 0.5
	var neutral_world := transform * neutral
	var pivot := smoothstep(0.30, 0.86, absf(_turn))
	var base := neutral_world
	var lift := 0.0
	var roll := 0.0
	if blend > 0.02 and _air < 0.25:
		var contact := transform * (neutral + Vector3.BACK * excursion * blend)
		if foot_phase < stance:
			if not state.planted:
				state.anchor = state.last_base if state.has_position else contact
			state.planted = true
			if pivot > 0.0:
				var local_anchor := inverse * state.anchor - neutral
				if local_anchor.x * sign_value < -0.035 or local_anchor.length() > 0.26:
					state.anchor = state.anchor.lerp(neutral_world, pivot)
			base = base.lerp(state.anchor, blend)
			var support := foot_phase / stance
			roll = lerpf(-11.0 * (1.0 - _crouch) * (1.0 - smoothstep(WALK_SPEED, SPRINT_SPEED, _speed)),
				0.0, smoothstep(0.0, 0.24, support))
			roll += lerpf(0.0, lerpf(23.0, 38.0, smoothstep(WALK_SPEED, SPRINT_SPEED, _speed)),
				smoothstep(0.68, 1.0, support))
		else:
			if state.planted or not state.has_position:
				state.lift_off = state.anchor if state.has_position else transform * (neutral - Vector3.BACK * excursion * blend)
			state.planted = false
			var swing := (foot_phase - stance) / (1.0 - stance)
			var ahead := maxf(0.0, (1.0 - foot_phase) * stride) * blend
			var forward := transform.basis.z.normalized()
			var next_contact := contact + forward * ahead
			var release := state.lift_off.lerp(neutral_world, pivot)
			var in_flight := release.lerp(next_contact, smoothstep(0.0, 1.0, swing))
			var overreach := (in_flight - contact).dot(forward)
			if overreach > 0.0:
				# Preserve some toe reach at the end of swing without throwing the foot forward.
				const TOE_REACH := 0.055
				in_flight -= forward * (overreach - TOE_REACH * tanh(overreach / TOE_REACH))
			base = base.lerp(in_flight, blend)
			lift = pow(sin(PI * pow(swing, 0.91)), 1.45) * profile.z * blend
			var running := smoothstep(WALK_SPEED, SPRINT_SPEED, _speed)
			var toe_off := lerpf(23.0, 38.0, running)
			var heel_strike := -11.0 * (1.0 - _crouch) * (1.0 - running)
			roll = toe_off * (1.0 - smoothstep(0.12, 0.78, swing)) + heel_strike * smoothstep(0.65, 1.0, swing)
	else:
		state.planted = false
	# Finish the last step, then collect the support foot. Moving again interrupts
	# the settle from the current foot positions.
	if _settle_age < 0.36:
		var delay := 0.0 if side == _settle_first else 0.16
		var collect := smoothstep(delay, delay + 0.19, _settle_age)
		var start := state.stop_from
		start.y = base.y
		base = start.lerp(neutral_world, collect)
		lift = sin(PI * collect) * minf(0.055, start.distance_to(neutral_world) * 0.27)
		roll *= 1.0 - smoothstep(0.0, 0.16, _settle_age)
		state.planted = collect == 0.0 or collect == 1.0
		state.anchor = base
		state.lift_off = base
	state.has_position = (_settle_age < 0.36 or blend > 0.02) and _air < 0.25
	state.last_base = Vector3(base.x, transform.origin.y, base.z)

	var normal := Vector3.UP
	state.has_floor = false
	if _air < 0.7:
		var query := PhysicsRayQueryParameters3D.create(
			state.last_base + Vector3.UP * 0.34, state.last_base - Vector3.UP * 0.40,
			body.collision_mask, [body.get_rid()]
		)
		var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.normal.y > 0.60:
			state.has_floor = true
			normal = (inverse.basis * hit.normal).normalized()
		var floor_height: float = hit.position.y if state.has_floor else transform.origin.y
		if is_inf(state.floor_y):
			state.floor_y = floor_height
		else:
			state.floor_y = move_toward(state.floor_y, floor_height, 1.65 * body.get_physics_process_delta_time())
		base.y = lerpf(state.floor_y, transform.origin.y, _air)
	var target := inverse * base + Vector3.UP * (_boot_height[side] + lift)
	var leading := side == _leading_leg
	var aerial := rest + Vector3(0.013 * sign_value,
		tuck * (0.27 if leading else 0.16), tuck * (0.14 if leading else -0.12))
	target = target.lerp(aerial, _air)
	roll = lerpf(roll * blend, 22.0 * tuck, _air)
	var sole_pivot := Vector3(0, -_boot_height[side], -0.044 if roll < 0.0 else 0.151)
	var pitch := Quaternion(Vector3.RIGHT, deg_to_rad(roll))
	target += sole_pivot - pitch * sole_pivot
	targets.append(target)
	pitches.append(roll)
	normals.append(normal)


func _sample_ground_action(gait: StringName, stance: float, control: Locomotion,
		grounded: bool, heading_error: float, delta: float) -> void:
	_clip_clock += delta
	var name := gait if _speed > 0.16 else &"idle"
	var phase := _phase if name == gait else _clip_clock / _clips.period(name, 2.0)
	var loop := true
	_turn_time += delta
	if grounded and stance < 0.08 and absf(heading_error) > 1.18 and _speed > 0.75 and _turn_time > 0.55:
		_turn_action = &"turn-left" if heading_error > 0.0 else &"turn-right"
		_turn_time = 0.0
	if not grounded or control.flight == Locomotion.Flight.LOAD:
		match control.flight:
			Locomotion.Flight.LOAD:
				name = &"jump"
				phase = _clips.jump_takeoff_phase() * (1.0 - control.load_left / Locomotion.LOAD_TIME)
			Locomotion.Flight.JUMP:
				name = &"jump"
				phase = lerpf(_clips.jump_takeoff_phase(), 1.0, clampf(control.flight_age / 0.96, 0.0, 1.0))
			Locomotion.Flight.DOUBLE_JUMP:
				name = &"double-jump"
				phase = lerpf(0.19, 1.0, clampf(control.flight_age / 0.52, 0.0, 1.0))
			_:
				name = &"land"
				phase = 0.0
		loop = false
	elif _landing_age < 0.27 and _landing > 0.0 and stance < 0.05:
		name = &"land"
		phase = _landing_age / 0.27
		loop = false
	elif stance > 1.02:
		name = &"prone"
		phase = clampf((stance - 1.0) * 1.08, 0.0, 0.98)
		if _was_prone and _clips.uses_roster_motions() and _clips.has(&"rise") and (
				stance < _last_stance or (is_equal_approx(stance, _last_stance) and _clips.action == &"rise")):
			name = &"rise"
			phase = clampf(2.0 - stance, 0.0, 1.0)
		loop = false
		_was_prone = true
	elif stance > 0.02:
		name = &"squat"
		phase = stance * 0.85
		loop = false
	elif _turn_time < 0.31 and _clips.has(_turn_action):
		name = _turn_action
		phase = _turn_time / 0.31
		loop = false
	if stance <= 0.001:
		_was_prone = false
	_last_stance = stance
	_clips.sample(name, phase, loop, delta)


func _apply_clip(bones: Array, strength: float = 1.0) -> void:
	if _clips.weight <= 0.0:
		return
	for bone: StringName in bones:
		if not _clips.pose.has(bone) or not _indices.has(bone):
			continue
		var index := _indices[bone]
		var base: Quaternion = _rotations.get(index, _rest[index].basis.get_rotation_quaternion())
		_set_rotation(index, base.slerp(_clips.pose[bone], _clips.weight * strength))


func _relax_hands(weight: float) -> void:
	for side in 2:
		var arm := _arms[side]
		var sign_x := 1.0 if side == 0 else -1.0
		var wrist := _pose(arm[2]).origin
		var elbow := _pose(arm[1]).origin
		var shoulder := _pose(arm[0]).origin
		var outside := Vector3(sign_x * (absf(shoulder.x) + 0.097), wrist.y, wrist.z)
		_solve(arm, wrist.lerp(outside, weight), elbow - shoulder)
		var forearm := (_pose(arm[2]).origin - _pose(arm[1]).origin).normalized()
		_align_palm(side, forearm, weight)


func _align_palm(side: int, forearm: Vector3, weight: float, thumb_axis: Vector3 = Vector3.BACK) -> void:
	var wrist := _arms[side][2]
	var lateral := forearm if side == 0 else -forearm
	var up := thumb_axis.cross(lateral).normalized()
	var axes := Basis(lateral, up, lateral.cross(up)).get_rotation_quaternion()
	var rest := _global_rest[wrist].basis.get_rotation_quaternion()
	_orient(wrist, _pose(wrist).basis.get_rotation_quaternion().slerp(axes * rest, weight))


# Pose both segments in the runner's facing frame. Let the forward arm follow
# the opposite driving knee, then open both elbows for balance on descent.
func _balance_jump_arms(weight: float, running: float) -> void:
	var rising := maxf(_arm_ascent, 0.0)
	var falling := maxf(-_arm_ascent, 0.0)
	for side in 2:
		var arm := _arms[side]
		var shoulder := _parents[arm[0]]
		var chain := [shoulder, arm[0], arm[1], arm[2]]
		var source: Array[Quaternion] = []
		for index: int in chain:
			var rest_rotation := _rest[index].basis.get_rotation_quaternion()
			source.append(_rotations.get(index, rest_rotation))
			_set_rotation(index, rest_rotation)
		var drive := (1.0 if side != _leading_leg else -1.0) * running
		var swing := 7.0 + 28.0 * rising - 12.0 * falling + drive * (16.0 + 13.0 * rising)
		var flex := 39.0 + 20.0 * rising - 17.0 * falling + drive * 9.0
		var outward := 1.0 if side == 0 else -1.0
		var upper := Vector3.DOWN.rotated(Vector3.RIGHT, deg_to_rad(-swing))
		var lower := Vector3.DOWN.rotated(Vector3.RIGHT, deg_to_rad(-swing - flex))
		upper.x = outward * (0.24 + 0.30 * falling)
		lower.x = outward * (0.04 + 0.26 * falling - 0.12 * maxf(0.0, drive))
		_aim(arm[0], arm[1], upper)
		_aim(arm[1], arm[2], lower)
		# Rotate the thumb up with the forearm, including when the leading
		# hand rises through horizontal. A fixed forward axis flips here.
		var thumb := Vector3(0.0, lower.z, -lower.y)
		_align_palm(side, lower.normalized(), 1.0, thumb)
		for i in chain.size():
			_set_rotation(chain[i], source[i].slerp(_rotations[chain[i]], weight))


func _apply_ground_contacts(targets: Array[Vector3], pitch: Array[float],
		normals: Array[Vector3], stance: float, stairs: float) -> void:
	# Blend onto the world anchors during support, then return to the authored swing.
	for side in 2:
		var phase := fposmod(_phase + float(side) * 0.5, 1.0)
		var support := smoothstep(0.0, 0.09, phase)
		support *= 1.0 - smoothstep(stance - 0.09, stance + 0.045, phase)
		support = maxf(support, 1.0 - smoothstep(0.12, 0.40, _speed))
		support = maxf(support, stairs * 0.72)
		if _clips.action in [&"turn-left", &"turn-right"]:
			support *= 1.0 - smoothstep(0.28, 0.85, absf(_turn))
		var weight := support * _clips.weight * (1.0 - _level_walk)
		if weight < 0.001:
			continue
		var joints := _legs[side]
		var ankle := _pose(joints[2])
		var toe := joints[3]
		var toe_rotation: Quaternion = _rotations[toe]
		var knee := _pose(joints[1]).origin - _pose(joints[0]).origin
		var pole := knee.normalized().slerp(Vector3(0.12 if side == 0 else -0.12, 0.02, 1.0).normalized(), weight)
		_solve(joints, ankle.origin.lerp(targets[side], weight), pole)
		var ground_rotation := Quaternion(Vector3.UP, normals[side]) * Quaternion(Vector3.RIGHT, deg_to_rad(pitch[side]))
		_orient(joints[2], ankle.basis.get_rotation_quaternion().slerp(
			ground_rotation * _global_rest[joints[2]].basis.get_rotation_quaternion(), weight))
		_spin(StringName("Toe_" + SIDES[side]), Vector3(-0.24 * maxf(pitch[side], 0.0), 0.0, 0.0))
		_set_rotation(toe, toe_rotation.slerp(_rotations[toe], weight))


func _update_level_walk(height: float, normals: Array[Vector3], grade: float, heading_error: float,
		grounded: bool, delta: float) -> void:
	var preserve := 0.0
	if _clips.action == &"walk" and grounded and _stairs_direction == 0:
		var speed_ratio := _speed / gait_speed(Locomotion.Gait.WALK)
		preserve = smoothstep(0.55, 0.94, speed_ratio)
		preserve *= 1.0 - smoothstep(0.10, 0.42, absf(heading_error))
		preserve *= 1.0 - smoothstep(0.025, 0.13, absf(grade))
		for side in 2:
			var foot := _feet[side]
			if not foot.has_floor:
				preserve = 0.0
				break
			preserve *= 1.0 - smoothstep(0.015, 0.07, absf(foot.floor_y - height))
			preserve *= 1.0 - smoothstep(0.003, 0.035, 1.0 - normals[side].y)
	_level_walk = move_toward(_level_walk, preserve, delta / 0.15)


func _begin(delta: float) -> void:
	_delta = delta
	_clock += delta
	_rotations.clear()
	_poses.clear()
	_hip_offset = Vector3.ZERO
	var yaw := _facing.global_rotation.y
	_turn = lerpf(_turn, clampf(angle_difference(_last_yaw, yaw) / delta / 7.0, -1.0, 1.0),
		1.0 - exp(-12.0 * delta))
	_last_yaw = yaw


func _forget_contacts() -> void:
	_support_side = -1
	_support_offset = Vector3.ZERO
	_terrain_time = 0.0
	for foot in _feet:
		foot.planted = false
		foot.has_position = false
		foot.has_floor = false
		foot.floor_y = INF
		foot.displayed_ankle = Vector3.INF
		foot.displayed_toe = Vector3.INF


func _torso(shift: Vector3, lean: float, yaw: float, bank: float) -> void:
	_hip_offset = shift
	var breath := sin(_clock * 2.7) * 0.85
	_spin(&"Hip", Vector3(lean * 0.55, yaw, bank * 0.42))
	_spin(&"Waist", Vector3(0.0, -yaw * 0.7, bank * 0.26))
	_spin(&"Chest", Vector3(breath, -yaw * 0.85 + _look_yaw * 0.13, bank * 0.32))
	_spin(&"Neck", Vector3(-lean * 0.27, _turn * 4.0 + _look_yaw * 0.18, -bank * 0.5))
	_spin(&"Head", Vector3(-lean * 0.33, _turn * 3.0 + _look_yaw * 0.24, -bank * 0.33))
	if not _uses_trial_skin:
		for side in SIDES:
			_spin(StringName("Ear_01_" + side), Vector3(sin(_clock * 5.0 - _phase * TAU) * 2.8, 0.0, bank * 0.18))

	_lean(lean)


func _lean(lean: float) -> void:
	# Set the sagittal hip-to-neck angle in model space, where +Z is forward.
	# The lower segment keeps its pelvic tilt; pitch the waist to match the target.
	var waist_index := _indices[&"Waist"]
	var waist := _pose(waist_index)
	var lower_spine := waist.origin - _pose(_hip).origin
	var upper_spine := _pose(_indices[&"Neck"]).origin - waist.origin
	var target := deg_to_rad(lean)
	var normal := Vector3(0.0, -sin(target), cos(target))
	var length := maxf(0.001, Vector2(upper_spine.y, upper_spine.z).length())
	var adjustment := target - atan2(upper_spine.z, upper_spine.y)
	adjustment += asin(clampf(-lower_spine.dot(normal) / length, -1.0, 1.0))
	_orient(waist_index, Quaternion(Vector3.RIGHT, adjustment) * waist.basis.get_rotation_quaternion())


func _leg(side: int, target: Vector3, pitch: float, normal: Vector3) -> void:
	var joints := _legs[side]
	var sign_value := 1.0 if side == 0 else -1.0
	_solve(joints, target, Vector3(sign_value * 0.12, 0.02, 1.0))
	var foot_basis := Quaternion(Vector3.UP, normal) * Quaternion(Vector3.RIGHT, deg_to_rad(pitch))
	_orient(joints[2], foot_basis * _global_rest[joints[2]].basis.get_rotation_quaternion())
	_spin(StringName("Toe_" + SIDES[side]), Vector3(-0.24 * maxf(pitch, 0.0), 0.0, 0.0))


func _skirt() -> void:
	if _skirt_clearance.panels.is_empty():
		return
	var thighs := PackedVector3Array()
	var knees := PackedVector3Array()
	var hands := PackedVector3Array()
	for side in 2:
		thighs.append(_pose(_legs[side][0]).origin)
		knees.append(_pose(_legs[side][1]).origin)
		var wrist := _pose(_arms[side][2]).origin
		var palm := _pose(_arms[side][3]).origin
		hands.append(wrist)
		hands.append(palm)
		for tip in _fingertips[side]:
			hands.append(_pose(tip).origin)
	var center := _pose(_hip).origin
	for panel in _skirt_clearance.panels:
		var root := _pose(panel[0]).origin
		var radial := (root - center).slide(Vector3.UP).normalized()
		for segment in 2:
			var start := _pose(panel[segment]).origin
			var end := _pose(panel[segment + 1]).origin
			# The lower joint carries the ruffle below the last pivot.
			var tip := end + (end - start) * (0.78 if segment == 1 else 0.0)
			var offset := _skirt_clearance.offset_at(tip, radial, thighs, knees, hands)
			_aim(panel[segment], panel[segment + 1], tip + radial * offset - start)


func _arm(side: int, swing_degrees: float, flex: float, spread: float) -> void:
	var joints := _arms[side]
	var direction := Quaternion(Vector3.RIGHT, deg_to_rad(-swing_degrees)) * Vector3.DOWN
	direction.x = spread if side == 0 else -spread
	_aim(joints[0], joints[1], direction)
	var forearm := Quaternion(Vector3.RIGHT, deg_to_rad(-flex)) * direction
	_aim(joints[1], joints[2], forearm)
	_aim(joints[2], joints[3], (forearm + Vector3.UP * 0.08).normalized())


func _fingers(side: int, curl: float) -> void:
	if _fingertips[side].is_empty():
		return
	var sign_value := -1.0 if side == 0 else 1.0
	for finger: String in FINGERS:
		for joint in 3:
			var weight := 0.56 if joint == 0 else (1.0 if joint == 1 else 0.72)
			var curl_scale := 0.45 + 0.20 * FINGERS.find(finger)
			_spin(StringName("%s_%02d_%s" % [finger, joint + 1, SIDES[side]]),
				Vector3(0.0, 0.0, sign_value * curl * weight * curl_scale))


func _length(a: int, b: int) -> float:
	return _global_rest[a].origin.distance_to(_global_rest[b].origin)


func _solve(joints: PackedInt32Array, target: Vector3, pole: Vector3) -> void:
	var center := _pose(joints[0]).origin
	var toward := target - center
	if toward.length_squared() < 0.000001:
		return
	var axis := toward.normalized()
	var bend := (pole - axis * pole.dot(axis)).normalized()
	var a := _length(joints[0], joints[1])
	var b := _length(joints[1], joints[2])
	var reach := clampf(toward.length(), absf(a - b) + 0.001, a + b - 0.001)
	var along := (a * a - b * b + reach * reach) / (2.0 * reach)
	var joint := center + axis * along + bend * sqrt(maxf(0.0, a * a - along * along))
	_aim(joints[0], joints[1], joint - center)
	_aim(joints[1], joints[2], center + axis * reach - joint)


func _pose(index: int) -> Transform3D:
	if index < 0:
		return _rig_base
	if _poses.has(index):
		return _poses[index]
	var local := _rest[index]
	if _rotations.has(index):
		local.basis = Basis(_rotations[index])
	if index == _hip:
		local.origin += _pose(_parents[index]).basis.inverse() * _hip_offset
	var result := _pose(_parents[index]) * local
	_poses[index] = result
	return result


func _set_rotation(index: int, rotation: Quaternion) -> void:
	_rotations[index] = rotation.normalized()
	_poses.clear()


func _orient(index: int, desired: Quaternion) -> void:
	var parent := _pose(_parents[index]).basis.get_rotation_quaternion()
	_set_rotation(index, parent.inverse() * desired)


func _aim(index: int, child: int, desired: Vector3) -> void:
	var bone := _pose(index)
	var from := _pose(child).origin - bone.origin
	if not from.is_zero_approx() and not desired.is_zero_approx():
		_orient(index, Quaternion(from.normalized(), desired.normalized()) * bone.basis.get_rotation_quaternion())


func _spin(name: StringName, angles: Vector3) -> void:
	if _indices.has(name):
		var index := _indices[name]
		var axes := _global_rest[index].basis.get_rotation_quaternion()
		var rest := _rest[index].basis.get_rotation_quaternion()
		var offset := Quaternion.from_euler(angles * (PI / 180.0))
		_set_rotation(index, rest * axes.inverse() * offset * axes)


func _finish() -> void:
	_skirt_clearance.apply_cycle(rig, _clips.action, _phase, _delta, _pose, _metres_per_unit)
	var hip_position := _rest[_hip].origin + _pose(_parents[_hip]).basis.inverse() * _hip_offset
	rig.set_bone_pose_position(_hip, hip_position / _metres_per_unit)
	for index in _rotations:
		rig.set_bone_pose_rotation(index, _rotations[index])
	for bone: StringName in [&"Spine", &"Shoulder_L", &"Shoulder_R"]:
		if _indices.has(bone):
			var index := _indices[bone]
			if not _rotations.has(index):
				rig.set_bone_pose_rotation(index, _rest[index].basis.get_rotation_quaternion())
