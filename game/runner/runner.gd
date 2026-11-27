extends CharacterBody3D

const RacePace := preload("res://game/race/race-pace.gd")
const Locomotion := preload("res://game/runner/runner-control.gd")
const Race := preload("res://game/campus/track-race.gd")
const Vault := preload("res://game/runner/traversal/runner-vault.gd")
const RunnerPose := preload("res://game/runner/pose/runner-pose.gd")
const WallClimb := preload("res://game/runner/traversal/wall-climb.gd")
const WallLedge := preload("res://game/runner/traversal/wall-ledge.gd")
const PracticeLadder := preload("res://game/campus/practice-ladder.gd")

const CROUCH_SPEED := 1.35
const CROUCH_HEIGHT := 1.22
const PRONE_HEIGHT := 0.66
const CLIMB_SPEED := 0.76
const STEP_HEIGHT := 0.23
const STEP_DEPTH := 0.15
const STEP_EDGE_CLEARANCE := 0.055
const LOOK_SENSITIVITY := 0.0028
const MIN_PITCH := deg_to_rad(-70.0)
const MAX_PITCH := deg_to_rad(16.0)
const RECOVERY_INTERVAL := 0.25
const STUCK_DELAY := 1.0
const OVERLAP_INSET := 0.04
const ESCAPE_DISTANCE := 0.18
const FALL_LIMIT := -15.0
const LOCAL_CHARACTER := RunnerPose.RunnerClip.CHARACTER_PATH
const DETAIL_CHARACTER := "res://art/special-week/special-week-detail.glb"
const FULL_CHARACTER := "res://art/special-week/special-week.glb"
const KICK_REACH := 0.78
const BALL_RADIUS := 0.11
const KICK_IMPULSE := 3.0

enum ClimbState { INACTIVE, ENTER, SCALE, EXIT }

@export_file("*.glb") var character_path := LOCAL_CHARACTER
@export var climb_hint: Label
@export var race_hint: Label
@export var practice_ball: RigidBody3D

var step_hit := KinematicCollision3D.new()
var mouse_motion := Vector2.ZERO
var crouched := false
var crouch_shape := CapsuleShape3D.new()
var _stance_progress := 0.0
var overlap_probe := CapsuleShape3D.new()
var safe_probe := CapsuleShape3D.new()
var clearance_query := PhysicsShapeQueryParameters3D.new()
var recovery_clock := 0.0
var blocked_time := 0.0
var overlap_count := 0
var motion: RunnerPose
var active_character_path := ""
var _character_model: Node3D
var control := Locomotion.new()
var race := Race.new()
var competition := false
var movement_locked := false
var race_pace: RacePace
var computer_controlled := false
var rival_direction := Vector3.ZERO
var prone := false
var _stair_grade := 0.0
var tread_depth := 0.32
var _wall: WallLedge
var _vault: Vault
var _vault_cooldown := 0.0
var _kick_elapsed := -1.0
var _kick_duration := 0.70
var _kick_strike := 0.72
var _kick_hit := false
var _kick_contact := Vector3.ZERO
var _tread_support := false
var _step_visual_offset := 0.0
var _ladder: PracticeLadder
var _climb_state := ClimbState.INACTIVE
var _climb_height := 0.0
var _climb_rate := 0.0
var _climb_destination := Vector3.ZERO

@onready var facing: Node3D = $Facing
@onready var model_proxy: MeshInstance3D = $Facing/ModelProxy
@onready var camera_arm: SpringArm3D = $CameraArm
@onready var camera_height: float = camera_arm.position.y
@onready var capsule: CollisionShape3D = $Capsule
@onready var standing_shape := capsule.shape as CapsuleShape3D
@onready var spawn := global_position
@onready var last_safe := spawn
@onready var _ball_spawn := practice_ball.global_transform if practice_ball != null else Transform3D.IDENTITY


func _ready() -> void:
	crouch_shape.radius = standing_shape.radius
	crouch_shape.height = standing_shape.height
	overlap_probe.radius = standing_shape.radius - OVERLAP_INSET
	safe_probe.radius = standing_shape.radius + 0.10
	safe_probe.height = standing_shape.height
	clearance_query.collision_mask = collision_mask
	clearance_query.exclude = [get_rid()]
	_reset_stance()
	if character_path == LOCAL_CHARACTER and not ResourceLoader.exists(LOCAL_CHARACTER, "PackedScene"):
		character_path = FULL_CHARACTER
	if not character_path.is_empty() and ResourceLoader.exists(character_path, "PackedScene"):
		change_character(character_path)
	if not computer_controlled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		set_process_unhandled_input(false)


func change_character(path: String) -> bool:
	if path == active_character_path:
		return true
	var model: Node3D
	var driver: RunnerPose
	if not path.is_empty():
		if not ResourceLoader.exists(path, "PackedScene"):
			return false
		var skin_path := DETAIL_CHARACTER if path == LOCAL_CHARACTER and ResourceLoader.exists(DETAIL_CHARACTER, "PackedScene") else path
		var character := load(skin_path) as PackedScene
		if character == null:
			return false
		var instance := character.instantiate()
		model = instance as Node3D
		if model == null:
			instance.free()
			return false
		facing.add_child(model)
		for node in model.find_children("*", "AnimationPlayer", true, false):
			var animation := node as AnimationPlayer
			animation.stop()
			animation.active = false
		var skeletons := model.find_children("*", "Skeleton3D", true, false)
		driver = RunnerPose.new()
		if skeletons.is_empty() or not driver.bind(skeletons[0] as Skeleton3D, facing, model, path == LOCAL_CHARACTER, path):
			facing.remove_child(model)
			model.queue_free()
			return false
		model.reset_physics_interpolation()

	if _character_model != null:
		facing.remove_child(_character_model)
		_character_model.queue_free()
	_character_model = model
	motion = driver
	active_character_path = path
	model_proxy.visible = model == null
	return true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		mouse_motion = Vector2.ZERO
	elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseMotion:
			mouse_motion += event.screen_relative
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not computer_controlled:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Input.action_release(&"accelerate_run")
		mouse_motion = Vector2.ZERO


func _physics_process(delta: float) -> void:
	var exploring := not competition and not computer_controlled
	if exploring and Input.is_action_just_pressed(&"reset_player"):
		_recover_at(spawn)
		if practice_ball != null:
			practice_ball.global_transform = _ball_spawn
			practice_ball.linear_velocity = Vector3.ZERO
			practice_ball.angular_velocity = Vector3.ZERO
			practice_ball.reset_physics_interpolation()
		return
	if global_position.y < FALL_LIMIT:
		_recover_to_safe_ground()
		return

	if not computer_controlled:
		_update_camera(delta)
	if exploring:
		race.update(global_position, race.active() and Input.is_action_just_pressed(&"race"), delta)
		_update_race_hint()
	_vault_cooldown = maxf(0.0, _vault_cooldown - delta)
	if _vault != null:
		_update_vault(delta)
		return
	if exploring and (_update_wall(delta) or _update_climb(delta)):
		_kick_elapsed = -1.0
		control.update_run_boost(false, delta)
		_smooth_step_visual(0.0, delta)
		return
	if exploring:
		_update_stance(delta)
		_update_kick(delta)

	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var direction := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, camera_arm.rotation.y)
	if computer_controlled:
		direction = rival_direction
	if movement_locked or race.state == Race.State.COUNTDOWN or prone or _kick_elapsed >= 0.0:
		direction = Vector3.ZERO
	var gait := control.requested_gait(Input.is_action_pressed(&"walk"),
		Input.is_action_pressed(&"sprint"))
	if competition or race.active():
		gait = Locomotion.Gait.RUN
	elif computer_controlled:
		gait = Locomotion.Gait.WALK
	var run_requested := gait == Locomotion.Gait.RUN and not direction.is_zero_approx()
	var grounded := on_walkable_ground()
	var can_accelerate_run := run_requested and grounded and _stance_progress < 0.02 \
		and control.flight == Locomotion.Flight.GROUNDED
	control.update_run_boost(exploring and can_accelerate_run and Input.is_action_pressed(&"accelerate_run"), delta)
	var speeds := Locomotion.SPEEDS
	if motion != null:
		speeds = motion.gait_speeds()
	var speed: float = speeds[gait]
	var run_cadence_scale := 1.0
	if race_pace != null:
		if not computer_controlled:
			race_pace.pushing = can_accelerate_run and Input.is_action_pressed(&"accelerate_run")
		if gait == Locomotion.Gait.RUN:
			speed = race_pace.speed_cap * (1.0 if race_pace.pushing else RacePace.CRUISE)
		else:
			speed = minf(speed * race_pace.surface_scale, race_pace.speed_cap)
	elif gait == Locomotion.Gait.RUN:
		var boost := control.run_boost if can_accelerate_run else 0.0
		speed = lerpf(minf(speed, Locomotion.MAX_RUN_SPEED), Locomotion.MAX_RUN_SPEED, boost)
	if gait == Locomotion.Gait.RUN:
		run_cadence_scale = speed / speeds[gait]
	speed = lerpf(speed, CROUCH_SPEED, minf(1.0, _stance_progress))
	speed *= 1.0 - smoothstep(1.0, 2.0, _stance_progress)
	var grade := _sample_grade(direction) if grounded and direction.length_squared() > 0.01 else 0.0
	_stair_grade = lerpf(_stair_grade, grade, 1.0 - exp(-delta * (12.0 if grade != 0.0 else 4.0)))
	# Carry the approach pace onto a flight. Grade costs a fraction of the
	# requested speed, so running, jogging and partial stick input stay distinct.
	var slope := smoothstep(0.04, 0.52, absf(_stair_grade))
	var terrain_speed := direction.length() * speed * (1.0 - slope * (0.22 if _stair_grade > 0.0 else 0.17))

	var current := Vector3(velocity.x, 0.0, velocity.z)
	if race_pace != null:
		# Apply forward acceleration independently of the traction used to steer.
		terrain_speed = race_pace.speed_after_acceleration(current.length(), terrain_speed, delta)
	var horizontal := control.horizontal(current, direction.normalized() * terrain_speed, grounded, delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	velocity.y = control.vertical(velocity.y, get_gravity().y, grounded,
		_stance_progress < 0.05 and _kick_elapsed < 0.0,
		exploring and Input.is_action_just_pressed(&"jump"), delta,
		not _low_ground_ahead())
	# A shorter rig can reach steady jog below the default approach speed.
	var vault_speed := minf(1.44, 0.92 * speeds[Locomotion.Gait.JOG])
	var approaching := horizontal.length_squared() > vault_speed * vault_speed and direction.dot(horizontal.normalized()) > 0.76
	if exploring and grounded and not crouched and approaching and velocity.y <= 0.0 and _vault_cooldown == 0.0:
		_vault = Vault.find(self, horizontal, horizontal.length())
		if _vault != null:
			_update_vault(delta)
			return
	var impact_speed := velocity.y
	var start := global_position
	var stepped := not competition and grounded and impact_speed <= 0.0 and horizontal.length_squared() >= 0.0064 and _step_up(horizontal * delta)
	if not stepped:
		move_and_slide()

	# A rounded capsule can leave the floor classification on the nosing even
	# with the next tread immediately below. Keep support only over a measured
	# walkable tread, and sweep downward so the riser still limits the capsule.
	_tread_support = false
	if grounded and impact_speed <= 0.0 and not is_on_floor():
		var floor_hit := _tread_below(global_position)
		# On a measured descent the back half of the capsule can still
		# overlap a tread when the center is already over the next riser.
		if floor_hit.is_empty() and _stair_grade < -0.04 and not horizontal.is_zero_approx():
			var rear := global_position - horizontal.normalized() * standing_shape.radius * 0.5
			floor_hit = _tread_below(rear)
		if not floor_hit.is_empty():
			move_and_collide(Vector3.DOWN * maxf(0.0, global_position.y - floor_hit.position.y))
			apply_floor_snap()
			_tread_support = true
			velocity.y = 0.0

	var displacement := global_position - start
	_smooth_step_visual(displacement.y if grounded and on_walkable_ground() and impact_speed <= 0.0 else 0.0, delta)
	var ground_speed := Vector2(displacement.x, displacement.z).length() / delta
	if race_pace != null and grounded and run_requested:
		_record_race_collision(current.length(), horizontal, ground_speed)
	var heading_error := 0.0
	if not direction.is_zero_approx():
		heading_error = angle_difference(facing.rotation.y, atan2(direction.x, direction.z))
	if ground_speed > 0.13 or not direction.is_zero_approx():
		var heading := atan2(displacement.x, displacement.z)
		if ground_speed < 0.60 and not direction.is_zero_approx():
			heading = atan2(direction.x, direction.z)
		var yaw_step := angle_difference(facing.rotation.y, heading) * (1.0 - exp(-13.0 * delta))
		facing.rotation.y += clampf(yaw_step, -6.8 * delta, 6.8 * delta)
	var land_impact := clampf((-impact_speed - 1.8) / 4.2, 0.0, 1.0) if not grounded and is_on_floor() else 0.0
	if motion != null:
		if _kick_elapsed >= 0.0 and is_on_floor():
			_pose_kick(delta)
		else:
			motion.ground(self, displacement, _stance_progress, land_impact,
				heading_error, _stair_grade, delta, control.stride_for_speed(ground_speed, speeds),
				control, run_requested, run_cadence_scale)
	if exploring:
		_check_recovery(delta, not direction.is_zero_approx(), ground_speed)


func _record_race_collision(approach_speed: float, travel: Vector3, ground_speed: float) -> void:
	for index in get_slide_collision_count():
		var hit := get_slide_collision(index)
		var normal := hit.get_normal()
		if absf(normal.y) < 0.5 and travel.dot(normal) < -0.1:
			var remaining_speed := minf(ground_speed, velocity.slide(Vector3.UP).length())
			race_pace.note_collision(approach_speed, remaining_speed)
			return


func _update_kick(delta: float) -> void:
	if motion == null or practice_ball == null or not is_on_floor() or crouched:
		_kick_elapsed = -1.0
		return
	if _kick_elapsed >= 0.0:
		_kick_elapsed += delta
		if _kick_elapsed >= _kick_duration:
			_kick_elapsed = -1.0
		return
	if not Input.is_action_just_pressed(&"kick") or velocity.length_squared() > 1.0:
		return
	var offset := practice_ball.global_position - global_position
	var flat := Vector3(offset.x, 0.0, offset.z)
	if offset.y < -0.02 or offset.y > 0.26 or flat.length() > KICK_REACH or flat.length() < 0.30:
		return
	if facing.global_basis.z.dot(flat.normalized()) < 0.65:
		return
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.16,
		practice_ball.global_position, collision_mask, [get_rid(), practice_ball.get_rid()])
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return
	_kick_duration = motion._clips.period(&"kick", 0.70)
	_kick_strike = motion._clips.contact_phase(&"kick", 0.72)
	_kick_elapsed = 0.0
	_kick_hit = false


