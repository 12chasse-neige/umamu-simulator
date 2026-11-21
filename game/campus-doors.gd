extends Node3D

const Door := preload("res://game/swing-door.gd")
const PLAN := preload("res://art/campus/interior-access.json")
const REACH := 2.1
const BEDROOM_DOORS := " open bedroom doors"
const FRAME_COLOR := Color("#604032")
const PANEL_COLOR := Color("#825944")

@export var campus: Node3D
@export var player: CharacterBody3D
@export var prompt: Label

var doors: Array[Door] = []
var models: Dictionary[Vector2, Mesh] = {}
var sight := PhysicsRayQueryParameters3D.new()
var oak: StandardMaterial3D


func _ready() -> void:
	var plan: Dictionary = PLAN.data
	var casing := campus.find_child("Pavilion · door cases and stone reveals", true, false) as MeshInstance3D
	if casing != null:
		for surface in casing.mesh.get_surface_count():
			var material := casing.mesh.surface_get_material(surface)
			if material != null and material.resource_name == &"Oak · armrest and door varnish":
				oak = material as StandardMaterial3D
				break
	sight.collision_mask = 1
	for route in plan.links:
		if route.name == "Amphitheatre stage":
			continue
		if route.kind == "entry" or route.name == "Hall to library":
			_build_entrance(route)

	for sheet in campus.find_children("*" + BEDROOM_DOORS, "MeshInstance3D", true, false):
		_split_bedroom_leaves(sheet, plan.rooms)


func _physics_process(_delta: float) -> void:
	var nearby := reachable_door()
	prompt.visible = nearby != null
	if nearby != null:
		prompt.text = "E   Close door" if nearby.wants_open else "E   Open door"
		if Input.is_action_just_pressed(&"interact_door"):
			nearby.toggle()


func reachable_door() -> Door:
	var eye := player.global_position + Vector3.UP * 1.05
	var nearest_distance := REACH * REACH
	var nearest: Door
	for door in doors:
		var handle := door.global_position + Vector3.UP * minf(door.height * 0.56, 1.17)
		var distance := eye.distance_squared_to(handle)
		if distance >= nearest_distance or absf(handle.y - eye.y) > 1.2:
			continue
		sight.from = eye
		sight.to = handle
		sight.exclude = door.body_ids
		if get_world_3d().direct_space_state.intersect_ray(sight).is_empty():
			nearest_distance = distance
			nearest = door
	return nearest


func _world(point: Array) -> Vector3:
	return Vector3(point[0], point[2], -point[1])


func _build_entrance(route: Dictionary) -> void:
	var sill := _world(route.points[-2])
	var width := 1.40
	var entrance_height := 2.08
	# The academy portal and library case predate the shared street entrance.
	if route.name == "Academy entrance":
		sill = _world(route.points[6])
		width = 1.24
		entrance_height = 2.13
	elif route.name == "Hall to library":
		sill = _world(route.points[2])
		width = 1.52
		entrance_height = 2.15

	var inside := _world(route.points[-1]) - _world(route.points[0])
	inside.y = 0.0
	var door := Door.new()
	door.name = route.name
	add_child(door, true)
	door.global_position = sill + Vector3.UP * 0.015
	door.look_at(door.global_position + inside, Vector3.UP)
	doors.append(door)

	var leaf_size := Vector3(width * 0.5 - 0.009, entrance_height, 0.052)
	var model := _entrance_model(leaf_size)
	for hand in [-1.0, 1.0]:
		var side := -float(hand)
		var hinge := Vector3(float(hand) * width * 0.5, 0.0, 0.0)
		var leaf := door.add_leaf(hinge, side, leaf_size, side)
		var panel := MeshInstance3D.new()
		panel.mesh = model
		panel.position = Vector3(side * leaf_size.x * 0.5, 0.0, 0.0)
		panel.rotation.y = PI if side > 0.0 else 0.0
		leaf.add_child(panel)


func _entrance_model(size: Vector3) -> Mesh:
	var dimensions := Vector2(size.x, size.y)
	if models.has(dimensions):
		return models[dimensions]
	var model := ArrayMesh.new()
	var wood := _wood_finish(FRAME_COLOR, Color(0.82, 0.73, 0.65))
	var inset := _wood_finish(PANEL_COLOR, Color(0.98, 0.91, 0.83))
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color("#b89852")
	brass.metallic = 0.63
	brass.roughness = 0.32

	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(builder, size, Vector3.UP * size.y * 0.5)
	builder.set_material(wood)
	builder.commit(model)
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in [-1.0, 1.0]:
		var face_z := float(face) * (size.z * 0.5 + 0.003)
		_box(builder, Vector3(size.x - 0.17, size.y * 0.47, 0.01), Vector3(0, size.y * 0.68, face_z))
		_box(builder, Vector3(size.x - 0.17, size.y * 0.27, 0.01), Vector3(0, size.y * 0.22, face_z))
	builder.set_material(inset)
	builder.commit(model)
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(builder, Vector3(0.042, 0.18, 0.097), Vector3(-size.x * 0.5 + 0.08, 1.03, 0))
	builder.set_material(brass)
	builder.commit(model)
	models[dimensions] = model
	return model


func _wood_finish(fallback: Color, tint: Color) -> StandardMaterial3D:
	if oak != null:
		var tinted_oak := oak.duplicate() as StandardMaterial3D
		tinted_oak.albedo_color = tint
		return tinted_oak
	var finish := StandardMaterial3D.new()
	finish.albedo_color = fallback
	finish.roughness = 0.72
	return finish


func _box(builder: SurfaceTool, size: Vector3, center: Vector3) -> void:
	var box := BoxMesh.new()
	box.size = size
	builder.append_from(box, 0, Transform3D(Basis.IDENTITY, center))


func _split_bedroom_leaves(sheet: MeshInstance3D, rooms: Array) -> void:
	var residence := str(sheet.name).trim_suffix(BEDROOM_DOORS)
	var bedrooms: Array[Dictionary] = []
	var centers: Array[Vector3] = []
	for room in rooms:
		if str(room.name).begins_with(residence + " ") and room.has("door"):
			bedrooms.append(room)
			centers.append(_world(room.door.hinge) + Vector3.UP)

	if bedrooms.is_empty():
		return

	# The Blender export groups all the open leaves in one mesh. The hinge
	# locations identify the bedroom that owns each surface triangle.
	var meshes: Array[ArrayMesh] = []
	for index in bedrooms.size():
		meshes.append(ArrayMesh.new())
	for surface in sheet.mesh.get_surface_count():
		var arrays := sheet.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var material := sheet.mesh.surface_get_material(surface)
		var buckets: Array[PackedInt32Array] = []
		for index in centers.size():
			buckets.append(PackedInt32Array())
		for triangle in range(0, indices.size(), 3):
			var middle := (vertices[indices[triangle]] + vertices[indices[triangle + 1]] + vertices[indices[triangle + 2]]) / 3.0
			var world_center := sheet.to_global(middle)
			var closest := 0
			for index in range(1, centers.size()):
				if world_center.distance_squared_to(centers[index]) < world_center.distance_squared_to(centers[closest]):
					closest = index
			for corner in 3:
				buckets[closest].append(indices[triangle + corner])
		for index in centers.size():
			if buckets[index].is_empty():
				continue
			var leaf_arrays := arrays.duplicate()
			leaf_arrays[Mesh.ARRAY_INDEX] = buckets[index]
			var model := meshes[index]
			model.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, leaf_arrays)
			model.surface_set_material(model.get_surface_count() - 1, material)

	sheet.hide()
	for index in meshes.size():
		var model := meshes[index]
		if model.get_surface_count() > 0:
			_add_bedroom_door(sheet, model, bedrooms[index])


func _add_bedroom_door(sheet: MeshInstance3D, mesh: ArrayMesh, bedroom: Dictionary) -> void:
	var spec: Dictionary = bedroom.door
	var pivot := _world(spec.hinge)
	var size := Vector3(spec.width, spec.height, spec.depth)
	var inward: float = spec.inward

	var door := Door.new()
	door.name = bedroom.name
	add_child(door, true)
	door.global_position = pivot + Vector3.BACK * size.x * 0.5
	door.rotation.y = -PI * 0.5
	doors.append(door)

	var leaf := door.add_leaf(door.to_local(pivot), 1.0, size, inward)
	var panel := MeshInstance3D.new()
	panel.mesh = mesh
	leaf.add_child(panel)
	var closed_basis := Basis(Vector3.UP, -inward * PI * 0.5)
	var closed := Transform3D(closed_basis, pivot - closed_basis * pivot)
	panel.global_transform = closed * sheet.global_transform
	var open_leaf_box := AABB(
		pivot + Vector3(minf(0.0, inward * size.x), 0.0, 0.0),
		Vector3(size.x, size.y, size.z)
	)
	panel.custom_aabb = AABB(sheet.to_local(open_leaf_box.position), open_leaf_box.size).grow(0.09)
