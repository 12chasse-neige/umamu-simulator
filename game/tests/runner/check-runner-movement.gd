extends SceneTree

const CAMPUS := preload("res://game/campus/campus-walk.tscn")
const Runner := preload("res://game/runner/runner.gd")
const PracticeLadder := preload("res://game/campus/practice-ladder.gd")
const LADDER_FIXTURE := preload("res://game/campus/practice-ladder.tscn")
const MOVE := &"move_forward"

var runner: Runner
var failed := false
var tail_sweeps: Array[float] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var campus := CAMPUS.instantiate()
	# Measure the terrain and gait without wandering runners on the test path.
	campus.get_node("Residents").free()
	runner = campus.get_node("SpecialWeek") as Runner
	var args := OS.get_cmdline_user_args()
	if args.has("--proxy"):
		runner.character_path = ""
	elif not args.is_empty():
		runner.character_path = args[0]
		_check(ResourceLoader.exists(runner.character_path, "PackedScene"), "Requested character scene is missing")
	root.add_child(campus)
	_check(not campus.has_node("PracticeLadder") and not campus.has_node("PracticeBall")
		and runner.practice_ball == null, "The playable gate should be clear of practice props")
	if not runner.character_path.is_empty() and ResourceLoader.exists(runner.character_path, "PackedScene"):
		_check(runner.motion != null, "The installed character should have a live bone solver")
	if runner.motion != null and runner.active_character_path == Runner.LOCAL_CHARACTER and ResourceLoader.exists("res://art/special-week/motions.tres"):
		if ResourceLoader.exists(Runner.DETAIL_CHARACTER):
			_check(runner.motion._skirt_clearance.panels.size() == 10 and runner.motion._fingertips[0].size() == 5,
				"Local gameplay skin is missing garment or finger chains")
		var tail_rig := runner.motion._tail._rig
		_check(tail_rig != null and tail_rig != runner.motion.rig and tail_rig.get_bone_count() == 4,
			"The tail needs its own three moving joints and a hip anchor")
		for action in [&"idle", &"walk", &"jog", &"run", &"sprint", &"squat", &"prone", &"rise",
				&"jump", &"double-jump", &"land", &"stairs-up", &"stairs-down", &"wall-up", &"wall-down",
				&"wall-left", &"wall-right", &"mantle", &"tree", &"vault", &"ladder",
				&"turn-left", &"turn-right", &"kick"]:
			_check(runner.motion._clips.has(action), "Missing playable UniMate clip %s" % action)
			_check(runner.motion._clips._tracks.get(action, {}).size() == 24, "%s must sample all 24 body joints" % action)
			var generation: Dictionary = runner.motion._clips._info.get(String(action), {}).get("generation", {})
			_check(generation.get("frame_digest") == Runner.RunnerPose.RunnerClip.TRIAL_FRAME_DIGEST
				and generation.get("joint_count") == 24 and generation.get("regenerated") == true
				and String(generation.get("motion_sha256", "")).length() == 64,
				"%s is missing the approved 24-joint generation provenance" % action)
		for action in ["walk", "run", "wall-up"]:
			_check(String(runner.motion._clips._info.get(action, {}).get("source", "")).begins_with("trial/"),
				"%s must come from the approved trial batch" % action)
		_check_loop_boundaries()
	await _gait(&"walk", Runner.Locomotion.Gait.WALK)
	await _gait(&"", Runner.Locomotion.Gait.JOG)
	await _gait(&"sprint", Runner.Locomotion.Gait.RUN)
	if tail_sweeps.size() == 3:
		_check(tail_sweeps[0] > 0.025 and tail_sweeps[0] < 0.14, "Walk tail swing should be small and visible")
		_check(tail_sweeps[1] > tail_sweeps[0] * 1.6, "Jog tail did not swing farther than walk")
		_check(tail_sweeps[2] > tail_sweeps[1] * 1.3, "Run tail did not swing farther than jog")
	await _race()
	await _run_acceleration()
	await _change_gaits()
	await _turn_and_step(campus)
	await _reverse_heading()
	await _academy_stairs()
	await _running_stairs()
	await _window_trim(campus)
	await _idle_and_walk_jump()
	await _running_jump_arms()
	await _squat_and_jump(campus)
	await _climb()
	await _stage_ledge()
	await _wall_faces(campus)
	await _blocked_wall(campus)
	await _unsupported_wall_top(campus)
	await _prone_and_double_jump()
	await _vault_barrier(campus)
	await _climb_campus_tree()
	await _kick_ball()
	print("Runner movement checks %s." % ("failed" if failed else "passed"))
	quit(1 if failed else 0)


func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame


func _check_loop_boundaries() -> void:
	var clips := Runner.RunnerPose.RunnerClip.new()
	clips.bind(runner.motion.rig)
	for action: StringName in [&"idle", &"walk", &"jog", &"run", &"sprint", &"stairs-up", &"stairs-down",
			&"wall-up", &"wall-down", &"wall-left", &"wall-right", &"tree", &"ladder"]:
		var window: Dictionary = clips._info.get(String(action), {})
		var frames: Array = window.get("loop_frames", [])
		_check(frames.size() == 2, "%s needs two matching source frames" % action)
		if frames.size() != 2:
			continue
		var period := float(frames[1] - frames[0]) / clips.SOURCE_FPS
		_check(is_equal_approx(clips.period(action, -1.0), period), "%s changed its source period" % action)
		var epsilon := 0.0001 / period
		clips.sample(action, 1.0 - epsilon, true, 1.0)
		var before := clips.pose.duplicate()
		var pelvis := clips.pelvis
		clips.sample(action, epsilon, true, 1.0)
		for bone in clips.pose:
			var previous: Quaternion = before[bone]
			_check(previous.angle_to(clips.pose[bone]) < 0.025, "%s %s snapped at the loop boundary" % [action, bone])
		_check(pelvis.distance_to(clips.pelvis) < 0.004, "%s pelvis snapped at the loop boundary" % action)


func _kick_ball() -> void:
	if runner.motion == null:
		return
	var ball := RigidBody3D.new()
	ball.position = Vector3(1.8, 0.15, 2.7)
	ball.collision_layer = 4
	ball.mass = 0.43
	ball.linear_damp = 0.62
	ball.angular_damp = 0.45
	ball.continuous_cd = true
	ball.physics_material_override = PhysicsMaterial.new()
	ball.physics_material_override.friction = 0.66
	ball.physics_material_override.bounce = 0.35
	var collision := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = Runner.BALL_RADIUS
	collision.shape = sphere
	ball.add_child(collision)
	runner.get_parent().add_child(ball)
	runner.practice_ball = ball
	await _recover(Vector3(1.8, 0.08, 3.28))
	runner.facing.rotation.y = PI
	var before := ball.global_position
	var played := false
	Input.action_press(&"kick")
	await _ticks(2)
	Input.action_release(&"kick")
	for tick in 46:
		await physics_frame
		played = played or _showing(&"kick")
	_check_clip_appeared(&"kick", played)
	_check(ball.global_position.z < before.z - 0.45, "Foot contact did not roll the practice ball forward")
	_check(runner.is_on_floor() and runner._kick_elapsed < 0.0, "Kick did not return to standing")
	runner.practice_ball = null
	ball.queue_free()