func _pose_kick(delta: float) -> void:
	var ball := practice_ball.global_position
	var offset := ball - global_position
	var direction := Vector3(offset.x, 0.0, offset.z).normalized()
	var phase := _kick_elapsed / _kick_duration
	if not _kick_hit:
		_kick_contact = ball - direction * BALL_RADIUS
		if phase <= _kick_strike:
			var yaw := atan2(direction.x, direction.z)
			facing.rotation.y = lerp_angle(facing.rotation.y, yaw, 1.0 - exp(-16.0 * delta))
	motion.kick(phase, _kick_contact, _kick_strike, delta)
	if not _kick_hit and phase >= _kick_strike and phase <= _kick_strike + 0.14:
		if motion.kick_toe_position().distance_to(ball) <= BALL_RADIUS + 0.075:
			practice_ball.apply_central_impulse(direction * KICK_IMPULSE + Vector3.UP * 0.22)
			_kick_hit = true


func _update_vault(delta: float) -> void:
	control.reset()
	var forward := _vault.forward
	facing.rotation.y = lerp_angle(facing.rotation.y, atan2(forward.x, forward.z),
		1.0 - exp(-16.0 * delta))
	_smooth_step_visual(0.0, delta)
	var continuing := _vault.advance(self, delta)
	if motion != null:
		motion.vault(_vault.phase, _vault.handhold, delta)
	if not continuing:
		_vault = null
		_vault_cooldown = 0.36
		apply_floor_snap()


