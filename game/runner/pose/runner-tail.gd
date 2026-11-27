extends RefCounted

const SWAY_DEGREES: Array[float] = [4.5, 11.0, 20.0]
const SEGMENT_WEIGHT: Array[float] = [0.60, 0.32, 0.24]
const PHASE_LAG: Array[float] = [0.20, 0.61, 1.02]
const TAIL_JOINTS := [&"Tail_Ctrl", &"Sp_Hi_Tail0_B_02", &"Sp_Hi_Tail0_B_04"]

var _rig: Skeleton3D
var _joints := PackedInt32Array()
var _rest: Array[Quaternion] = []
var _axes: Array[Quaternion] = []
var _sway := 0.0
var _lift := 0.0
var _turn := 0.0


func bind(model: Node3D, body: Skeleton3D, facing: Node3D, use_trial_mesh: bool) -> void:
	if use_trial_mesh:
		_rig = _split_trial_tail(model, body)
		if _rig == null:
			return
		# The separate tail rig uses the mesh's model-space axes.
		for index in range(1, _rig.get_bone_count()):
			_joints.append(index)
			_rest.append(Quaternion.IDENTITY)
			_axes.append(Quaternion.IDENTITY)
		return
	_rig = body
	var model_to_rig := facing.global_transform.affine_inverse() * body.global_transform
	for name: StringName in TAIL_JOINTS:
		var index := body.find_bone(name)
		if index < 0:
			continue
		_joints.append(index)
		_rest.append(body.get_bone_rest(index).basis.get_rotation_quaternion())
		var axes := model_to_rig.basis * body.get_bone_global_rest(index).basis
		_axes.append(axes.orthonormalized().get_rotation_quaternion())


func reset() -> void:
	_sway = 0.0
	_lift = 0.0
	_turn = 0.0
	for segment in _joints.size():
		_rig.set_bone_pose_rotation(_joints[segment], _rest[segment])


func step(phase: float, gait: int, effort: float, turn: float, lift: float, delta: float) -> void:
	if _joints.is_empty():
		return
	var blend := 1.0 - exp(-8.0 * delta)
	_sway = lerpf(_sway, SWAY_DEGREES[gait] * effort, blend)
	_lift = lerpf(_lift, lift, blend)
	_turn = lerpf(_turn, turn * 5.0, blend)
	for segment in _joints.size():
		var beat := phase * TAU - PHASE_LAG[segment]
		var swing := _sway * sin(beat)
		var angles := Vector3(_lift + _sway * 0.12 * cos(2.0 * beat), swing * 0.12, swing - _turn)
		var offset := Quaternion.from_euler(angles * (SEGMENT_WEIGHT[segment] * PI / 180.0))
		var axes := _axes[segment]
		_rig.set_bone_pose_rotation(_joints[segment], _rest[segment] * axes.inverse() * offset * axes)


func _split_trial_tail(model: Node3D, body: Skeleton3D) -> Skeleton3D:
	var hip := body.find_bone(&"Hip")
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh as ArrayMesh
		var skin := mesh_instance.skin
		if mesh == null or skin == null:
			continue
		for surface in mesh.get_surface_count():
			var material := mesh_instance.get_active_material(surface)
			if material == null or not material.resource_name.begins_with("mtl_tail"):
				continue
			for slot in skin.get_bind_count():
				if skin.get_bind_name(slot) == &"Hip" or skin.get_bind_bone(slot) == hip:
					return _attach_tail(body, mesh_instance, mesh, surface, material, skin.get_bind_pose(slot))
	return null


func _attach_tail(body: Skeleton3D, mesh_instance: MeshInstance3D, mesh: ArrayMesh, surface: int,
		material: Material, hip_bind: Transform3D) -> Skeleton3D:
	var arrays := mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var top := -INF
	var bottom := INF
	for vertex in vertices:
		top = maxf(top, vertex.y)
		bottom = minf(bottom, vertex.y)
	var span := top - bottom
	if span <= 0.02:
		return null

	# Keep the first ring attached to the hip, with progressively looser weights
	# along the tail so each successive joint can follow the previous one.
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for vertex in vertices:
		var distance := (top - vertex.y) / span
		var base := smoothstep(0.025, 0.20, distance)
		var middle := smoothstep(0.25, 0.57, distance)
		var tip := smoothstep(0.59, 0.88, distance)
		bones.append_array(PackedInt32Array([0, 1, 2, 3]))
		weights.append_array(PackedFloat32Array([1.0 - base, base - middle, middle - tip, tip]))
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	var tail_mesh := ArrayMesh.new()
	tail_mesh.add_surface_from_arrays(mesh.surface_get_primitive_type(surface), arrays, [], {},
		mesh.surface_get_format(surface))
	if tail_mesh.get_surface_count() != 1:
		return null
	tail_mesh.surface_set_material(0, material)

	var tail := Skeleton3D.new()
	tail.name = "TailSkeleton"
	var tail_skin := Skin.new()
	var previous := Vector3.ZERO
	for index in 4:
		var pivot := Vector3.ZERO
		if index > 0:
			pivot = _tail_center(vertices, top - span * [0.035, 0.32, 0.62][index - 1], span * 0.10)
		tail.add_bone("Anchor" if index == 0 else "Tail%d" % index)
		tail.set_bone_parent(index, index - 1)
		tail.set_bone_rest(index, Transform3D(Basis.IDENTITY, pivot - previous))
		tail_skin.add_bind(index, Transform3D(Basis.IDENTITY, -pivot))
		previous = pivot
	tail.reset_bone_poses()

	var attachment := BoneAttachment3D.new()
	attachment.name = "TailAttachment"
	attachment.bone_name = &"Hip"
	body.add_child(attachment)
	attachment.add_child(tail)
	tail.transform = hip_bind
	var instance := MeshInstance3D.new()
	instance.name = "TailMesh"
	instance.mesh = tail_mesh
	instance.skin = tail_skin
	instance.skeleton = NodePath("..")
	instance.extra_cull_margin = 0.35
	tail.add_child(instance)

	var body_mesh := mesh.duplicate() as ArrayMesh
	body_mesh.surface_remove(surface)
	# The original shadow mesh includes the retired tail surface.
	body_mesh.shadow_mesh = null
	mesh_instance.mesh = body_mesh
	return tail


func _tail_center(vertices: PackedVector3Array, height: float, radius: float) -> Vector3:
	var center := Vector3.ZERO
	var count := 0
	for vertex in vertices:
		if absf(vertex.y - height) <= radius:
			center += vertex
			count += 1
	center /= maxi(1, count)
	center.y = height
	return center
