extends Node3D

const Course := preload("res://game/race/race-course.gd")

# Use the architectural and ground surfaces from the campus export. Water,
# leaves, lettering and other fine details are left out of the physics mesh.
const TREE_BARK := &"Bark_NormalTree"
const TRUNK_COLLISION_HEIGHT := 3.0
const REPLACED_TRACK_MESHES := [
	&"Primary dirt circuit", &"Inner sand circuit", &"Inner dirt circuit",
	&"Start stripe", &"Start alignment tabs beside the near rail",
]

const FOUNTAIN_MESHES := [
	&"Basin foundation", &"Basin wall · open stone lining",
	&"Fountain · limestone coping and tazza", &"Fountain · fluted stone and cast bowl ribs",
	&"Fountain · submerged tiled floor and pier footing",
	&"Three Goddesses · elliptical bronze plinth",
	&"Three Goddesses · Wisdom", &"Three Goddesses · Resolve", &"Three Goddesses · Grace",
]
const FOUNTAIN_SOLID_MATERIALS := [
	&"Submerged basin stone", &"Patinated bronze", &"Old brass",
	&"Cast bronze · guardians", &"Cast brass · attributes", &"Cast bronze · carved hair",
	&"Cast bronze · pouring vessels", &"Cast bronze · polished vessel rims",
]

const SOLID_MATERIALS := [
	&"Base", &"Turf", &"Lawn", &"Earth", &"Road", &"Paving", &"Packed clay",
	&"Sand course", &"Court green", &"Deep green", &"Brick", &"Lime mortar · recessed joints",
	&"Ivory", &"Limestone", &"Pale sandstone", &"Ochre", &"Warm panel", &"Chalk",
	&"Terracotta · individual fired faces",
	&"Roof deck", &"Slate", &"Dressed blue slate", &"Copper patina", &"Terrace red",
	&"Dorm blue", &"Dorm rose", &"Garden cream", &"Sports red", &"Seat blue",
	&"Glass", &"Glass · graduated glazing", &"Frame", &"Rail", &"Post", &"Iron enamel",
	&"Oak · armrest and door varnish", &"Oak · boarded interior floor",
	&"Oak · end grain", &"Heartwood", &"Interior · graphite rubber",
	&"Classroom · warm plaster", &"Classroom · desaturated teal",
	&"Marble · honed cream veining", &"Marble · set gallery slabs",
	&"Bark · weathered ridge", &"Bark · cool umber", &"Bark · furrow",
	&"Summer growth", &"Cut timber", &"Heartwood checks",
	&"Stump · weathered inner wood", &"Stump · decayed heartwood", &"Stump · hollow floor",
]

@export var campus: Node3D


func _ready() -> void:
	var faces_by_mesh: Dictionary[Mesh, PackedVector3Array] = {}
	var faces_by_cell: Dictionary[Vector2i, PackedVector3Array] = {}
	var trunks_by_cell: Dictionary[Vector2i, PackedVector3Array] = {}
	var fountain_by_cell: Dictionary[Vector2i, PackedVector3Array] = {}
	var world_to_local := global_transform.affine_inverse()

	for object in campus.find_children("*", "MeshInstance3D", true, false):
		var instance := object as MeshInstance3D
		var mesh := instance.mesh
		var label := str(instance.name)
		if mesh == null or not instance.is_visible_in_tree() or label.ends_with(" · mesh") or label.ends_with(" open bedroom doors"):
			continue
		if instance.name in REPLACED_TRACK_MESHES or _is_authored_oval_rail(instance):
			instance.hide()
			continue
		var fountain := instance.name in FOUNTAIN_MESHES
		var faces: PackedVector3Array
		if fountain:
			faces = _solid_faces(mesh, true)
		else:
			if not faces_by_mesh.has(mesh):
				faces_by_mesh[mesh] = _solid_faces(mesh)
			faces = faces_by_mesh[mesh]
		if faces.is_empty():
			continue

		# Separate campus districts so local queries do not overlap the entire map.
		var mesh_to_local := world_to_local * instance.global_transform
		var center := mesh_to_local * instance.get_aabb().get_center()
		var cell := Vector2i(floori(center.x / 32.0), floori(center.z / 32.0))
		var cells := faces_by_cell
		if fountain:
			cells = fountain_by_cell
		elif _has_bark(mesh):
			cells = trunks_by_cell
		if not cells.has(cell):
			cells[cell] = PackedVector3Array()
		var vertices: PackedVector3Array = cells[cell]
		for vertex in faces:
			vertices.append(mesh_to_local * vertex)

	_add_body(&"Surfaces", faces_by_cell)
	_add_body(&"Trunks", trunks_by_cell, true)
	# The bowl and casting include thin shells. Both sides are solid, including
	# when the runner is already in the basin.
	_add_body(&"Fountain", fountain_by_cell, false, true)


func _is_authored_oval_rail(instance: MeshInstance3D) -> bool:
	# The export places each course beam and upright below its own anchor.
	var anchor := instance.get_parent() as Node3D
	if anchor == null or not (anchor.name.begins_with("Rail span") or anchor.name.begins_with("Course upright")):
		return false
	var offset := Course.project(anchor.global_position).y
	return absf(absf(offset) - Course.HALF_WIDTH) < 0.20


func _add_body(label: StringName, cells: Dictionary[Vector2i, PackedVector3Array],
		climbable := false, two_sided := false) -> void:
	if cells.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = label
	body.collision_mask = 0
	if climbable:
		body.add_to_group(&"climbable_trunks")
	for faces in cells.values():
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = two_sided
		shape.set_faces(faces)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
	add_child(body)


func _has_bark(mesh: Mesh) -> bool:
	for index in mesh.get_surface_count():
		var material := mesh.surface_get_material(index)
		if material != null and material.resource_name == TREE_BARK:
			return true
	return false


func _solid_faces(mesh: Mesh, fountain := false) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface)
		if material == null:
			continue
		var trunk := material.resource_name == TREE_BARK
		var solid := material.resource_name in SOLID_MATERIALS
		solid = solid or (fountain and material.resource_name in FOUNTAIN_SOLID_MATERIALS)
		if not trunk and not solid:
			continue
		var arrays := mesh.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if trunk:
			faces = _append_trunk_faces(faces, points, indices)
		elif indices.is_empty():
			faces.append_array(points)
		else:
			for index in indices:
				faces.append(points[index])
	return faces


func _append_trunk_faces(faces: PackedVector3Array, points: PackedVector3Array,
		indices: PackedInt32Array) -> PackedVector3Array:
	# Use the original lower bark triangles so the collider follows the
	# flare and lean of each shared tree model.
	var count := points.size() if indices.is_empty() else indices.size()
	for i in range(0, count, 3):
		var a := points[i if indices.is_empty() else indices[i]]
		var b := points[i + 1 if indices.is_empty() else indices[i + 1]]
		var c := points[i + 2 if indices.is_empty() else indices[i + 2]]
		if minf(a.y, minf(b.y, c.y)) <= TRUNK_COLLISION_HEIGHT:
			faces.append(a)
			faces.append(b)
			faces.append(c)
	return faces