func _low_ground_ahead() -> bool:
	if is_on_floor() or velocity.y >= -1.0:
		return false
	var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.04,
		global_position + Vector3.DOWN * 0.26, collision_mask, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return not hit.is_empty() and hit.normal.y > 0.64


func _update_race_hint() -> void:
	if race_hint == null:
		return
	match race.state:
		Race.State.COUNTDOWN:
			race_hint.text = tr("Race starts in %d") % ceili(race.time)
		Race.State.RUNNING:
			race_hint.text = tr("Practice   %05.1f s   ·   G Cancel") % race.time
		Race.State.FINISHED:
			race_hint.text = tr("Lap complete   %.2f s") % race.time
			if race.at_start(global_position):
				race_hint.text += "   ·   " + tr("G   Race entry")
		_:
			race_hint.text = "G   Race entry" if race.at_start(global_position) else ""
	race_hint.visible = not race_hint.text.is_empty()


func on_walkable_ground() -> bool:
	return is_on_floor() or _tread_support


func _tread_below(point: Vector3) -> Dictionary:
	var reach := maxf(STEP_HEIGHT, floor_snap_length) + safe_margin
	var hit := WallLedge._ray(self, point + Vector3.UP * 0.04, point - Vector3.UP * reach)
	return hit if not hit.is_empty() and hit.normal.y >= cos(floor_max_angle) else {}


func _update_stance(delta: float) -> void:
	var target := 0.0
	if on_walkable_ground():
		if Input.is_action_pressed(&"prone"):
			target = 2.0 if prone or _prone_clearance() else 1.0
		elif Input.is_action_pressed(&"crouch"):
			target = 1.0
	else:
		target = _stance_progress
	if target < _stance_progress:
		var next_stance := maxf(target, 1.0) if _stance_progress > 1.0 else target
		var clearance := _height_for_stance(next_stance) - crouch_shape.height
		if clearance > 0.0 and test_move(global_transform, Vector3.UP * clearance):
			return
	var step := move_toward(_stance_progress, target, delta / (0.31 if target > _stance_progress else 0.36))
	if step != _stance_progress:
		_stance_progress = step
		_apply_stance()


func _prone_clearance() -> bool:
	var forward := facing.global_basis.z
	# The prone pose extends beyond the standing capsule in both directions.
	for reach: float in [0.66, -0.56]:
		var start := global_position + Vector3.UP * 0.20
		var query := PhysicsRayQueryParameters3D.create(start, start + forward * reach,
			collision_mask, [get_rid()])
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			return false
	return true


func _reset_stance() -> void:
	_stance_progress = 0.0
	_apply_stance()


func _height_for_stance(progress: float) -> float:
	if progress <= 1.0:
		return lerpf(standing_shape.height, CROUCH_HEIGHT, smoothstep(0.0, 1.0, progress))
	return lerpf(CROUCH_HEIGHT, PRONE_HEIGHT, smoothstep(1.0, 2.0, progress))


func _apply_stance() -> void:
	crouched = _stance_progress > 0.05
	prone = _stance_progress > 1.05
	crouch_shape.height = _height_for_stance(_stance_progress)
	capsule.shape = crouch_shape
	capsule.position.y = crouch_shape.height * 0.5
	model_proxy.position.y = capsule.position.y
	model_proxy.scale.y = crouch_shape.height / standing_shape.height
	overlap_probe.height = crouch_shape.height - 2.0 * OVERLAP_INSET


func _update_camera(delta: float) -> void:
	var height := camera_height - 0.36 * smoothstep(0.0, 1.0, _stance_progress) - 0.36 * smoothstep(1.0, 2.0, _stance_progress)
	height += _step_visual_offset * 0.72
	camera_arm.position.y = move_toward(camera_arm.position.y, height, 2.5 * delta)
	if not mouse_motion.is_zero_approx():
		var orbit := camera_arm.rotation
		orbit.x = clampf(orbit.x - mouse_motion.y * LOOK_SENSITIVITY, MIN_PITCH, MAX_PITCH)
		orbit.y = wrapf(orbit.y - mouse_motion.x * LOOK_SENSITIVITY, -PI, PI)
		camera_arm.rotation = orbit
		mouse_motion = Vector2.ZERO


