extends SceneTree

const CAMPUS := preload("res://game/campus/campus-walk.tscn")
const PLAN := preload("res://art/campus/interior-access.json")
const Runner := preload("res://game/runner/runner.gd")
const FORWARD := &"move_forward"
const INTERACT := &"interact_door"

var runner: Runner
var arm: SpringArm3D
var doors: Node3D


func _initialize() -> void:
	call_deferred("_check")


func _check() -> void:
	var scene := CAMPUS.instantiate()
	root.add_child(scene)
	runner = scene.get_node("SpecialWeek")
	arm = runner.get_node("CameraArm")
	doors = scene.get_node("Doors")

	var passed := 0
	var total := 0
	for room: Dictionary in PLAN.data.rooms:
		if not room.has("door"):
			continue
		total += 1
		var failure := await _use_bedroom(room)
		if failure.is_empty():
			passed += 1
		else:
			print("%s: %s" % [room.name, failure])
	print("Bedroom door checks passed %d of %d." % [passed, total])
	quit(0 if passed == total and total > 0 else 1)


func _use_bedroom(room: Dictionary) -> String:
	var door := doors.get_node_or_null(NodePath(room.name))
	if door == null:
		return "Missing interactive door."
	var spec: Dictionary = room.door
	var feet := _world(room.point)
	var threshold: Vector3 = door.global_position - Vector3.UP * 0.02
	var approach := threshold - Vector3.RIGHT * float(spec.inward) * 0.92
	runner._recover_at(approach + Vector3.UP * 0.06)
	await _settle(14)
	if not runner.is_on_floor() or runner.global_position.distance_to(approach) > 0.15:
		return "Could not stand outside the door."
	if door.opening > 0.01 or doors.reachable_door() != door:
		return "Closed door is out of reach from the lounge."
	await _interact()
	if door.opening < 0.99:
		return "Door would not open from the lounge."
	if not await _walk(feet):
		return "Runner could not get past the open leaf."
	if doors.reachable_door() != door:
		return "Door is out of reach from inside the bedroom."
	await _interact()
	if door.opening > 0.01 or not runner.is_on_floor():
		return "Could not close the door while standing in the bedroom."
	await _interact()
	if door.opening < 0.99 or not await _walk(approach):
		return "Could not reopen the door and leave."
	return ""


func _settle(frames: int) -> void:
	for tick in frames:
		await physics_frame


func _interact() -> void:
	# Send a real action event so the door manager receives the same input as in play.
	var event := InputEventAction.new()
	event.action = INTERACT
	event.pressed = true
	Input.parse_input_event(event)
	await _settle(2)
	event.pressed = false
	Input.parse_input_event(event)
	await _settle(26)


func _walk(target: Vector3) -> bool:
	var arrived := false
	var default_pace := Runner.Locomotion.SPEEDS[Runner.Locomotion.Gait.JOG]
	var pace := runner.motion.gait_speed(Runner.Locomotion.Gait.JOG) if runner.motion != null else default_pace
	var ticks := ceili(160.0 * maxf(1.0, default_pace / pace))
	for tick in ticks:
		var offset := target - runner.global_position
		var horizontal := Vector2(offset.x, offset.z).length()
		if horizontal < 0.11 and absf(offset.y) < 0.13:
			arrived = true
			break
		arm.rotation.y = atan2(-offset.x, -offset.z)
		Input.action_press(FORWARD, clampf(horizontal * 1.55, 0.42, 0.67))
		await physics_frame
	Input.action_release(FORWARD)
	await _settle(6)
	return arrived


func _world(point: Array) -> Vector3:
	return Vector3(point[0], point[2], -point[1])
