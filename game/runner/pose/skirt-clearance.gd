extends RefCounted

# The ten strips share skin weights at their edges. Drive the original garment
# joints after posing the body. Each strip needs room outside the thighs and
# inside the passing hand. All distances below are in the runner's metre frame.
const SECTIONS := ["F", "FL", "FLL", "L", "BL", "B", "BR", "R", "FRR", "FR"]
const CYCLE_PATH := "res://art/special-week/skirt-cycles.json"
var panels: Array[PackedInt32Array] = []
var _phases: Dictionary[StringName, PackedFloat32Array] = {}
var _offsets: Dictionary[StringName, Array] = {}
var _last_action := &""
var _last := PackedVector3Array()
var _from := PackedVector3Array()
var _fade := 1.0


func bind(rig: Skeleton3D) -> void:
	for section in SECTIONS:
		var chain := PackedInt32Array()
		for segment in 3:
			var bone := rig.find_bone("Sp_Hi_MSkirt0_%s_%02d" % [section, segment])
			if bone >= 0:
				chain.append(bone)
		if chain.size() == 3:
			panels.append(chain)


func offset_at(point: Vector3, radial: Vector3, thighs: PackedVector3Array,
		knees: PackedVector3Array, hands: PackedVector3Array) -> float:
	var required := -INF
	for side in 2:
		var leg := knees[side] - thighs[side]
		var fraction := clampf((point.y - thighs[side].y) / minf(-0.015, leg.y), 0.0, 1.0)
		var center := thighs[side] + leg * fraction
		var radius := lerpf(0.094, 0.071, fraction)
		required = maxf(required, (center - point).dot(radial) + radius)
	var deflection := 0.0
	for hand in hands:
		var offset := hand - point
		var depth := offset.dot(radial)
		var lateral := (offset - radial * depth).length()
		var nearby := 1.0 - smoothstep(0.035, 0.13, lateral)
		if depth > -0.17 and nearby > 0.0:
			deflection = minf(deflection, minf(0.0, depth - 0.040) * nearby)
	return clampf(maxf(deflection, required), -0.105, 0.29)


func load_cycles() -> void:
	if panels.size() != SECTIONS.size() or not FileAccess.file_exists(CYCLE_PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CYCLE_PATH))
	if not data is Dictionary or data.get("sections") != SECTIONS:
		return
	for action: String in data.get("curves", {}):
		var phases := PackedFloat32Array()
		var frames: Array[PackedVector3Array] = []
		for sample: Array in data.curves[action]:
			var values := PackedVector3Array()
			for xyz: Array in sample[1]:
				values.append(Vector3(xyz[0], xyz[1], xyz[2]))
			if values.size() != panels.size() * 3:
				return
			phases.append(sample[0])
			frames.append(values)
		if phases.size() >= 2:
			_phases[action] = phases
			_offsets[action] = frames
	_last.resize(panels.size() * 3)
	_from = _last.duplicate()


func reset(rig: Skeleton3D) -> void:
	if _last.is_empty():
		return
	_last.fill(Vector3.ZERO)
	_from.fill(Vector3.ZERO)
	_last_action = &""
	_fade = 1.0
	for panel in panels:
		for bone in panel:
			rig.set_bone_pose_position(bone, rig.get_bone_rest(bone).origin)


func apply_cycle(rig: Skeleton3D, action: StringName, phase: float, delta: float,
		pose: Callable, metres_per_unit: float) -> void:
	if _last.is_empty():
		return
	if action != _last_action:
		_from = _last.duplicate()
		_last_action = action
		_fade = 0.0
	_fade = minf(1.0, _fade + delta / 0.19)
	var blend := smoothstep(0.0, 1.0, _fade)
	var previous := PackedVector3Array()
	var following := PackedVector3Array()
	var fraction := 0.0
	if _phases.has(action):
		var phases := _phases[action]
		var next := phases.bsearch(phase) % phases.size()
		var prior := posmod(next - 1, phases.size())
		var span := fposmod(phases[next] - phases[prior], 1.0)
		fraction = clampf(fposmod(phase - phases[prior], 1.0) / maxf(0.00001, span), 0.0, 1.0)
		previous = _offsets[action][prior]
		following = _offsets[action][next]
	elif _fade == 1.0 and _last.count(Vector3.ZERO) == _last.size():
		return
	for i in panels.size():
		var parent_offset := Vector3.ZERO
		for level in 3:
			var slot := 3 * i + level
			var target := previous[slot].lerp(following[slot], fraction) if not previous.is_empty() else Vector3.ZERO
			_last[slot] = _from[slot].lerp(target, blend)
			var bone := panels[i][level]
			var parent: Transform3D = pose.call(rig.get_bone_parent(bone))
			var local := parent.basis.inverse() * (_last[slot] - parent_offset)
			rig.set_bone_pose_position(bone, rig.get_bone_rest(bone).origin + local / metres_per_unit)
			parent_offset = _last[slot]