func _smooth_step_visual(rise: float, delta: float) -> void:
	var previous := _step_visual_offset
	_step_visual_offset = clampf((previous - rise) * exp(-11.0 * delta), -STEP_HEIGHT, STEP_HEIGHT)
	facing.position.y = _step_visual_offset
	camera_arm.position.y += (_step_visual_offset - previous) * 0.72


func _sample_grade(direction: Vector3) -> float:
	var along := direction.normalized()
	var previous := INF
	var signed_steps := 0
	var rise := 0.0
	var first_edge := 0.0
	var last_edge := 0.0
	# Count distinct risers along the direction of travel and estimate their spacing.
	for sample in 9:
		var distance := -0.28 + sample * 0.12
		var point := global_position + along * distance
		var hit := WallLedge._ray(self, point + Vector3.UP * 0.53, point + Vector3.DOWN * 0.62)
		if hit.is_empty() or hit.normal.y < 0.96:
			previous = INF
			continue
		var height: float = hit.position.y
		if is_finite(previous):
			var change := height - previous
			if absf(change) >= 0.045 and absf(change) <= STEP_HEIGHT + 0.01:
				if signed_steps == 0:
					first_edge = distance
				last_edge = distance
				signed_steps += int(signf(change))
				rise += change
		previous = height
	if absi(signed_steps) < 2:
		return 0.0
	var measured := (last_edge - first_edge) / (absi(signed_steps) - 1)
	tread_depth = lerpf(tread_depth, clampf(measured, 0.22, 0.46), 0.10)
	return clampf(rise / 0.96, -1.0, 1.0)


func _update_wall(delta: float) -> bool:
	if _wall == null:
		if _climb_state != ClimbState.INACTIVE or crouched or not Input.is_action_just_pressed(&"climb") or _reachable_ladder() != null:
			return false
		_wall = WallClimb.find_face(self, facing.global_basis.z, true)
		if _wall == null:
			_wall = WallLedge.find_grip(self, facing.global_basis.z)
		if _wall == null:
			_wall = WallClimb.find_face(self, facing.global_basis.z)
		if _wall == null:
			return false
		control.reset()
		_tread_support = false
	elif Input.is_action_just_pressed(&"climb"):
		_wall = null
		return false
	velocity = Vector3.ZERO
	var forward := -_wall.normal
	facing.rotation.y = lerp_angle(facing.rotation.y, atan2(forward.x, forward.z), 1.0 - exp(-17.0 * delta))
	var climb_input := Vector2(Input.get_axis(&"move_left", &"move_right"),
		Input.get_axis(&"move_back", &"move_forward")).limit_length()
	var wall := _wall as WallClimb
	if wall != null and not wall.tree and climb_input.y > 0.1:
		var ledge: WallLedge = WallLedge.find_grip(self, forward)
		if ledge != null and ledge.lip.y - global_position.y <= 1.30:
			_wall = ledge
			if motion != null:
				motion.begin_climb_transfer()
	if not _wall.advance(self, climb_input, delta):
		var lower: WallClimb
		if climb_input.y < 0.0 and not _wall is WallClimb and not _wall._supported_at_base:
			lower = WallClimb.find_face(self, forward)
		_wall = lower
		if _wall == null:
			_set_climb_hint("")
			return false
		if motion != null:
			motion.begin_climb_transfer()
	wall = _wall as WallClimb
	var clip := &"mantle"
	if wall != null:
		clip = &"tree" if wall.tree else wall.direction_name
		_set_climb_hint("W / S   Climb tree     F   Let go" if wall.tree else "WASD   Climb wall     F   Let go")
	else:
		_set_climb_hint("W   Pull up     S   Lower     F   Let go")
	if motion != null:
		motion.climb(_wall.feet(self), _wall.hands(self), _wall.top_blend(self), delta,
			wall == null, clip, _wall.clip_phase(), wall.clip_rate if wall != null else 0.0)
	return true