func _recover(point: Vector3) -> void:
	runner._recover_at(point)
	runner.camera_arm.rotation.y = 0.0
	await _ticks(15)
	_check(runner.is_on_floor(), "Could not stand at %s" % point)


func _showing(action: StringName) -> bool:
	return runner.motion != null and runner.motion._clips.action == action


func _check_clip_appeared(action: StringName, appeared: bool) -> void:
	if runner.motion != null and runner.motion._clips.has(action):
		_check(appeared, "Did not play the %s clip through gameplay input" % action)


func _gait(modifier: StringName, gait: int) -> void:
	var speed: float = runner.motion.gait_speed(gait) if runner.motion != null else Runner.Locomotion.SPEEDS[gait]
	var duty := 0.58 if gait == Runner.Locomotion.Gait.WALK else 0.39
	await _recover(Vector3(0, 0.08, 19.0))
	if not modifier.is_empty():
		Input.action_press(modifier)
	Input.action_press(MOVE)
	await _ticks(3)
	_check(_speed() > 0.05 and _speed() < speed - 0.10, "Movement should accelerate into %s m/s" % speed)
	await _ticks(37)
	_check(absf(_speed() - speed) < 0.09, "Steady speed %.2f, expected %.2f" % [_speed(), speed])

	var last_contact: Dictionary[String, Vector3] = {}
	var largest_slide := 0.0
	var contacts := 0
	var last_step_phase := -1
	var last_step := Vector3.INF
	var steps: Array[float] = []
	var impact_step := 0.0
	var last_height := INF
	var pitch_range := Vector2(INF, -INF)
	var wrist_range := Vector2(INF, -INF)
	var forward_reach := 0.0
	var phase_travel := 0.0
	var previous_phase := runner.motion._phase if runner.motion != null else 0.0
	var compare_walk := modifier == &"walk" and runner.motion != null and runner.motion._clips.has(&"walk")
	var pose_error := 0.0
	var authored_walk_frames := 0
	var native_run := gait == Runner.Locomotion.Gait.RUN and runner.motion != null and runner.motion.has_generated_run()
	var run_toes: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array()]
	var tail_rig: Skeleton3D = runner.motion._tail._rig if runner.motion != null else null
	var tip_in_bone := Vector3.ZERO
	var separate_tail := tail_rig != null and tail_rig != runner.motion.rig
	if separate_tail:
		var tail_mesh := tail_rig.get_node("TailMesh") as MeshInstance3D
		var vertices: PackedVector3Array = tail_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var tip := vertices[0]
		for vertex in vertices:
			if vertex.y < tip.y:
				tip = vertex
		tip_in_bone = tail_rig.get_bone_global_rest(3).affine_inverse() * tip
	var tail_range := Vector2(INF, -INF)
	for tick in 82:
		await physics_frame
		if runner.motion == null:
			continue
		var rig := runner.motion.rig
		if separate_tail:
			var tip_x := (tail_rig.get_bone_global_pose(3) * tip_in_bone).x
			tail_range = Vector2(minf(tail_range.x, tip_x), maxf(tail_range.y, tip_x))
		if compare_walk and _showing(&"walk"):
			authored_walk_frames += 1
			for bone: StringName in runner.motion._clips.pose:
				var source: Quaternion = runner.motion._clips.pose[bone]
				var actual := rig.get_bone_pose_rotation(rig.find_bone(bone))
				pose_error = maxf(pose_error, source.angle_to(actual))
		phase_travel += fposmod(runner.motion._phase - previous_phase, 1.0)
		previous_phase = runner.motion._phase
		var hips := _bone_in_metres("Hip")
		if is_finite(last_height) and fposmod(runner.motion._phase, 0.5) < 0.11:
			impact_step = maxf(impact_step, absf(hips.y - last_height))
		last_height = hips.y
		var torso := _bone_in_metres("Neck") - hips
		var torso_pitch := rad_to_deg(atan2(torso.z, torso.y))
		pitch_range = Vector2(minf(pitch_range.x, torso_pitch), maxf(pitch_range.y, torso_pitch))
		var step_phase := floori(runner.motion._phase * 2.0)
		if last_step_phase >= 0 and step_phase != last_step_phase:
			if last_step.is_finite():
				steps.append(last_step.distance_to(runner.global_position))
			last_step = runner.global_position
		last_step_phase = step_phase
		for side in 2:
			var suffix := "_L" if side == 0 else "_R"
			var wrist := _bone_in_metres("Wrist" + suffix).z - hips.z
			wrist_range = Vector2(minf(wrist_range.x, wrist), maxf(wrist_range.y, wrist))
			var ankle := _bone_in_metres("Ankle" + suffix)
			forward_reach = maxf(forward_reach, ankle.z - hips.z)
			var phase := fposmod(runner.motion._phase + side * 0.5, 1.0) / duty
			var name := "Toe" + suffix
			var toe := rig.global_transform * rig.get_bone_global_pose(rig.find_bone(name)).origin
			if native_run:
				run_toes[side].append(toe)
				continue
			if phase < 0.25 or phase > 0.66:
				last_contact.erase(name)
				continue
			if last_contact.has(name):
				largest_slide = maxf(largest_slide, toe.distance_to(last_contact[name]))
				contacts += 1
			else:
				last_contact[name] = toe
	if native_run:
		# The retargeted run starts at its selected source frame. Its low
		# contact window can be elsewhere in the cycle than the trial walk.
		for trace in run_toes:
			var low := INF
			for toe in trace:
				low = minf(low, toe.y)
			var contact := Vector3.INF
			for toe in trace:
				if toe.y > low + 0.018:
					contact = Vector3.INF
				elif contact.is_finite():
					largest_slide = maxf(largest_slide, toe.distance_to(contact))
					contacts += 1
				else:
					contact = toe
	if runner.motion != null:
		var measured_step := 0.0
		for length in steps:
			measured_step += length / steps.size()
		print("%.2f m/s   step %.2f m   %.3f m contact drift   %.1f° to %.1f° lean   %.1f mm pelvis change" % [
			speed, measured_step, largest_slide, pitch_range.x, pitch_range.y, impact_step * 1000.0])
		_check(contacts >= 3 and largest_slide < 0.075, "Mid-stance foot contact drifted")
		_check(not steps.is_empty() and measured_step > 0.20 and measured_step < 1.45, "Unusable stride length")
		_check(pitch_range.x >= -18.0 and pitch_range.y <= 45.0, "Locomotion torso left its physical range")
		_check(wrist_range.y - wrist_range.x > 0.12 and forward_reach < 0.61, "Unusable arm or leg stride range")
		var gait_name: StringName = Runner.Locomotion.GAITS[gait]
		if runner.motion._clips.has(gait_name):
			var native_period := runner.motion._clips.period(gait_name, 1.0)
			_check(absf(phase_travel - 82.0 / (60.0 * native_period)) < 0.045,
				"%s changed its generated cadence on straight ground" % gait_name)
		if modifier == &"walk":
			_check(impact_step < 0.024, "Pelvis jolted at walking touchdown")
		if compare_walk:
			_check(authored_walk_frames == 82 and pose_error < deg_to_rad(0.5),
				"Level walking changed the approved joint rotations by %.2f degrees" % rad_to_deg(pose_error))
		if separate_tail:
			var sweep := tail_range.y - tail_range.x
			tail_sweeps.append(sweep)
			print("%.3f m side-to-side tail tip swing" % sweep)

	Input.action_release(MOVE)
	if not modifier.is_empty():
		Input.action_release(modifier)
	await _ticks(2)
	_check(_speed() > 0.0 and _speed() < speed, "Release should brake smoothly from %s" % speed)
	await _ticks(25)
	_check(_speed() < 0.05, "Runner did not stop")


