extends Node3D

const Course := preload("res://game/race/race-course.gd")
const SCATTER := preload("res://art/campus/grass-scatter.json")
const NEAR_RADIUS := 26.0
const OUTER_RADIUS := 57.0
const HYSTERESIS := 5.0
const VALUES_PER_FACE := 10

var tiles: Dictionary[Vector2i, Array] = {}
var clumps: Array[Mesh] = []
var distant_clumps: Array[Mesh] = []
var active: Dictionary[Vector2i, MultiMeshInstance3D] = {}
var levels: Dictionary[Vector2i, bool] = {}
var waiting: Array[Vector2i] = []
var wanted: Dictionary[Vector2i, bool] = {}
var focus := Vector2(INF, INF)
var tile_size: float
var reserve_race_course := false


func _ready() -> void:
	for index in range(1, 5):
		for lod in ["near", "far"]:
			var source := get_parent().get_node_or_null("Campus/Grass clump %s %d" % [lod, index]) as MeshInstance3D
			if source == null:
				continue
			source.hide()
			if lod == "near":
				clumps.append(source.mesh)
			else:
				distant_clumps.append(source.mesh)
	var scatter: Dictionary = SCATTER.data
	tile_size = scatter.tile_size
	for tile: String in scatter.tiles:
		var parts := tile.split(",", false)
		tiles[Vector2i(parts[0].to_int(), parts[1].to_int())] = scatter.tiles[tile]
	set_process(not clumps.is_empty() and DisplayServer.get_name() != "headless")


func _process(_delta: float) -> void:
	var view := get_viewport().get_camera_3d()
	if view == null:
		return
	var camera := to_local(view.global_position)
	var point := Vector2(camera.x, camera.z)
	if point.distance_squared_to(focus) > HYSTERESIS * HYSTERESIS:
		_schedule(point)

	# Keep foliage preparation off the critical path of a camera cut or spawn.
	if not waiting.is_empty():
		var key: Vector2i = waiting.pop_front()
		if active.has(key):
			active[key].queue_free()
		var near := wanted[key]
		active[key] = _plant_tile(key, near)
		levels[key] = near


func _schedule(point: Vector2) -> void:
	focus = point
	wanted.clear()
	waiting.clear()
	var tile := Vector2i((point / tile_size).floor())
	var span := ceili(OUTER_RADIUS / tile_size) + 1
	for y in range(tile.y - span, tile.y + span + 1):
		for x in range(tile.x - span, tile.x + span + 1):
			var key := Vector2i(x, y)
			if not tiles.has(key):
				continue
			var distance := _center(key).distance_to(point)
			if distance > OUTER_RADIUS + (HYSTERESIS if active.has(key) else 0.0):
				continue
			var near := distance < NEAR_RADIUS
			if levels.has(key) and absf(distance - NEAR_RADIUS) < HYSTERESIS:
				near = levels[key]
			wanted[key] = near
			if not active.has(key) or near != levels[key]:
				waiting.append(key)
	for key in active.keys():
		if not wanted.has(key):
			active[key].queue_free()
			active.erase(key)
			levels.erase(key)
	waiting.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _center(a).distance_squared_to(point) < _center(b).distance_squared_to(point))


func _center(key: Vector2i) -> Vector2:
	return (Vector2(key) + Vector2(0.5, 0.5)) * tile_size


func _plant_tile(key: Vector2i, near: bool) -> MultiMeshInstance3D:
	var packed := Marshalls.base64_to_raw(tiles[key][1])
	var data := packed.decompress(int(tiles[key][0]), FileAccess.COMPRESSION_DEFLATE)
	var fields := data.to_float32_array()
	var transforms := PackedFloat32Array()
	var variation := absi(hash(key))
	var random := RandomNumberGenerator.new()
	random.seed = variation
	var tile_origin := Vector3(key.x * tile_size, 0, key.y * tile_size)
	var density_scale := 0.92 if near else 0.28
	var width_scale := 1.30 if near else 1.52
	for field in range(0, fields.size(), VALUES_PER_FACE):
		var width := fields[field + 2]
		var depth := fields[field + 3]
		var count := int(width * depth * fields[field + 8] * density_scale + random.randf())
		for sample in count:
			var u := random.randf()
			var v := random.randf()
			var x := fields[field] + u * width - tile_origin.x
			var z := -(fields[field + 1] + v * depth) - tile_origin.z
			var y := lerpf(lerpf(fields[field + 4], fields[field + 5], u),
					lerpf(fields[field + 7], fields[field + 6], u), v)
			var yaw := random.randf() * TAU
			var size := random.randf_range(0.73, 1.28)
			var leaf_width := size * width_scale
			var c := cos(yaw) * leaf_width
			var s := sin(yaw) * leaf_width
			var height := size * fields[field + 9] * 1.19
			if reserve_race_course and Course.contains_offset(Course.lateral_offset(x + tile_origin.x, z + tile_origin.z)):
				continue
			# MultiMesh packs the three rows of each 3D transform.
			transforms.append(c)
			transforms.append(0.0)
			transforms.append(s)
			transforms.append(x)
			transforms.append(0.0)
			transforms.append(height)
			transforms.append(0.0)
			transforms.append(y)
			transforms.append(-s)
			transforms.append(0.0)
			transforms.append(c)
			transforms.append(z)
	var source := clumps if near else distant_clumps
	var mulch := MultiMesh.new()
	mulch.transform_format = MultiMesh.TRANSFORM_3D
	mulch.mesh = source[variation % source.size()]
	mulch.instance_count = floori(transforms.size() / 12.0)
	if mulch.instance_count > 0:
		mulch.buffer = transforms
	var patch := MultiMeshInstance3D.new()
	patch.multimesh = mulch
	patch.position = tile_origin
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(patch)
	return patch
