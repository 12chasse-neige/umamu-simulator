extends SceneTree

const CAMPUS_SCENE := preload("res://game/campus-walk.tscn")
const ROUTES_PATH := "res://art/campus/interior-access.json"
const MOVE_FORWARD := &"move_forward"
const WALK_MARGIN := 0.105

var runner: CharacterBody3D
var camera_arm: SpringArm3D
var doors: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var routes: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROUTES_PATH))
	if not routes is Dictionary or not routes.has("links"):
		push_error("Could not read campus routes.")
		quit(1)
		return

	var campus := CAMPUS_SCENE.instantiate()
	root.add_child(campus)
	runner = campus.get_node("SpecialWeek")
	camera_arm = runner.get_node("CameraArm")
	doors = campus.get_node("Doors")

	var args := OS.get_cmdline_user_args()
	var filter := args[0] if not args.is_empty() else ""
	var passed := 0
	var attempted := 0
	for route in routes.links:
		if not filter.is_empty() and not String(route.name).containsn(filter):
			continue
		for reverse in [false, true]:
			var waypoints: Array = route.points.duplicate()
			if reverse:
				waypoints.reverse()
			var failure := await _walk(_turns(waypoints))
			attempted += 1
			if failure.is_empty():
				passed += 1
			else:
				var direction := "outbound" if reverse else "inbound"
				print("%s [%s] %s" % [route.name, direction, failure])

	print("Campus route walks passed %d of %d." % [passed, attempted])
	quit(0 if attempted > 0 and passed == attempted else 1)


func _world_point(coordinate: Array) -> Vector3:
	return Vector3(coordinate[0], coordinate[2], -coordinate[1])


func _turns(waypoints: Array) -> Array[Vector3]:
	# Steer at the turns. Walk naturally over consecutive treads on a straight flight.
	var course: Array[Vector3] = [_world_point(waypoints[0])]
	for index in range(1, waypoints.size() - 1):
		var point := _world_point(waypoints[index])
		var from := point - _world_point(waypoints[index - 1])
		var toward := _world_point(waypoints[index + 1]) - point
		var arrival := Vector2(from.x, from.z).normalized()
		var departure := Vector2(toward.x, toward.z).normalized()
		if arrival.dot(departure) < 0.92:
			course.append(point)
	course.append(_world_point(waypoints[-1]))
	return course


func _walk(course: Array[Vector3]) -> String:
	runner._recover_at(course[0] + Vector3.UP * 0.06)
	for tick in 14:
		await physics_frame
	if runner.global_position.distance_to(course[0]) > 0.24 or not runner.is_on_floor():
		return "Could not stand at %s. Reached %s." % [course[0], runner.global_position]

	for index in range(1, course.size()):
		var point := course[index]
		var arrived := false
		for tick in 650:
			var door: Node3D = doors.reachable_door()
			if door != null and not door.wants_open:
				door.toggle()
			var offset := point - runner.global_position
			var horizontal := Vector2(offset.x, offset.z).length()
			if horizontal < WALK_MARGIN and absf(offset.y) < 0.30 and absf(runner.velocity.y) < 0.35:
				arrived = true
				break
			camera_arm.rotation.y = atan2(-offset.x, -offset.z)
			var strength := clampf(0.24 + horizontal * 1.9, 0.415, 0.68)
			Input.action_press(MOVE_FORWARD, strength if horizontal > WALK_MARGIN else 0.0)
			await physics_frame
		if not arrived:
			Input.action_release(MOVE_FORWARD)
			return "Could not reach %s from %s." % [point, runner.global_position]
	Input.action_release(MOVE_FORWARD)
	return ""