func _race() -> void:
	await _recover(Vector3(40, 0.08, -136))
	runner.camera_arm.rotation.y = -PI * 0.5
	Input.action_press(&"race")
	await _ticks(2)
	Input.action_release(&"race")
	var meet := runner.get_parent().get_node("RunningRace")
	_check(meet._menu.visible, "Race entry menu did not open")
	meet._menu._choose(Callable(meet, "_solo"))
	_check(runner.race.state == Runner.Race.State.COUNTDOWN, "No countdown at the campus start stripe")
	Input.action_press(MOVE)
	_right_mouse(true)
	await _ticks(70)
	_check(_speed() < 0.05, "Moved before the race countdown ended")
	_check(is_zero_approx(runner.control.run_boost), "Right mouse built speed during the race countdown")
	_right_mouse(false)
	await _ticks(161)
	var run_gait := Runner.Locomotion.Gait.RUN
	var speed: float = runner.motion.gait_speed(run_gait) if runner.motion != null else Runner.Locomotion.SPEEDS[run_gait]
	_check(runner.race.state == Runner.Race.State.RUNNING and absf(_speed() - speed) < 0.15,
		"Timed laps should use the ordinary running speed without Shift")
	_check(runner.race_hint.text == tr("Practice   %05.1f s   ·   G Cancel") % runner.race.time,
		"Timed lap displayed the wrong running controls")
	if runner.motion != null:
		_check(runner.control.visual_gait == run_gait, "Timed lap did not select the ordinary run gait")
	if runner.motion != null and runner.motion._clips.has(&"run"):
		_check(_showing(&"run"), "Timed lap did not play the ordinary run clip")
		var native_cycle := runner.motion._clips.period(&"run", 1.0)
		var phase := runner.motion._phase
		await _ticks(12)
		_check(absf(fposmod(runner.motion._phase - phase, 1.0) - 0.2 / native_cycle) < 0.035,
			"Race changed the generated run cadence")
	Input.action_press(&"race")
	await _ticks(2)
	Input.action_release(&"race")
	await _ticks(20)
	var jog: float = runner.motion.gait_speed(Runner.Locomotion.Gait.JOG) if runner.motion != null else Runner.Locomotion.SPEEDS[Runner.Locomotion.Gait.JOG]
	_check(runner.race.state == Runner.Race.State.IDLE and absf(_speed() - jog) < 0.15,
		"Cancelling practice should restore the exploration jog")
	Input.action_release(MOVE)

	var session := Runner.Race.new()
	var track := Runner.Race
	var start := Vector3(track.START.x, 0.0, track.START.y)
	session.update(start, true, 0.0)
	session.update(start, false, 3.0)
	# Run one complete lap by advancing along the surveyed centreline.
	var points: Array[Vector2] = [Vector2(track.RIGHT, track.CENTER_Z + track.RADIUS)]
	for index in range(1, 28):
		var angle := PI * 0.5 - PI * index / 27.0
		points.append(Vector2(track.RIGHT, track.CENTER_Z) + Vector2.from_angle(angle) * track.RADIUS)
	points.append(Vector2(track.LEFT, track.CENTER_Z - track.RADIUS))
	for index in range(1, 28):
		var angle := -PI * 0.5 - PI * index / 27.0
		points.append(Vector2(track.LEFT, track.CENTER_Z) + Vector2.from_angle(angle) * track.RADIUS)
	points.append(track.START)
	for point in points:
		session.update(Vector3(point.x, 0.0, point.y), false, 0.25)
	_check(session.state == track.State.FINISHED, "One clockwise lap did not finish")
	session.update(start, true, 0.0)
	session.update(start, false, 3.0)
	session.update(Vector3(40.0, 0.0, -130.0), false, 0.25)
	_check(session.state == track.State.IDLE, "Leaving the oval did not cancel the timed lap")


func _run_acceleration() -> void:
	await _recover(Vector3(40, 0.08, -136))
	runner.camera_arm.rotation.y = -PI * 0.5
	_right_mouse(true)
	Input.action_press(MOVE)
	await _ticks(45)
	_check(is_zero_approx(runner.control.run_boost), "Right mouse accelerated a jog")
	_right_mouse(false)
	Input.action_press(&"sprint")
	await _ticks(40)
	var normal_speed := _speed()
	var normal_cadence := await _sample_cadence()
	var limit := Runner.Locomotion.MAX_RUN_SPEED

	_right_mouse(true)
	await _ticks(30)
	var ramp_speed := _speed()
	_check(absf(ramp_speed - lerpf(normal_speed, limit, 0.25)) < 0.05,
		"Running speed should cover a quarter of the ramp after half a second")
	var ramp_cadence := await _sample_cadence()
	await _ticks(125)
	var top_speed := _speed()
	var top_cadence := await _sample_cadence()
	_check(absf(top_speed - limit) < 0.05, "Running speed missed the shared upper limit")
	if runner.motion != null:
		_check(ramp_cadence > normal_cadence and ramp_cadence < top_cadence,
			"Step cadence did not increase progressively")
		_check(absf(top_cadence / normal_cadence - limit / normal_speed) < 0.02,
			"Step cadence did not match the speed increase")
		if runner.motion.has_generated_run():
			_check(_showing(&"run"), "Acceleration should keep the ordinary run clip")
	await _ticks(25)
	_check(absf(_speed() - top_speed) < 0.05, "Running speed kept rising after reaching the limit")

	_right_mouse(false)
	await _ticks(12)
	_check(_speed() > normal_speed and _speed() < top_speed, "Releasing right mouse should ease back to running pace")
	await _ticks(48)
	_check(absf(_speed() - normal_speed) < 0.05, "Running speed did not return to normal")
	var released_cadence := await _sample_cadence()
	if runner.motion != null:
		_check(absf(released_cadence - normal_cadence) < 0.005, "Step cadence did not return to normal")
	Input.action_release(MOVE)
	Input.action_release(&"sprint")


