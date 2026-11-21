extends Node3D

const OPEN_ANGLE := deg_to_rad(88.0)
const SWING_RATE := 3.4

var leaves: Array[AnimatableBody3D] = []
var boxes: Array[CollisionShape3D] = []
var turns: Array[float] = []
var body_ids: Array[RID] = []
var wants_open := false
var opening := 0.0
var height := 2.08
var occupant := PhysicsShapeQueryParameters3D.new()


func add_leaf(hinge: Vector3, side: float, size: Vector3, swing: float) -> AnimatableBody3D:
	var leaf := AnimatableBody3D.new()
	leaf.sync_to_physics = false
	leaf.collision_mask = 0
	leaf.position = hinge
	add_child(leaf)

	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = Vector3(side * size.x * 0.5, size.y * 0.5, 0.0)
	leaf.add_child(collider)

	leaves.append(leaf)
	boxes.append(collider)
	turns.append(swing)
	body_ids.append(leaf.get_rid())
	height = size.y
	return leaf


func _ready() -> void:
	occupant.collision_mask = 2


func toggle() -> void:
	wants_open = not wants_open


func _physics_process(delta: float) -> void:
	var desired := 1.0 if wants_open else 0.0
	if is_equal_approx(opening, desired):
		return

	var next := move_toward(opening, desired, delta * SWING_RATE)
	var eased := smoothstep(0.0, 1.0, next)
	var space := get_world_3d().direct_space_state
	for index in leaves.size():
		var leaf := leaves[index]
		var proposed := Transform3D(Basis(Vector3.UP, turns[index] * OPEN_ANGLE * eased), leaf.position)
		occupant.shape = boxes[index].shape
		occupant.transform = global_transform * proposed * boxes[index].transform
		if not space.intersect_shape(occupant, 1).is_empty():
			# Reopen if someone steps into the closing sweep.
			if not wants_open:
				wants_open = true
			return

	opening = next
	for index in leaves.size():
		leaves[index].rotation.y = turns[index] * OPEN_ANGLE * eased
