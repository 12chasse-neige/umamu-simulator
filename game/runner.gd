extends CharacterBody3D

const JOG_SPEED := 3.8
const SPRINT_SPEED := 7.4
const CROUCH_SPEED := 1.35
const CROUCH_HEIGHT := 1.22
const JUMP_SPEED := 4.9
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
const LOCAL_CHARACTER := "res://art/special-week/special-week.glb"

var step_hit := KinematicCollision3D.new()
var mouse_motion := Vector2.ZERO
var crouched := false
var crouch_shape := CapsuleShape3D.new()
var overlap_probe := CapsuleShape3D.new()
var safe_probe := CapsuleShape3D.new()
var clearance_query := PhysicsShapeQueryParameters3D.new()
var recovery_clock := 0.0
var blocked_time := 0.0
var overlap_count := 0
var motion: AnimationPlayer

@onready var facing: Node3D = $Facing
@onready var model_proxy: MeshInstance3D = $Facing/ModelProxy
@onready var camera_arm: SpringArm3D = $CameraArm
@onready var camera_height: float = camera_arm.position.y
@onready var capsule: CollisionShape3D = $Capsule
@onready var standing_shape := capsule.shape as CapsuleShape3D
@onready var spawn := global_position
@onready var last_safe := spawn


func _ready() -> void:
	crouch_shape.radius = standing_shape.radius
	crouch_shape.height = CROUCH_HEIGHT
	overlap_probe.radius = standing_shape.radius - OVERLAP_INSET
	safe_probe.radius = standing_shape.radius + 0.10
	safe_probe.height = standing_shape.height
	clearance_query.collision_mask = collision_mask
	clearance_query.exclude = [get_rid()]
	_set_crouched(false)
	if ResourceLoader.exists(LOCAL_CHARACTER, "PackedScene"):
		var character := load(LOCAL_CHARACTER) as PackedScene
		var model := character.instantiate()
		facing.add_child(model)
		model_proxy.hide()
		motion = model.get_node("AnimationPlayer") as AnimationPlayer
		for clip in [&"Idle", &"Jog", &"Sprint", &"Crouch", &"CrouchWalk"]:
			motion.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		motion.play(&"Idle")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		mouse_motion = Vector2.ZERO


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed(&"reset_player"):
		_recover_at(spawn)
		return
	if global_position.y < FALL_LIMIT:
		_recover_to_safe_ground()
		return

	_update_stance()
	_update_camera(delta)

	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var direction := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, camera_arm.rotation.y)
	var sprinting := not crouched and Input.is_action_pressed(&"sprint")
	var speed := SPRINT_SPEED if sprinting else JOG_SPEED
	if crouched:
		speed = CROUCH_SPEED
	var horizontal := direction * speed
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	var grounded := is_on_floor()
	var jumping := grounded and not crouched and Input.is_action_just_pressed(&"jump")
	if jumping:
		velocity.y = JUMP_SPEED
	elif grounded:
		velocity.y = 0.0
	else:
		velocity.y += get_gravity().y * delta

	var start := global_position
	if jumping or not grounded or direction.is_zero_approx() or not _step_up(horizontal * delta):
		move_and_slide()

	if not direction.is_zero_approx():
		var heading := atan2(direction.x, direction.z)
		facing.rotation.y = lerp_angle(facing.rotation.y, heading, 1.0 - exp(-16.0 * delta))

	var displacement := global_position - start
	var ground_speed := Vector2(displacement.x, displacement.z).length() / delta
	_update_animation(ground_speed, speed, sprinting)
	_check_recovery(delta, not direction.is_zero_approx(), ground_speed)


func _update_stance() -> void:
	if Input.is_action_pressed(&"crouch"):
		if not crouched and is_on_floor():
			_set_crouched(true)
	elif crouched:
		# Sweeping the shorter capsule up checks the space the taller one will occupy.
		var extra_height := standing_shape.height - crouch_shape.height
		if not test_move(global_transform, Vector3.UP * extra_height):
			_set_crouched(false)


func _set_crouched(value: bool) -> void:
	crouched = value
	var shape := crouch_shape if crouched else standing_shape
	capsule.shape = shape
	capsule.position.y = shape.height * 0.5
	model_proxy.position.y = capsule.position.y
	model_proxy.scale.y = shape.height / standing_shape.height
	overlap_probe.height = shape.height - 2.0 * OVERLAP_INSET


func _update_camera(delta: float) -> void:
	var height := camera_height - 0.36 if crouched else camera_height
	camera_arm.position.y = move_toward(camera_arm.position.y, height, 2.5 * delta)
	if not mouse_motion.is_zero_approx():
		var orbit := camera_arm.rotation
		orbit.x = clampf(orbit.x - mouse_motion.y * LOOK_SENSITIVITY, MIN_PITCH, MAX_PITCH)
		orbit.y = wrapf(orbit.y - mouse_motion.x * LOOK_SENSITIVITY, -PI, PI)
		camera_arm.rotation = orbit
		mouse_motion = Vector2.ZERO


func _update_animation(ground_speed: float, speed: float, sprinting: bool) -> void:
	if motion == null:
		return
	var clip: StringName
	var moving := ground_speed > 0.15
	if not is_on_floor():
		clip = &"Jump"
	elif crouched:
		clip = &"CrouchWalk" if moving else &"Crouch"
	elif moving:
		clip = &"Sprint" if sprinting else &"Jog"
	else:
		clip = &"Idle"
	if motion.assigned_animation != clip:
		var blend := 0.06 if clip == &"Jump" else 0.15
		motion.play(clip, blend)
	var loop_has_stride := moving and is_on_floor()
	motion.speed_scale = clampf(ground_speed / speed, 0.35, 1.12) if loop_has_stride else 1.0


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
	global_position = point
	last_safe = point
	velocity = Vector3.ZERO
	_set_crouched(false)
	blocked_time = 0.0
	overlap_count = 0
	recovery_clock = 0.0
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
	var near_depth := maxf(travel.length(), STEP_DEPTH)
	var far_depth := maxf(near_depth, standing_shape.radius + STEP_EDGE_CLEARANCE)
	for depth in [near_depth, far_depth]:
		var stride := direction * float(depth)
		if test_move(raised, stride):
			continue
		var destination := raised.translated(stride)
		if not test_move(destination, -lift, step_hit) or step_hit.get_normal().y < cos(floor_max_angle):
			continue
		var landing := destination.translated(step_hit.get_travel())
		if landing.origin.y <= global_position.y + safe_margin:
			continue
		global_transform = landing
		return true
	return false