func _right_mouse(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = pressed
	Input.parse_input_event(event)


func _sample_cadence() -> float:
	var start := runner.motion._phase if runner.motion != null else 0.0
	await _ticks(10)
	return fposmod(runner.motion._phase - start, 1.0) if runner.motion != null else 0.0


func _change_gaits() -> void:
	await _recover(Vector3(0, 0.08, 20))
	Input.action_press(MOVE)
	Input.action_press(&"walk")
	await _ticks(42)
	for mode in [&"jog", &"sprint", &"walk"]:
		Input.action_release(&"walk")
		Input.action_release(&"sprint")
		if mode != &"jog":
			Input.action_press(mode)
		var previous := _speed()
		var phase := runner.motion._phase if runner.motion != null else 0.0
		for tick in 35:
			await physics_frame
			_check(absf(_speed() - previous) < 0.37, "Speed jumped while changing gait")
			previous = _speed()
			if runner.motion != null:
				var progress := fposmod(runner.motion._phase - phase, 1.0)
				_check(progress < 0.08, "Foot cycle skipped during a gait change")
				phase = runner.motion._phase
	Input.action_release(MOVE)
	Input.action_release(&"walk")


func _turn_and_step(campus: Node) -> void:
	await _recover(Vector3(0, 0.08, 15.0))
	Input.action_press(MOVE)
	await _ticks(36)
	Input.action_release(MOVE)
	Input.action_press(&"move_right")
	await _ticks(5)
	if runner.motion != null:
		_check(absf(runner.motion._look_yaw) > 5.0, "Head did not anticipate the requested turn")
	await _ticks(32)
	Input.action_release(&"move_right")
	var yaw_error := absf(angle_difference(runner.facing.rotation.y, PI * 0.5))
	_check(yaw_error < 0.2, "Visual heading did not settle after turning right")

	var step := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 0.18, 1.6)
	shape.shape = box
	step.position = Vector3(-3.4, 0.09, 10.0)
	step.add_child(shape)
	campus.add_child(step)
	await _recover(Vector3(-3.4, 0.08, 11.4))
	Input.action_press(&"walk")
	Input.action_press(MOVE)
	var start_y := runner.global_position.y
	for descending in [false, true]:
		var max_travel := 0.0
		var max_visual_rise := 0.0
		var grade := 0.0
		var action := &"stairs-down" if descending else &"stairs-up"
		var showed_clip := false
		for tick in (55 if not descending else 158):
			var last := runner.global_position
			var visual_y := runner.facing.global_position.y
			await physics_frame
			var travel := runner.global_position - last
			max_travel = maxf(max_travel, Vector2(travel.x, travel.z).length())
			max_visual_rise = maxf(max_visual_rise, absf(runner.facing.global_position.y - visual_y))
			grade = maxf(grade, runner._stair_grade * (-1.0 if descending else 1.0))
			showed_clip = showed_clip or _showing(action)
		_check(max_travel < 0.032 and max_visual_rise < 0.065, "Stair traversal lurched")
		_check(grade < 0.08 and not showed_clip, "An isolated curb interrupted the ground gait")
		if descending:
			_check(absf(runner.global_position.y - start_y) < 0.035, "Did not return to the lower floor")
		else:
			_check(runner.is_on_floor() and runner.global_position.y > 0.15, "Did not ascend the tread")
	Input.action_release(MOVE)
	Input.action_release(&"walk")
	await _ticks(18)
	_check(absf(runner.facing.position.y) < 0.015, "Visual stair offset did not settle")
	# Repeat at an unmodified jog and check the entire up/down crossing.
	await _recover(Vector3(-3.4, 0.08, 11.75))
	runner.facing.rotation.y = PI
	Input.action_press(MOVE)
	var lost_contact := 0
	var traversed_top := false
	for tick in 170:
		await physics_frame
		traversed_top = traversed_top or runner.position.y > 0.16
		if not runner.on_walkable_ground() or _showing(&"land") or runner._vault != null:
			lost_contact += 1
		if runner.position.z < 8.85:
			break
	Input.action_release(MOVE)
	_check(traversed_top and runner.position.z < 8.86 and lost_contact == 0,
		"Jogging over a low curb lost support or started a vault")
	step.queue_free()


func _reverse_heading() -> void:
	await _recover(Vector3(0, 0.08, 19))
	runner.facing.rotation.y = PI
	Input.action_press(MOVE)
	await _ticks(60)
	runner.camera_arm.rotation.y = PI
	var smallest_width := INF
	var largest_yaw := 0.0
	for tick in 45:
		var yaw := runner.facing.rotation.y
		await physics_frame
		largest_yaw = maxf(largest_yaw, absf(angle_difference(yaw, runner.facing.rotation.y)))
		if runner.motion != null:
			var width := _bone_in_metres("Ankle_L").x - _bone_in_metres("Ankle_R").x
			smallest_width = minf(smallest_width, width)
	Input.action_release(MOVE)
	_check(smallest_width > 0.015 and largest_yaw < 0.12, "Reversal crossed the legs or snapped the heading")


func _academy_stairs() -> void:
	# Ten 16.85 cm risers on the west academy flight, followed in both directions.
	for descending in [false, true]:
		var start := Vector3(-25.32, 2.60, -66.71) if descending else Vector3(-21.62, 0.92, -66.71)
		await _recover(start)
		runner.camera_arm.rotation.y = -PI / 2 if descending else PI / 2
		runner.facing.rotation.y = PI + runner.camera_arm.rotation.y
		Input.action_press(&"walk")
		Input.action_press(MOVE)
		var clip := &"stairs-down" if descending else &"stairs-up"
		var showed_clip := false
		var lost_support := 0
		var peak_travel := 0.0
		var previous: Array[Vector3] = []
		for tick in 560:
			await physics_frame
			if not runner.on_walkable_ground() or _showing(&"land"):
				lost_support += 1
			showed_clip = showed_clip or _showing(clip)
			if runner.motion != null:
				for side in 2:
					var toe := runner.facing.to_global(_bone_in_metres("Toe_" + ["L", "R"][side]))
					if previous.size() > side:
						peak_travel = maxf(peak_travel, toe.distance_to(previous[side]))
						previous[side] = toe
					else:
						previous.append(toe)
			if (runner.position.x > -21.65 if descending else runner.position.x < -25.23):
				break
		Input.action_release(MOVE)
		Input.action_release(&"walk")
		_check_clip_appeared(clip, showed_clip)
		_check(absf(runner.position.y - (0.86 if descending else 2.545)) < 0.04,
			"Did not reach the academy landing: %s" % runner.position)
		_check(lost_support == 0 and peak_travel < 0.10, "Stair support/foot continuity failed")
		print("%s: %d unsupported frames, %.3f m maximum toe travel per tick" % [clip, lost_support, peak_travel])


func _running_stairs() -> void:
	for descending in [false, true]:
		var start := Vector3(-25.37, 2.60, -66.71) if descending else Vector3(-19.7, 1.0, -66.71)
		await _recover(start)
		runner.camera_arm.rotation.y = -PI / 2 if descending else PI / 2
		runner.facing.rotation.y = PI + runner.camera_arm.rotation.y
		Input.action_press(&"sprint")
		Input.action_press(MOVE)
		var samples := 0
		var distance := 0.0
		var lowest_speed := INF
		var lost_support := 0
		var peak_travel := 0.0
		var last_toes: Array[Vector3] = [Vector3.INF, Vector3.INF]
		for tick in 180:
			var old_x := runner.position.x
			await physics_frame
			var x := runner.position.x
			if x > -24.95 and x < -21.95:
				samples += 1
				var step := absf(old_x - x)
				distance += step
				lowest_speed = minf(lowest_speed, step * Engine.physics_ticks_per_second)
				if not runner.on_walkable_ground() or _showing(&"land"):
					lost_support += 1
				if runner.motion != null:
					for side in 2:
						var toe := runner.facing.to_global(_bone_in_metres("Toe_" + ["L", "R"][side]))
						if last_toes[side].is_finite():
							peak_travel = maxf(peak_travel, toe.distance_to(last_toes[side]))
						last_toes[side] = toe
			if (x > -21.4 if descending else x < -25.4):
				break
		Input.action_release(MOVE)
		Input.action_release(&"sprint")
		var mean_speed := distance * Engine.physics_ticks_per_second / maxi(1, samples)
		_check(distance > 2.90 and mean_speed > 2.5 and lowest_speed > 2.1,
			"Run input lost momentum on the academy flight")
		_check(lost_support == 0 and peak_travel < 0.17, "Missed support or snapped a toe on running stairs")
		_check(absf(runner.position.y - (0.86 if descending else 2.545)) < 0.04,
			"Running missed the academy landing")
		print("Running stairs %s: %.2f m/s mean, %.2f minimum, %.3f m peak toe travel" %
			[("down" if descending else "up"), mean_speed, lowest_speed, peak_travel])


func _window_trim(campus: Node) -> void:
	var wall := _wall_fixture(campus, Vector3(-3.4, 2.3, 10.0), Vector3(2.0, 4.6, 2.0))
	var sill := _wall_fixture(campus, Vector3(-3.4, 2.02, 11.08), Vector3(1.45, 0.14, 0.16))
	await _recover(Vector3(-3.4, 0.08, 11.45))
	runner.facing.rotation.y = PI
	await _grab_face()
	Input.action_press(MOVE)
	var stalled := 0
	var shoulder_clearance := 0.0
	for tick in 220:
		var height := runner.position.y
		await physics_frame
		if runner.position.y > 0.5 and runner.position.y - height < 0.001:
			stalled += 1
		shoulder_clearance = maxf(shoulder_clearance, runner.position.z - 11.0)
	Input.action_release(MOVE)
	_check(runner._wall is Runner.WallClimb and runner.position.y > 2.55 and stalled < 12,
		"Window sill blocked the climb or detached the grip")
	_check(shoulder_clearance > 0.48 and runner.position.z < 11.41, "Capsule did not follow the protruding trim")
	wall.queue_free()
	sill.queue_free()


func _idle_and_walk_jump() -> void:
	await _recover(Vector3(0, 0.08, 19.0))
	if runner.motion == null or not runner.motion._clips.has(&"idle"):
		return
	await _ticks(20)
	await _check_idle_loop()
	var idle_hands := -INF
	var alignment := 1.0
	for tick in 90:
		await physics_frame
		idle_hands = maxf(idle_hands, _highest_wrist_above_shoulder())
		for suffix in ["_L", "_R"]:
			var wrist := _bone_in_metres("Wrist" + suffix)
			var forearm := wrist - _bone_in_metres("Elbow" + suffix)
			var fingers := _bone_in_metres("Hand_Attach" + suffix) - wrist
			alignment = minf(alignment, forearm.normalized().dot(fingers.normalized()))
	_check(alignment > 0.76, "Idle wrist bent sideways away from the forearm")
	_check(_showing(&"idle") and idle_hands < -0.16,
		"Standing should keep both hands below the shoulders: %.3f m" % idle_hands)

	Input.action_press(&"walk")
	Input.action_press(MOVE)
	await _ticks(45)
	Input.action_press(&"jump")
	await _ticks(2)
	Input.action_release(&"jump")
	var showed_jump := false
	var showed_landing := false
	var jump_hands := -INF
	for tick in 93:
		await physics_frame
		showed_jump = showed_jump or (_showing(&"jump") and not runner.is_on_floor())
		showed_landing = showed_landing or _showing(&"land")
		jump_hands = maxf(jump_hands, _highest_wrist_above_shoulder())
	_check(showed_jump and showed_landing and _showing(&"walk"), "Walking jump did not land back into the walk")
	_check(jump_hands < 0.025, "Walking jump raised the hands above the shoulders: %.3f m" % jump_hands)
	print("Peak wrist relative to shoulder: idle %.3f m, walking jump %.3f m" % [idle_hands, jump_hands])
	Input.action_release(MOVE)
	Input.action_release(&"walk")


func _check_idle_loop() -> void:
	var motion := runner.motion
	var clips := motion._clips
	var period := clips.period(&"idle", 0.0)
	var frames: Array = clips._info.get("idle", {}).get("loop_frames", [])
	if frames.size() != 2:
		return
	_check(is_equal_approx(period, (float(frames[1]) - float(frames[0])) / clips.SOURCE_FPS),
		"Idle playback changed its source period")
	var phase_step := 1.0 / (period * Engine.physics_ticks_per_second)
	var progress := fposmod(motion._clip_clock / period, 1.0)
	var turns := 0
	var peak_phase_error := 0.0
	var peak_rotation := 0.0
	var peak_travel := 0.0
	var rotations: Dictionary[StringName, Quaternion] = {}
	var positions: Dictionary[StringName, Vector3] = {}
	var landmarks := [&"Hip", &"Neck", &"Head", &"Wrist_L", &"Wrist_R", &"Toe_L", &"Toe_R"]
	for tick in ceili(3.0 / phase_step) + 1:
		await physics_frame
		var next := fposmod(motion._clip_clock / period, 1.0)
		turns += int(next < progress)
		peak_phase_error = maxf(peak_phase_error, absf(fposmod(next - progress, 1.0) - phase_step))
		progress = next
		for bone: StringName in clips.BODY_BONES:
			var index: int = motion._indices[bone]
			var rotation := motion.rig.get_bone_pose_rotation(index)
			if rotations.has(bone):
				peak_rotation = maxf(peak_rotation, rotations[bone].angle_to(rotation))
			rotations[bone] = rotation
			if bone in landmarks:
				var position := motion.rig.to_global(motion.rig.get_bone_global_pose(index).origin)
				if positions.has(bone):
					peak_travel = maxf(peak_travel, positions[bone].distance_to(position))
				positions[bone] = position
	_check(_showing(&"idle") and turns >= 3 and peak_phase_error < 0.0001,
		"Standing did not complete three idle cycles at the source rate")
	_check(peak_rotation < deg_to_rad(5.0) and peak_travel < 0.012,
		"Standing snapped by %.1f mm or %.1f degrees in one tick" % [peak_travel * 1000.0, rad_to_deg(peak_rotation)])
	print("Idle: %.3f s period, %.1f mm maximum travel and %.1f° maximum rotation per tick" % [
		period, peak_travel * 1000.0, rad_to_deg(peak_rotation)])