func _update_climb(delta: float) -> bool:
	if _climb_state == ClimbState.INACTIVE:
		var nearby := _reachable_ladder()
		_set_climb_hint("F   Climb" if nearby != null and is_on_floor() and not crouched else "")
		if nearby == null or crouched or not is_on_floor() or not Input.is_action_just_pressed(&"climb"):
			return false
		_ladder = nearby
		_climb_height = _ladder.entry_level(global_position) * PracticeLadder.RUNG_GAP
		_climb_destination = _ladder.track_point(_climb_height) + Vector3.UP * PracticeLadder.EXIT_LIFT
		_climb_state = ClimbState.ENTER
		velocity = Vector3.ZERO
		control.reset()
		# Clear the deck lip before moving out over the ladder.
		if _climb_height > 0.0:
			move_and_collide(Vector3.UP * PracticeLadder.EXIT_LIFT)
	elif Input.is_action_just_pressed(&"climb"):
		_end_climb()
		return false

	_set_climb_hint("W / S   Climb     F   Let go")
	var forward := -_ladder.global_basis.z
	facing.rotation.y = lerp_angle(facing.rotation.y, atan2(forward.x, forward.z), 1.0 - exp(-19.0 * delta))
	var previous_height := _climb_height
	if _climb_state == ClimbState.SCALE:
		var direction := Input.get_axis(&"move_back", &"move_forward")
		_climb_rate = move_toward(_climb_rate, direction * CLIMB_SPEED, 5.0 * delta) if direction != 0.0 else 0.0
		var next_height := clampf(_climb_height + _climb_rate * delta, 0.0, PracticeLadder.DECK_HEIGHT)
		var target := _ladder.track_point(next_height) + Vector3.UP * PracticeLadder.EXIT_LIFT
		if move_and_collide(target - global_position) == null:
			_climb_height = next_height
		if direction > 0.0 and is_equal_approx(_climb_height, PracticeLadder.DECK_HEIGHT):
			_climb_state = ClimbState.EXIT
			_climb_destination = _ladder.exit_point()
		elif direction < 0.0 and is_zero_approx(_climb_height):
			_end_climb()
			return false
	else:
		var offset := _climb_destination - global_position
		if offset.length() < 0.025:
			if _climb_state == ClimbState.EXIT:
				_end_climb()
				return false
			_climb_state = ClimbState.SCALE
		elif move_and_collide(offset.limit_length(1.7 * delta)) != null:
			_end_climb()
			return false

	if motion != null:
		var hands := _ladder.holds(_climb_height, true)
		var feet := _ladder.holds(_climb_height, false)
		var finishing := 0.0
		if _climb_state == ClimbState.EXIT:
			var track := _ladder.track_point(PracticeLadder.DECK_HEIGHT)
			finishing = smoothstep(0.0, 0.80, global_position.distance_to(track))
			for side in 2:
				var width := 0.105 if side == 0 else -0.105
				var exit_contact := global_position + facing.global_basis.x * width
				feet[side] = feet[side].lerp(exit_contact - Vector3.UP * PracticeLadder.EXIT_LIFT, finishing)
				hands[side] = hands[side].lerp(exit_contact + Vector3.UP * 0.87 + forward * 0.08, finishing)
		var travel_rate := clampf((_climb_height - previous_height) / (CLIMB_SPEED * delta), -1.0, 1.0)
		motion.climb(feet, hands, finishing, delta, false, &"ladder",
			_climb_height / (2.0 * PracticeLadder.RUNG_GAP), travel_rate)
	return true


func _reachable_ladder() -> PracticeLadder:
	for node in get_tree().get_nodes_in_group(&"practice_ladders"):
		var ladder := node as PracticeLadder
		if ladder.entry_level(global_position) >= 0:
			return ladder
	return null


func _set_climb_hint(message: String) -> void:
	if climb_hint != null:
		climb_hint.text = message
		climb_hint.visible = not message.is_empty()


func _end_climb() -> void:
	_climb_rate = 0.0
	_climb_state = ClimbState.INACTIVE
	_ladder = null
	velocity = Vector3.ZERO
	_set_climb_hint("")


func _check_recovery(delta: float, trying_to_move: bool, ground_speed: float) -> void:
	blocked_time = blocked_time + delta if trying_to_move and ground_speed < 0.15 else 0.0
	recovery_clock += delta
	if recovery_clock < RECOVERY_INTERVAL:
		return
	recovery_clock = 0.0
	# The inset leaves ordinary floor and wall contact outside the overlap test.
	var embedded := _overlaps(overlap_probe, capsule.global_position)
	overlap_count = overlap_count + 1 if embedded else 0
	if overlap_count >= 3 or (blocked_time >= STUCK_DELAY and not _has_escape_route()):
		_recover_to_safe_ground()
	elif not embedded and is_on_floor() and not crouched and _is_clear_for_recovery(global_position):
		last_safe = global_position


func _has_escape_route() -> bool:
	# A wall blocks one direction. A wedge blocks every nearby way out.
	for direction in 8:
		var travel := Vector3.FORWARD.rotated(Vector3.UP, direction * TAU / 8.0) * ESCAPE_DISTANCE
		if not test_move(global_transform, travel):
			return true
	return false


func _is_clear_for_recovery(point: Vector3) -> bool:
	var center := point + Vector3.UP * (safe_probe.height * 0.5 + 0.10)
	return not _overlaps(safe_probe, center)


func _overlaps(shape: Shape3D, center: Vector3) -> bool:
	clearance_query.shape = shape
	clearance_query.transform = Transform3D(Basis.IDENTITY, center)
	return not get_world_3d().direct_space_state.intersect_shape(clearance_query, 1).is_empty()


func _recover_to_safe_ground() -> void:
	_recover_at(last_safe if _is_clear_for_recovery(last_safe) else spawn)


func _recover_at(point: Vector3) -> void:
	_end_climb()
	global_position = point
	last_safe = point
	velocity = Vector3.ZERO
	_reset_stance()
	blocked_time = 0.0
	overlap_count = 0
	recovery_clock = 0.0
	control.reset()
	if race_pace != null:
		race_pace.clear_collision_recovery()
	race.reset()
	_wall = null
	_vault = null
	_vault_cooldown = 0.0
	_kick_elapsed = -1.0
	_stair_grade = 0.0
	tread_depth = 0.32
	_tread_support = false
	_step_visual_offset = 0.0
	facing.position.y = 0.0
	camera_arm.position.y = camera_height
	if motion != null:
		motion.reset()
	reset_physics_interpolation()


func _step_up(travel: Vector3) -> bool:
	if not test_move(global_transform, travel, step_hit):
		return false
	var direction := travel.normalized()
	# The capsule can report a floor-like normal at the rounded edge of a blocked tread.
	var along := step_hit.get_travel().dot(direction)
	if step_hit.get_normal().y >= cos(floor_max_angle) and along > travel.length() * 0.65:
		return false

	var lift := Vector3.UP * STEP_HEIGHT
	if test_move(global_transform, lift, step_hit):
		lift.y = step_hit.get_travel().y - safe_margin
		if lift.y <= safe_margin:
			return false

	var raised := global_transform.translated(lift)
	if test_move(raised, travel):
		return false
	var next := raised.translated(travel)
	if not test_move(next, -lift, step_hit):
		return false
	next = next.translated(step_hit.get_travel())
	if next.origin.y <= global_position.y + safe_margin:
		return false
	# The capsule touches the rounded edge before its centre is over the tread.
	# Verify the top at toe distance, then spend only this tick's horizontal travel.
	for depth in [STEP_DEPTH, standing_shape.radius + STEP_EDGE_CLEARANCE]:
		var ahead := next.origin + direction * float(depth)
		ahead.y = global_position.y + STEP_HEIGHT + safe_margin
		var query := PhysicsRayQueryParameters3D.create(ahead, ahead - Vector3.UP * STEP_HEIGHT,
			collision_mask, [get_rid()])
		var tread := get_world_3d().direct_space_state.intersect_ray(query)
		if not tread.is_empty() and tread.normal.y >= cos(floor_max_angle):
			global_transform = next
			return true
		# A capsule can already reach a walkable rounded edge before a vertical ray
		# clears a protruding nosing. Check that support along the raised path.
		var stride := direction * float(depth)
		if not test_move(raised, stride) and test_move(raised.translated(stride), -lift, step_hit):
			if step_hit.get_normal().y >= cos(floor_max_angle) and step_hit.get_travel().y > -lift.y + safe_margin:
				global_transform = next
				return true
	return false
