extends RefCounted

const Doors := preload("res://game/campus/campus-doors.gd")
const Door := preload("res://game/campus/swing-door.gd")
const INTERIOR := preload("res://art/campus/interior-access.json")
const CONNECTION_RANGE := 16.0

# Open walks seed destinations between the authored indoor connections.
const OUTDOOR_WALKS := {
	"Gate avenue west": Vector4(-1.7, -4, -1.7, -30),
	"Gate avenue east": Vector4(1.7, -5, 1.7, -28),
	"Forecourt": Vector4(-8, -39, 8, -39),
	"East walk": Vector4(11, -40, 37, -40),
	"Training path": Vector4(39, -50, 39, -121),
	"Residence avenue": Vector4(1.5, 18, 1.5, 87),
	"Faculty walk": Vector4(-99, -31, -83, -31),
	"Grandstand approach": Vector4(-48, -98, -22, -98),
	"Dining hall walk": Vector4(51, -22, 67, -22),
}
const INTERIOR_WALKS := {
	"Academy reception": [Vector3(0.8, 0.715, -56), Vector3(0.8, 0.715, -65.8)],
	"Library reading aisle": [Vector3(-2, 0.743, -71), Vector3(-2, 0.743, -77)],
	"Grandstand concourse": [Vector3(-26, 0.64, -115.05), Vector3(-1, 0.64, -115.05)],
}


class Place:
	var position: Vector3
	var exits: Array[int] = []
	var sheltered := false


class Passage:
	var ends: Vector2i
	var points: PackedVector3Array
	var door: Door

	func other(place: int) -> int:
		return ends.y if place == ends.x else ends.x


var places: Array[Place] = []
var passages: Array[Passage] = []
var outdoor_starts: Array[int] = []


func build(doors: Doors, space: PhysicsDirectSpaceState3D) -> void:
	for route: Vector4 in OUTDOOR_WALKS.values():
		var first := Vector3(route.x, 0.008, route.y)
		var last := Vector3(route.z, 0.008, route.w)
		var segments := ceili(first.distance_to(last) / 8.0)
		outdoor_starts.append(_place_at(first))
		for index in segments:
			_add_passage(PackedVector3Array([
				first.lerp(last, float(index) / segments),
				first.lerp(last, float(index + 1) / segments)]))

	for points: Array in INTERIOR_WALKS.values():
		_add_passage(PackedVector3Array(points))

	for link: Dictionary in INTERIOR.data.links:
		var points := PackedVector3Array()
		for point: Array in link.points:
			points.append(_world(point))
		_add_passage(_turns(points), doors.passage_door(points[0]))

	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.30
	capsule.height = 1.64
	var clearance := PhysicsShapeQueryParameters3D.new()
	clearance.shape = capsule
	clearance.collision_mask = 1
	for room: Dictionary in INTERIOR.data.rooms:
		if room.has("door"):
			continue
		var point := _world(room.point)
		clearance.transform.origin = point + Vector3.UP * 0.93
		if space.intersect_shape(clearance, 1).is_empty():
			_place_at(point)

	# Link rooms, landings and outdoor paths across clear, supported floors.
	# Authored passages supply the height changes that need actual stair walking.
	for index in places.size():
		var from := places[index]
		var nearby: Array[Vector2] = []
		for other in places.size():
			var offset := places[other].position - from.position
			if other != index and absf(offset.y) <= 0.16 and offset.length_squared() <= CONNECTION_RANGE * CONNECTION_RANGE:
				nearby.append(Vector2(offset.length_squared(), other))
		nearby.sort()
		for neighbor in nearby.slice(0, 9):
			var other := int(neighbor.y)
			if from.exits.any(func(edge: int) -> bool: return passages[edge].other(index) == other):
				continue
			var to := places[other]
			if _can_walk(space, clearance, from.position, to.position):
				_record_passage(index, other, PackedVector3Array([from.position, to.position]), null)


func _world(point: Array) -> Vector3:
	return Vector3(point[0], point[2], -point[1])


func _place_at(position: Vector3) -> int:
	for index in places.size():
		if places[index].position.distance_squared_to(position) < 0.04:
			return index
	var place := Place.new()
	place.position = position
	place.sheltered = position.y > 0.25
	places.append(place)
	return places.size() - 1


func _add_passage(points: PackedVector3Array, door: Door = null) -> void:
	var from := _place_at(points[0])
	var to := _place_at(points[-1])
	if from == to:
		return
	points[0] = places[from].position
	points[-1] = places[to].position
	_record_passage(from, to, points, door)


func _record_passage(from: int, to: int, points: PackedVector3Array, door: Door) -> void:
	var passage := Passage.new()
	passage.ends = Vector2i(from, to)
	passage.points = points
	passage.door = door
	places[from].exits.append(passages.size())
	places[to].exits.append(passages.size())
	passages.append(passage)


func _can_walk(space: PhysicsDirectSpaceState3D, clearance: PhysicsShapeQueryParameters3D,
		from: Vector3, to: Vector3) -> bool:
	var obstruction := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.8, to + Vector3.UP * 0.8, 1)
	if not space.intersect_ray(obstruction).is_empty():
		return false
	clearance.transform.origin = from + Vector3.UP * 0.93
	clearance.motion = to - from
	if space.cast_motion(clearance)[0] < 1.0:
		return false
	var samples := ceili(from.distance_to(to) / 0.48)
	for index in range(samples + 1):
		var point := from.lerp(to, float(index) / samples)
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.20, point - Vector3.UP * 0.20, 1)
		var floor_hit := space.intersect_ray(query)
		if floor_hit.is_empty() or floor_hit.normal.y < 0.71:
			return false
	return true


func _turns(points: PackedVector3Array) -> PackedVector3Array:
	var turns := PackedVector3Array([points[0]])
	for index in range(1, points.size() - 1):
		var arrival := (points[index] - points[index - 1]).slide(Vector3.UP).normalized()
		var departure := (points[index + 1] - points[index]).slide(Vector3.UP).normalized()
		if arrival.dot(departure) < 0.92:
			turns.append(points[index])
	turns.append(points[-1])
	return turns