func _running_jump_arms() -> void:
	if runner.motion == null:
		return
	for second_jump in [false, true]:
		await _recover(Vector3(0, 0.08, 19))
		runner.facing.rotation.y = PI
		Input.action_press(MOVE)
		Input.action_press(&"sprint")
		await _ticks(48)
		Input.action_press(&"jump")
		var early_flex := Vector2.ZERO
		var late_flex := Vector2.ZERO
		var lead := 0.0
		var wrist_alignment := 1.0
		var last_palms: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
		var palm_turn := 0.0
		for tick in 110:
			await physics_frame
			if tick == 2 or tick == 26:
				Input.action_release(&"jump")
			if second_jump and tick == 24:
				Input.action_press(&"jump")
			if tick < 15 or runner.on_walkable_ground():
				continue
			var hands_z := Vector2.ZERO
			for side in 2:
				var suffix := "_L" if side == 0 else "_R"
				var upper := _bone_in_metres("Elbow" + suffix) - _bone_in_metres("Arm" + suffix)
				var wrist := _bone_in_metres("Wrist" + suffix)
				var lower := wrist - _bone_in_metres("Elbow" + suffix)
				var angle := rad_to_deg(upper.angle_to(lower))
				if runner.velocity.y > 1.5:
					early_flex[side] = maxf(early_flex[side], angle)
				if runner.velocity.y < -2.5:
					late_flex[side] = angle
				hands_z[side] = wrist.z
				if runner.motion._indices.has("Middle_01" + suffix):
					var knuckle := _bone_in_metres("Middle_01" + suffix) - wrist
					wrist_alignment = minf(wrist_alignment, knuckle.normalized().dot(lower.normalized()))
					var palm := knuckle.cross(_bone_in_metres("Index_01" + suffix) - wrist).normalized()
					if not last_palms[side].is_zero_approx():
						palm_turn = maxf(palm_turn, rad_to_deg(palm.angle_to(last_palms[side])))
					last_palms[side] = palm
			if runner.velocity.y > 0.0:
				lead = maxf(lead, absf(hands_z.x - hands_z.y))
		Input.action_release(MOVE)
		Input.action_release(&"sprint")
		_check(lead > 0.14 and late_flex.x > 0.0 and late_flex.y > 0.0
			and early_flex.x > late_flex.x + 18.0 and early_flex.y > late_flex.y + 18.0,
			"Running jump lost its opposite arm drive or held its elbows fixed during descent")
		_check(wrist_alignment > 0.91 and palm_turn < 25.0, "Airborne wrist kinked or rolled abruptly")


func _highest_wrist_above_shoulder() -> float:
	return maxf(_bone_in_metres("Wrist_L").y - _bone_in_metres("Arm_L").y,
		_bone_in_metres("Wrist_R").y - _bone_in_metres("Arm_R").y)


func _squat_and_jump(campus: Node) -> void:
	await _recover(Vector3(0, 0.08, 11.0))
	var baseline := _hip_height()
	Input.action_press(&"crouch")
	await _ticks(7)
	_check(runner.capsule.shape.height > Runner.CROUCH_HEIGHT + 0.05 and runner.capsule.shape.height < runner.standing_shape.height - 0.025, "Squat height changed abruptly")
	await _ticks(16)
	_check(runner.crouched and runner.capsule.shape.height < 1.3, "Squat capsule did not shorten")
	_check_clip_appeared(&"squat", _showing(&"squat"))
	if runner.motion != null:
		_check(baseline - _hip_height() > 0.24, "Pelvis did not descend during squat")
	Input.action_press(MOVE)
	await _ticks(23)
	_check(absf(_speed() - Runner.CROUCH_SPEED) < 0.08, "Crouch walk missed its target speed")
	Input.action_release(MOVE)
	await _ticks(10)
	var ceiling := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(1.4, 0.15, 1.4)
	collision.shape = slab
	ceiling.add_child(collision)
	ceiling.position = runner.global_position + Vector3.UP * 1.47
	campus.add_child(ceiling)
	await _ticks(2)
	Input.action_release(&"crouch")
	await _ticks(8)
	_check(runner.crouched and runner.capsule.shape.height < 1.3, "Stood into the low ceiling")
	ceiling.queue_free()
	await _ticks(26)
	_check(not runner.crouched, "Squat did not recover")
	if runner.motion != null:
		_check(absf(baseline - _hip_height()) < 0.03, "Pelvis did not recover from squat")

	Input.action_press(&"jump")
	await _ticks(2)
	Input.action_release(&"jump")
	var highest := runner.global_position.y
	var airborne := false
	var upright := true
	var jumping_clip := false
	var landing_clip := false
	for tick in 85:
		await physics_frame
		highest = maxf(highest, runner.global_position.y)
		airborne = airborne or not runner.is_on_floor()
		jumping_clip = jumping_clip or _showing(&"jump")
		landing_clip = landing_clip or _showing(&"land")
		if runner.motion != null and not runner.is_on_floor():
			upright = upright and _bone_in_metres("Neck").y > _hip_height() + 0.10
	_check(airborne and highest > 0.8 and runner.is_on_floor(), "Jump did not take off and land")
	_check(upright, "The jump pose flipped upside down")
	_check_clip_appeared(&"jump", jumping_clip)
	_check_clip_appeared(&"land", landing_clip)
	print("Jump apex: %.2f m" % highest)
	# Press again just before landing. One buffered jump should load after contact.
	Input.action_press(&"jump")
	await _ticks(2)
	Input.action_release(&"jump")
	var buffered := false
	var second_takeoff := false
	for tick in 110:
		await physics_frame
		if not buffered and runner.velocity.y < -3.0 and runner.global_position.y < 0.30:
			Input.action_press(&"jump")
			buffered = true
		elif buffered:
			Input.action_release(&"jump")
			second_takeoff = second_takeoff or runner.velocity.y > 3.5
	_check(buffered and second_takeoff, "Jump pressed before landing was lost")


