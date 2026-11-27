extends SceneTree

const CAMPUS := preload("res://game/campus/campus-walk.tscn")
const Runner := preload("res://game/runner/runner.gd")
const RunnerClip := preload("res://game/runner/pose/runner-clip.gd")
const SAMPLE_TICKS := 24
const TRACK_START := Vector3(40, 0.08, -136)

var runner: Runner
var failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var campus := CAMPUS.instantiate()
	root.add_child(campus)
	runner = campus.get_node("SpecialWeek") as Runner
	var checked := 0
	var slowest := ""
	var minimum := INF
	var args := OS.get_cmdline_user_args()
	var require_full := args.has("--full")
	var directory := RunnerClip.ROSTER_MOTIONS_PATH
	if not require_full and not DirAccess.dir_exists_absolute(directory):
		directory = RunnerClip.ROSTER_RUNS_PATH
	var picks: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://design/unimate/locomotion/picks.json"))
	for file in ResourceLoader.list_directory(directory):
		if not file.ends_with(".res"):
			continue
		var slug := file.get_basename()
		if not _select(slug):
			continue
		var clips := runner.motion._clips
		_check(not require_full or clips.uses_roster_motions(), "%s did not load its full motion library" % slug)
		if clips.uses_roster_motions():
			_check_library(slug, clips, picks)
			await _check_ground_gait(slug, &"walk", &"walk", Runner.Locomotion.Gait.WALK)
			await _check_ground_gait(slug, &"jog", &"", Runner.Locomotion.Gait.JOG)
		var speed := runner.motion.gait_speed(Runner.Locomotion.Gait.RUN)
		if speed < minimum:
			minimum = speed
			slowest = slug
		await _check_run(slug, false)
		checked += 1
	for argument in args:
		if argument.is_valid_int():
			_check(checked == argument.to_int(), "Expected %s libraries, checked %d" % [argument, checked])
	_check(not require_full or checked > 0, "No roster motion libraries were inspected")
	if not slowest.is_empty() and _select(slowest):
		await _check_run(slowest, true)
	print("Verified %d roster libraries, their ground gaits and shared top speed, including the slowest runner in a timed lap." % checked)
	quit(1 if failed else 0)


func _select(slug: String) -> bool:
	var path := "res://art/characters".path_join(slug + ".glb")
	var ready := runner.change_character(path) and runner.motion != null and runner.motion.has_generated_run()
	_check(ready, "%s did not load its generated run" % slug)
	return ready


func _check_library(slug: String, clips: RunnerClip, picks: Dictionary) -> void:
	_check(clips._library.get_animation_list().size() == picks.size(), "%s has an incomplete action set" % slug)
	for action: String in picks:
		var info: Dictionary = clips._info.get(action, {})
		_check(info.get("reference_source") == picks[action]["source"], "%s %s selected the wrong take" % [slug, action])
		_check(clips._tracks.get(action, {}).size() == RunnerClip.BODY_BONES.size() and clips._hips.has(action),
			"%s %s lacks the full rotation and pelvis pose" % [slug, action])
		var frames: Array = info.get("loop_frames", [])
		if frames.size() == 2:
			var period := (float(frames[1]) - float(frames[0])) / RunnerClip.SOURCE_FPS
			_check(is_equal_approx(clips.period(action, 0.0), period), "%s %s changed source timing" % [slug, action])
		_check(info.get("reverse", false) == picks[action].get("reverse", false), "%s %s reversed playback" % [slug, action])
		clips.sample(action, 0.5, not frames.is_empty(), 1.0)
		_check(clips.action == StringName(action) and clips.pelvis.is_finite(), "%s %s did not sample" % [slug, action])
	clips.reset()


func _check_ground_gait(slug: String, action: StringName, modifier: StringName, gait: int) -> void:
	runner._recover_at(TRACK_START)
	runner.camera_arm.rotation.y = -PI * 0.5
	await _ticks(6)
	if modifier != &"":
		Input.action_press(modifier)
	Input.action_press(&"move_forward")
	await _ticks(42)
	var clips := runner.motion._clips
	var period := clips.period(action, 0.0)
	var speed := runner.motion.gait_speed(gait)
	var start := runner.global_position
	var phase_travel := 0.0
	var last_phase := runner.motion._phase
	var matched_ticks := 0
	for tick in SAMPLE_TICKS:
		await physics_frame
		if clips.action == action:
			matched_ticks += 1
		phase_travel += fposmod(runner.motion._phase - last_phase, 1.0)
		last_phase = runner.motion._phase
	var elapsed := float(SAMPLE_TICKS) / Engine.physics_ticks_per_second
	var measured := (runner.global_position - start).slide(Vector3.UP).length() / elapsed
	_check(matched_ticks == SAMPLE_TICKS, "%s did not play its %s clip through gameplay input" % [slug, action])
	_check(absf(measured - speed) < 0.10 and period > 0.0 and absf(phase_travel - elapsed / period) < 0.025,
		"%s changed %s pace or cadence" % [slug, action])
	Input.action_release(&"move_forward")
	if modifier != &"":
		Input.action_release(modifier)


func _check_run(slug: String, timed: bool) -> void:
	var clips := runner.motion._clips
	var info: Dictionary = clips._info["run"]
	var frames: Array = info["loop_frames"]
	var period := clips.period(&"run", 0.0)
	var speed := runner.motion.gait_speed(Runner.Locomotion.Gait.RUN)
	_check(is_equal_approx(period, float(frames[1] - frames[0]) / RunnerClip.SOURCE_FPS),
		"%s changed the source frame timing" % slug)
	runner._recover_at(TRACK_START)
	runner.camera_arm.rotation.y = -PI * 0.5
	await _ticks(6)
	if timed:
		Input.action_press(&"race")
		await _ticks(2)
		Input.action_release(&"race")
		var meet := runner.get_parent().get_node("RunningRace")
		_check(meet._menu.visible, "Race entry menu did not open")
		meet._menu._choose(Callable(meet, "_solo"))
		_check(runner.race.state == Runner.Race.State.COUNTDOWN, "Timed lap did not start")
	else:
		Input.action_press(&"sprint")
	Input.action_press(&"move_forward")
	await _ticks(225 if timed else 42)
	_check(not timed or runner.race.state == Runner.Race.State.RUNNING, "Timed lap is not running")
	var ground_speed := await _check_run_pace(slug, speed, period, SAMPLE_TICKS)

	Input.action_press(&"accelerate_run")
	await _ticks(ceili(Runner.Locomotion.RUN_ACCELERATION_TIME * Engine.physics_ticks_per_second) + 2)
	var limit := Runner.Locomotion.MAX_RUN_SPEED
	var boosted_period := period * speed / limit
	var boosted_ticks := ceili(3.0 * boosted_period * Engine.physics_ticks_per_second)
	var top_speed := await _check_run_pace(slug, limit, boosted_period, boosted_ticks)
	_check(not timed or runner.race.state == Runner.Race.State.RUNNING, "Timed lap stopped during acceleration")
	Input.action_release(&"accelerate_run")
	Input.action_release(&"sprint")
	await _ticks(16)
	if timed:
		_check(clips.action == &"run", "%s dropped the run clip during solo practice" % slug)
	else:
		_check(clips.action != &"run", "%s kept the run clip after releasing Shift" % slug)
	Input.action_release(&"move_forward")
	print("%s%s: %.3f s per base loop, %.2f m/s base, %.3f m/s top" %
		[slug, " (timed lap)" if timed else "", period, ground_speed, top_speed])


func _check_run_pace(slug: String, speed: float, period: float, ticks: int) -> float:
	var clips := runner.motion._clips
	var pose_error := 0.0
	var phase_travel := 0.0
	var previous := runner.motion._phase
	var start := runner.global_position
	for tick in ticks:
		await physics_frame
		_check(clips.action == &"run" and clips.pose.size() == RunnerClip.BODY_BONES.size(),
			"%s did not play its full run pose" % slug)
		for bone: StringName in clips.pose:
			var rotation := runner.motion.rig.get_bone_pose_rotation(runner.motion.rig.find_bone(bone))
			pose_error = maxf(pose_error, rotation.angle_to(clips.pose[bone]))
		phase_travel += fposmod(runner.motion._phase - previous, 1.0)
		previous = runner.motion._phase
	var elapsed := float(ticks) / Engine.physics_ticks_per_second
	var ground_speed := (runner.global_position - start).slide(Vector3.UP).length() / elapsed
	_check(absf(phase_travel - elapsed / period) < 0.025, "%s missed the expected cadence at %.2f m/s" % [slug, speed])
	_check(absf(ground_speed - speed) < 0.05, "%s ran at %.3f m/s, expected %.2f m/s" % [slug, ground_speed, speed])
	_check(pose_error < deg_to_rad(0.6), "%s changed generated joint rotations by %.2f degrees" % [slug, rad_to_deg(pose_error)])
	return ground_speed


func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failed = true
