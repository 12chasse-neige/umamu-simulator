extends SceneTree

const CAMPUS := preload("res://game/campus/campus-walk.tscn")

const FOUNTAIN_CONTACTS := {
	"rim": [Vector3(3.40, 0.525, -47), Vector3(2.64, 0.525, -47), Vector3(2.9675, 0.525, -47)],
	"inner lining": [Vector3(2.60, 0.46, -47), Vector3(3.40, 0.46, -47), Vector3(2.6678, 0.46, -47)],
	"submerged floor": [Vector3(2.35, 0.80, -47), Vector3(2.35, 0.10, -47), Vector3(2.35, 0.249, -47)],
	"pedestal": [Vector3(1.50, 1.22, -47), Vector3(0.20, 1.22, -47), Vector3(0.4949, 1.22, -47)],
	"upper bowl": [Vector3(1.56, 1.77, -47), Vector3(0.88, 1.77, -47), Vector3(1.175, 1.77, -47)],
	"bronze plinth": [Vector3(1.41, 2.095, -47), Vector3(0.65, 2.095, -47), Vector3(0.9899, 2.095, -47)],
	"statue": [Vector3(0.05, 2.71, -45.80), Vector3(0.05, 2.71, -47.50), Vector3(0.05, 2.71, -46.9856)],
}

const STUMP_CENTER := Vector3(-25.90, 0.0, -22.98)

var runner: CharacterBody3D
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := CAMPUS.instantiate()
	root.add_child(scene)
	runner = scene.get_node("SpecialWeek")
	await physics_frame

	for label: String in FOUNTAIN_CONTACTS:
		var probe: Array = FOUNTAIN_CONTACTS[label]
		_check_contact(label, probe[0], probe[1], probe[2], 0.015)
	_check(_ray(Vector3(0.85, 1.92, -47), Vector3(0.85, 1.815, -47)).is_empty(),
		"The water surface in the upper bowl blocked the ray.")
	_check_contact("solid stump rim", Vector3(-25.05, 2.50, -22.86),
		Vector3(-25.05, 0.0, -22.86), Vector3(-25.05, 1.5435, -22.86), 0.025)
	_check_contact("deep stump opening", STUMP_CENTER + Vector3.UP * 2.50,
		STUMP_CENTER, STUMP_CENTER + Vector3.UP * 0.408, 0.045)
	_check_contact("inside of the stump wall", STUMP_CENTER + Vector3.UP * 0.91,
		Vector3(-25.0, 0.91, -22.98), Vector3(-25.2261, 0.91, -22.98), 0.035)

	var movement := runner.global_transform
	movement.origin = Vector3(3.50, 0.015, -47.0)
	_check(runner.test_move(movement, Vector3.LEFT * 1.2), "The runner passed straight through the outside rim.")
	movement.origin = Vector3(1.67, 0.253, -47.0)
	_check(runner.test_move(movement, Vector3.LEFT * 0.72), "The runner passed straight through the bronze bowl.")

	runner._recover_at(STUMP_CENTER + Vector3.UP * 1.80)
	await _ticks(60)
	_check(runner.is_on_floor() and runner.global_position.y > 0.34 and runner.global_position.y < 0.58,
		"The runner did not settle on the recessed floor of the stump.")

	# Jump vertically through the opening before steering over the rim.
	Input.action_press(&"jump")
	await _ticks(2)
	Input.action_release(&"jump")
	await _ticks(14)
	Input.action_press(&"jump")
	await _ticks(2)
	Input.action_release(&"jump")
	runner.get_node("CameraArm").rotation.y = 0.0
	Input.action_press(&"move_forward")
	await _ticks(65)
	Input.action_release(&"move_forward")
	_check(runner.global_position.z < STUMP_CENTER.z - 0.90, "The runner could not jump out of the hollow.")

	print("Landmark checks %s." % ("passed" if failures == 0 else "failed (%d)" % failures))
	quit(0 if failures == 0 else 1)


func _check_contact(label: String, from: Vector3, to: Vector3, expected: Vector3, tolerance: float) -> void:
	var hit := _ray(from, to)
	_check(not hit.is_empty() and hit.position.distance_to(expected) < tolerance,
		"%s contact expected at %s, got %s." % [label, expected, hit.get("position", "no hit")])


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1, [runner.get_rid()])
	return runner.get_world_3d().direct_space_state.intersect_ray(query)


func _check(condition: bool, message: String) -> void:
	if not condition:
		print(message)
		failures += 1


func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame
