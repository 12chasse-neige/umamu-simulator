extends StaticBody3D

# Use the architectural and ground surfaces from the campus export. Water,
# leaves, lettering and other fine details are left out of the physics mesh.
const TREE_BARK := &"Bark_NormalTree"
const TRUNK_COLLISION_HEIGHT := 3.0

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
]

@export var campus: Node3D


func _ready() -> void:
	var faces_by_mesh: Dictionary[Mesh, PackedVector3Array] = {}
	var faces_by_cell: Dictionary[Vector2i, PackedVector3Array] = {}
	var world_to_local := global_transform.affine_inverse()

	for object in campus.find_children("*", "MeshInstance3D", true, false):
		var instance := object as MeshInstance3D
		var mesh := instance.mesh
		var label := str(instance.name)
		if mesh == null or not instance.is_visible_in_tree() or label.ends_with(" · mesh") or label.ends_with(" open bedroom doors"):
			continue
		if not faces_by_mesh.has(mesh):
			faces_by_mesh[mesh] = _solid_faces(mesh)
		var faces := faces_by_mesh[mesh]
		if faces.is_empty():
			continue

		# Separate campus districts so local queries do not overlap the entire map.
		var mesh_to_local := world_to_local * instance.global_transform
		var center := mesh_to_local * instance.get_aabb().get_center()
		var cell := Vector2i(floori(center.x / 32.0), floori(center.z / 32.0))
		if not faces_by_cell.has(cell):
			faces_by_cell[cell] = PackedVector3Array()
		var vertices := faces_by_cell[cell]
		for vertex in faces:
			vertices.append(mesh_to_local * vertex)

	for faces in faces_by_cell.values():
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		add_child(collider)


func _solid_faces(mesh: Mesh) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface)
		if material == null:
			continue
		var trunk := material.resource_name == TREE_BARK
		if not trunk and material.resource_name not in SOLID_MATERIALS:
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