func _climb() -> void:
	var ladder := LADDER_FIXTURE.instantiate() as PracticeLadder
	ladder.position = Vector3(5.7, 0.001, 6.25)
	runner.get_parent().add_child(ladder)
	await _recover(ladder.to_global(Vector3(0, 0.08, 0.74)))
	await _press_climb()
	Input.action_press(MOVE)
	await _ticks(51)
	await _check_climb_cadence(&"ladder")
	Input.action_release(MOVE)
	var hold := runner.global_position
	_check(hold.y > 0.35 and runner._climb_state == Runner.ClimbState.SCALE, "Could not begin ladder ascent")
	await _ticks(16)
	_check(runner.global_position.distance_to(hold) < 0.008, "Runner slipped while holding the ladder")

	Input.action_press(MOVE)
	await _finish_climb()
	Input.action_release(MOVE)
	await _ticks(12)
	_check(runner.is_on_floor() and absf(runner.global_position.y - ladder.exit_point().y) < 0.09,
		"Could not stand on the ladder platform: %s" % runner.global_position)

	await _press_climb()
	Input.action_press(&"move_back")
	await _finish_climb()
	Input.action_release(&"move_back")
	await _ticks(12)
	_check(runner.is_on_floor() and runner.global_position.y < 0.12, "Could not descend the ladder")
	ladder.queue_free()


func _stage_ledge() -> void:
	# The south edge of the actual amphitheatre stage, away from its stairs.
	await _recover(Vector3(68, 0.01, -68.5))
	runner.facing.rotation.y = PI
	Input.action_press(&"climb")
	await _ticks(2)
	Input.action_release(&"climb")
	_check(runner._wall != null, "Could not catch the amphitheatre ledge")
	if runner._wall == null:
		return
	await _ticks(25)
	if runner.motion != null:
		var rig := runner.motion.rig
		var hand := rig.to_global(rig.get_bone_global_pose(rig.find_bone("Wrist_L")).origin)
		_check(hand.distance_to(runner._wall.hands(runner)[0]) < 0.055, "The wrist missed the stage lip")
	var grip := runner.global_position
	await _ticks(10)
	_check(grip.distance_to(runner.global_position) < 0.005, "Slipped off the stationary grip")
	Input.action_press(MOVE)
	for tick in 140:
		await physics_frame
		if runner._wall == null:
			break
	Input.action_release(MOVE)
	await _ticks(12)
	_check(runner._wall == null and runner.is_on_floor() and runner.global_position.y > 0.64,
		"Wall pull-up did not finish on the stage")
	runner.facing.rotation.y = 0.0
	Input.action_press(&"climb")
	await _ticks(2)
	Input.action_release(&"climb")
	_check(runner._wall != null, "Could not grasp the edge from the stage")
	Input.action_press(&"move_back")
	for tick in 150:
		await physics_frame
		if runner._wall == null:
			break
	Input.action_release(&"move_back")
	await _ticks(18)
	_check(runner._wall == null and runner.is_on_floor() and runner.global_position.y < 0.10,
		"Lowering from the stage failed")


func _wall_faces(campus: Node) -> void:
	# The facade beside the entrance to the first faculty pavilion.
	await _recover(Vector3(-103, 0.01, -34))
	runner.facing.rotation.y = PI
	await _grab_face()
	Input.action_press(MOVE)
	await _ticks(36)
	await _check_climb_cadence(&"wall-up")
	await _ticks(160)
	Input.action_release(MOVE)
	await _ticks(4)
	var hold := runner.global_position
	_check(hold.y > 2.0 and runner._wall is Runner.WallClimb, "Did not scale the faculty wall")
	await _ticks(12)
	_check(hold.distance_to(runner.global_position) < 0.012, "Slipped while holding the wall")
	Input.action_press(&"move_back")
	await _ticks(52)
	Input.action_release(&"move_back")
	_check(runner.global_position.y < hold.y - 0.40, "Could not climb down the facade")
	Input.action_press(&"climb")
	await _ticks(2)
	Input.action_release(&"climb")
	await _ticks(50)
	_check(runner._wall == null and runner.is_on_floor(), "Letting go did not return to ground")

	# A flat-topped wall isolates the full face-to-mantle and reverse handoffs.
	var wall := _wall_fixture(campus, Vector3(-3.4, 1.60, 10.0), Vector3(2.0, 3.2, 2.0))
	await _recover(Vector3(-3.4, 0.08, 11.45))
	runner.facing.rotation.y = PI
	await _grab_face()
	Input.action_press(&"move_right")
	await _ticks(38)
	Input.action_release(&"move_right")
	_check(runner.global_position.x > -3.14 and runner._wall is Runner.WallClimb, "Could not traverse right")
	_check_clip_appeared(&"wall-right", _showing(&"wall-right"))
	Input.action_press(&"move_left")
	await _ticks(38)
	Input.action_release(&"move_left")
	_check(absf(runner.global_position.x + 3.4) < 0.12, "Could not traverse left")
	_check_clip_appeared(&"wall-left", _showing(&"wall-left"))
	Input.action_press(MOVE)
	var mantle := false
	for tick in 430:
		await physics_frame
		mantle = mantle or _showing(&"mantle")
		if runner._wall == null:
			break
	Input.action_release(MOVE)
	await _ticks(15)
	_check(runner._wall == null and runner.is_on_floor() and runner.global_position.y > 3.17,
		"Wall climb did not transfer to the mantle")
	_check_clip_appeared(&"mantle", mantle)
	runner.facing.rotation.y = 0.0
	Input.action_press(&"climb")
	await _ticks(2)
	Input.action_release(&"climb")
	Input.action_press(&"move_back")
	var on_face := false
	for tick in 430:
		await physics_frame
		on_face = on_face or runner._wall is Runner.WallClimb
		if runner._wall == null:
			break
	Input.action_release(&"move_back")
	await _ticks(15)
	_check(on_face and runner.is_on_floor() and runner.global_position.y < 0.1,
		"Descending the mantle did not return to wall and ground")
	wall.queue_free()


func _blocked_wall(campus: Node) -> void:
	var wall := _wall_fixture(campus, Vector3(-3.4, 2.0, 10.0), Vector3(2.0, 4.0, 2.0))
	var overhang := _wall_fixture(campus, Vector3(-3.4, 2.18, 11.34), Vector3(2.0, 0.25, 0.95))
	await _recover(Vector3(-3.4, 0.08, 11.45))
	runner.facing.rotation.y = PI
	await _grab_face()

	Input.action_press(MOVE)
	await _ticks(47)
	Input.action_release(MOVE)
	var hold := runner.global_position
	_check(runner._wall is Runner.WallClimb and hold.y > 0.35 and hold.y < 0.46,
		"Overhang fixture did not block a climb above ground: %s" % hold)
	await _ticks(40)
	_check(runner._wall != null and runner.global_position.distance_to(hold) < 0.012,
		"Pausing beneath an overhang should hold the grip")

	Input.action_press(&"move_back")
	await _ticks(15)
	Input.action_release(&"move_back")
	_check(runner._wall != null and runner.global_position.y < hold.y - 0.10,
		"Could not reverse away from the overhang")
	Input.action_press(MOVE)
	await _ticks(120)
	Input.action_release(MOVE)
	_check(runner._wall == null and runner.is_on_floor(), "Sustained blockage left the runner stuck on the wall")

	Input.action_press(&"move_back")
	await _ticks(36)
	Input.action_release(&"move_back")
	_check(runner.global_position.z > hold.z + 0.5, "Walking did not resume after releasing a blocked climb")
	overhang.queue_free()
	wall.queue_free()


