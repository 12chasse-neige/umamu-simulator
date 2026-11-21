extends SceneTree

const CAMPUS := preload("res://game/campus-walk.tscn")
const FORWARD := &"move_forward"

# These placements exercise all five tree meshes and the separate garden stump.
const TARGETS := {
	"Avenue canopy": Vector2(-7.8, -6.2),
	"Hall promenade · tree.003": Vector2(47.076, -37.709),
	"Hall promenade · tree.006": Vector2(46.77, -49.004),
	"North shelter woodland · tree": Vector2(6.007, -293.973),
	"North shelter woodland · tree.003": Vector2(39.084, -285.151),
	"Old stump": Vector2(-26.0, -23.0),
}

var runner: CharacterBody3D
var arm: SpringArm3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := CAMPUS.instantiate()
	root.add_child(scene)
	runner = scene.get_node("SpecialWeek")
	arm = runner.get_node("CameraArm")
	await physics_frame

	var passed := 0
	for label: String in TARGETS:
		if await _blocks_direct_walk(TARGETS[label]):
			passed += 1
		else:
			print("No confirmed trunk contact at %s." % label)

	print("Tree collision checks passed %d of %d." % [passed, TARGETS.size()])
	quit(0 if passed == TARGETS.size() else 1)


func _blocks_direct_walk(target: Vector2) -> bool:
	for side: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		var from := target + side * 2.5
		var start_floor := _ground_at(from)
		if start_floor.is_empty():
			continue

		var start: Vector3 = start_floor.position
		var towards := Vector3(-side.x, 0.0, -side.y)
		var query := PhysicsRayQueryParameters3D.create(
			start + Vector3.UP * 0.80,
			Vector3(target.x, start.y + 0.80, target.y),
			1
		)
		var bark := runner.get_world_3d().direct_space_state.intersect_ray(query)
		if bark.is_empty() or (bark.position - query.from).length() < 0.7:
			continue

		runner._recover_at(start + Vector3.UP * 0.055)
		for tick in 13:
			await physics_frame
		if not runner.is_on_floor() or runner.global_position.distance_to(start) > 0.19:
			continue

		arm.rotation.y = atan2(-towards.x, -towards.z)
		Input.action_press(FORWARD, 0.76)
		var touched := false
		for tick in 115:
			await physics_frame
			for index in runner.get_slide_collision_count():
				var collision := runner.get_slide_collision(index)
				var point := collision.get_position()
				var radial := Vector2(point.x, point.z).distance_to(target)
				if radial < 1.8 and collision.get_normal().dot(towards) < -0.48:
					touched = true
					break
			if touched:
				break
		Input.action_release(FORWARD)
		if touched:
			return true

	return false


func _ground_at(point: Vector2) -> Dictionary:
	var start := Vector3(point.x, 32.0, point.y)
	var end := Vector3(point.x, -4.0, point.y)
	var space := runner.get_world_3d().direct_space_state
	# A low branch can cover the first approach. Use a nearby
	# point to find the walking surface below it.
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(start, end, 1))
	if not hit.is_empty() and hit.normal.y > 0.70:
		return hit
	start.x += 1.9
	end.x += 1.9
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(start, end, 1))