func _wall_fixture(campus: Node, center: Vector3, size: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	wall.add_child(collision)
	wall.position = center
	campus.add_child(wall)
	return wall


func _unsupported_wall_top(campus: Node) -> void:
	# The wall ends above the handholds with too little depth for a landing.
	var panel := _wall_fixture(campus, Vector3(-3.4, 1.175, 10.89), Vector3(2.0, 2.35, 0.22))
	await _recover(Vector3(-3.4, 0.08, 11.45))
	runner.facing.rotation.y = PI
	await _grab_face()
	Input.action_press(MOVE)
	var highest := runner.global_position.y
	for tick in 190:
		await physics_frame
		highest = maxf(highest, runner.global_position.y)
	Input.action_release(MOVE)
	_check(highest > 1.15 and highest < 1.30, "Thin wall fixture did not reach its last handhold")
	_check(runner._wall == null and runner.is_on_floor(), "A wall with no pull-up landing kept the runner attached")
	panel.queue_free()


func _prone_and_double_jump() -> void:
	await _recover(Vector3(0, 0.08, 19.0))
	var hip := _hip_height()
	Input.action_press(&"prone")
	await _ticks(45)
	_check(runner.prone and runner.capsule.shape.height < 0.70, "Could not lower to the ground")
	_check_clip_appeared(&"prone", _showing(&"prone"))
	if runner.motion != null:
		_check(hip - _hip_height() > 0.45, "Prone pose did not reach the ground")
		if runner.motion._clips.has(&"prone"):
			var torso := _bone_in_metres("Neck") - _bone_in_metres("Hip")
			_check(torso.z > 0.28 and absf(torso.y) < 0.10, "Prone body is not face down")
	Input.action_release(&"prone")
	var showed_rise := false
	for tick in 53:
		await physics_frame
		showed_rise = showed_rise or _showing(&"rise")
	if runner.motion != null and runner.motion._clips.uses_roster_motions():
		_check_clip_appeared(&"rise", showed_rise)
	_check(not runner.crouched and runner.capsule.shape.height > 1.60, "Could not rise from prone")
	if runner.motion != null:
		var spine := _bone_in_metres("Neck") - _bone_in_metres("Hip")
		_check(absf(atan2(spine.z, spine.y)) < deg_to_rad(9), "Recovery ended bent forward")
	Input.action_press(&"jump")
	await _ticks(2)
	Input.action_release(&"jump")
	await _ticks(21)
	Input.action_press(&"jump")
	await _ticks(2)
	Input.action_release(&"jump")
	_check(runner.control.flight == Runner.Locomotion.Flight.DOUBLE_JUMP and runner.velocity.y > 2.8,
		"Second press did not trigger the airborne jump")
	_check_clip_appeared(&"double-jump", _showing(&"double-jump"))
	for tick in 16:
		await physics_frame
		if runner.motion != null:
			_check(_bone_in_metres("Neck").y > _hip_height() + 0.08, "Double jump pose was inverted")
	Input.action_press(&"jump")
	await _ticks(2)
	Input.action_release(&"jump")
	_check(runner.velocity.y < 1.5, "Third press kicked the runner up a second time")
	await _ticks(100)
	_check(runner.is_on_floor(), "Double jump did not land")


func _vault_barrier(campus: Node) -> void:
	var barrier := _wall_fixture(campus, Vector3(-3.4, 0.24, 10.0), Vector3(1.6, 0.48, 0.23))
	await _recover(Vector3(-3.4, 0.08, 12.0))
	Input.action_press(MOVE)
	var vaulted := false
	var vault_clip := false
	for tick in 120:
		await physics_frame
		vaulted = vaulted or runner._vault != null
		vault_clip = vault_clip or _showing(&"vault")
	Input.action_release(MOVE)
	_check(vaulted and runner._vault == null and runner.is_on_floor() and runner.global_position.z < 9.45,
		"Running into a low barrier did not complete the vault: %s" % runner.global_position)
	_check_clip_appeared(&"vault", vault_clip)
	barrier.queue_free()


func _climb_campus_tree() -> void:
	var found := false
	for direction: Vector3 in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		var trunk := Vector3(-7.8, 0, -6.2)
		var space := runner.get_world_3d().direct_space_state
		var origin := trunk - direction * 1.5 + Vector3.UP * 0.9
		var bark := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, trunk + Vector3.UP * 0.9))
		if bark.is_empty() or not bark.collider.is_in_group(&"climbable_trunks"):
			continue
		var base: Vector3 = bark.position - direction * 0.47
		base.y = 0.08
		await _recover(base)
		runner.facing.rotation.y = atan2(direction.x, direction.z)
		Input.action_press(&"climb")
		await _ticks(2)
		Input.action_release(&"climb")
		var wall := runner._wall as Runner.WallClimb
		if wall == null or not wall.tree:
			continue
		Input.action_press(MOVE)
		await _ticks(75)
		Input.action_release(MOVE)
		found = runner.global_position.y > base.y + 0.44
		_check_clip_appeared(&"tree", _showing(&"tree"))
		break
	_check(found, "Could not climb a real avenue trunk")


func _grab_face() -> void:
	Input.action_press(&"climb")
	await _ticks(2)
	Input.action_release(&"climb")
	_check(runner._wall is Runner.WallClimb, "Could not grasp the wall face")


func _check_climb_cadence(action: StringName) -> void:
	var motion := runner.motion
	if motion == null or not motion._clips.has(action):
		await _ticks(12)
		return
	var start := motion._climb_clip_phase
	await _ticks(12)
	_check(_showing(action), "Expected to play %s during sustained climbing" % action)
	var progress := fposmod(motion._climb_clip_phase - start, 1.0)
	_check(absf(progress - 0.2 / motion._clips.period(action, 1.0)) < 0.035,
		"%s changed the generated cycle period during a steady climb" % action)


func _press_climb() -> void:
	Input.action_press(&"climb")
	await _ticks(2)
	Input.action_release(&"climb")
	_check(runner._climb_state != Runner.ClimbState.INACTIVE, "Ladder entry did not engage")


func _finish_climb() -> void:
	for tick in 240:
		if runner._climb_state == Runner.ClimbState.INACTIVE:
			return
		await physics_frame
	_check(false, "Ladder traversal did not finish")


func _speed() -> float:
	return Vector2(runner.velocity.x, runner.velocity.z).length()


func _hip_height() -> float:
	if runner.motion == null:
		return 0.0
	return _bone_in_metres("Hip").y


func _bone_in_metres(name: String) -> Vector3:
	var rig := runner.motion.rig
	return runner.facing.to_local(rig.to_global(rig.get_bone_global_pose(rig.find_bone(name)).origin))


func _check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
