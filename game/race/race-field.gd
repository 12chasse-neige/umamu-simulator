extends Node3D

const Course := preload("res://game/race/race-course.gd")
const Surface := preload("res://game/race/track-surface.gdshader")
const ANIME_ART := "res://art/race/hishi-amazon-anime.png"
const FALLBACK_ART := "res://art/race/finish-amazon.png"
const TRACK_HEIGHT := 0.034
const CURVE_SEGMENTS := 48
const ENTRANCE_HALF_WIDTH := 3.0

var _race_surface := ShaderMaterial.new()


func install(campus: Node3D) -> void:
	_race_surface.shader = Surface
	var stations := _course_stations()
	_build_tread(stations)
	_build_guard(&"InnerGuardRail", stations, Course.INNER_EDGE)
	_build_guard(&"OuterGuardRail", stations, Course.HALF_WIDTH)
	_build_start_stripe(campus)
	_build_start_sign()


func set_surface(mudland: bool) -> void:
	_race_surface.set_shader_parameter("mudland", mudland)


func _course_stations() -> PackedFloat32Array:
	# Divide at the actual tangent joins, where the straight meets each bend.
	var distance := -Course.START_DISTANCE
	var stations := PackedFloat32Array([distance])
	for section in 4:
		var straight := section % 2 == 0
		var length := Course.STRAIGHT if straight else Course.TURN
		var steps := 24 if straight else CURVE_SEGMENTS
		for step in range(1, steps + 1):
			stations.append(distance + length * float(step) / steps)
		distance += length
	stations.append(-ENTRANCE_HALF_WIDTH)
	stations.append(ENTRANCE_HALF_WIDTH)
	stations.sort()
	return stations


func _build_tread(stations: PackedFloat32Array) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(_race_surface)
	for index in stations.size() - 1:
		var near := stations[index]
		var far := stations[index + 1]
		var a := Course.point_at(near, Course.INNER_EDGE)
		var b := Course.point_at(far, Course.INNER_EDGE)
		var c := Course.point_at(far, Course.HALF_WIDTH)
		var d := Course.point_at(near, Course.HALF_WIDTH)
		for corner: Vector3 in [a, b, c, a, c, d]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(corner + Vector3.UP * TRACK_HEIGHT)
	_add_solid_mesh(&"RaceTread", surface.commit())


func _build_guard(label: StringName, stations: PackedFloat32Array, offset: float) -> void:
	var cream := StandardMaterial3D.new()
	cream.albedo_color = Color("#e4e7df")
	cream.roughness = 0.68
	var beam := BoxMesh.new()
	beam.size = Vector3(0.15, 0.12, 1.0)
	var post := BoxMesh.new()
	post.size = Vector3(0.115, 0.65, 0.115)
	var railing := SurfaceTool.new()
	railing.begin(Mesh.PRIMITIVE_TRIANGLES)
	railing.set_material(cream)
	var height := TRACK_HEIGHT + 0.70
	var outside := offset > 0.0
	for index in stations.size() - 1:
		var from := stations[index]
		var to := stations[index + 1]
		if outside and from < ENTRANCE_HALF_WIDTH and to > -ENTRANCE_HALF_WIDTH:
			continue
		var a := Course.point_at(from, offset)
		var b := Course.point_at(to, offset)
		var span := b - a
		var yaw := atan2(span.x, span.z)
		var along := Basis(Vector3.UP, yaw).scaled_local(Vector3(1.0, 1.0, span.length() + 0.12))
		railing.append_from(beam, 0, Transform3D(along, (a + b) * 0.5 + Vector3.UP * height))
		if index % 2 == 0 or (outside and is_equal_approx(from, ENTRANCE_HALF_WIDTH)):
			var base := a + Vector3.UP * (TRACK_HEIGHT + 0.325)
			railing.append_from(post, 0, Transform3D(Basis(Vector3.UP, yaw), base))
		if outside and is_equal_approx(to, -ENTRANCE_HALF_WIDTH):
			var base := b + Vector3.UP * (TRACK_HEIGHT + 0.325)
			railing.append_from(post, 0, Transform3D(Basis(Vector3.UP, yaw), base))
	_add_solid_mesh(label, railing.commit())


func _add_solid_mesh(label: StringName, mesh: ArrayMesh) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	var instance := MeshInstance3D.new()
	instance.name = "Mesh"
	instance.mesh = mesh
	body.add_child(instance)
	add_child(body)


func _build_start_stripe(campus: Node3D) -> void:
	var original := campus.find_child("Start stripe", true, false) as MeshInstance3D
	var paint := original.get_active_material(0) if original != null else null
	var span := Course.HALF_WIDTH - Course.INNER_EDGE
	var mid := (Course.INNER_EDGE + Course.HALF_WIDTH) * 0.5
	_box(self, Course.point_at(0.0, mid) + Vector3.UP * (TRACK_HEIGHT + 0.007),
		Vector3(0.25, 0.008, span), paint)


func _build_start_sign() -> void:
	var signpost := Node3D.new()
	signpost.name = "AmazonStartSign"
	# Keep the board parallel with the straight, facing across the tread.
	signpost.position = Course.point_at(0.0, Course.INNER_EDGE - 1.30)
	add_child(signpost)

	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color("#183632")
	var backing := StandardMaterial3D.new()
	backing.albedo_color = Color("#f4ead7")
	var gilt := StandardMaterial3D.new()
	gilt.albedo_color = Color("#c5a872")
	_box(signpost, Vector3(0.0, 1.61, 0.0), Vector3(1.77, 2.28, 0.13), frame)
	_box(signpost, Vector3(0.0, 1.51, 0.069), Vector3(1.65, 1.82, 0.012), backing)
	_box(signpost, Vector3(0.0, 2.43, 0.09), Vector3(1.65, 0.035, 0.022), gilt)
	for side: float in [-1.0, 1.0]:
		_box(signpost, Vector3(side * 0.67, 0.48, -0.04), Vector3(0.12, 0.96, 0.13), frame)

	var artwork: Texture2D
	for path: String in [ANIME_ART, FALLBACK_ART]:
		if ResourceLoader.exists(path, "Texture2D"):
			artwork = load(path) as Texture2D
			if artwork != null:
				break
	if artwork != null:
		var material := StandardMaterial3D.new()
		material.albedo_texture = artwork
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var quad := QuadMesh.new()
		quad.size = Vector2(1.70 * float(artwork.get_width()) / artwork.get_height(), 1.70)
		var portrait := MeshInstance3D.new()
		portrait.mesh = quad
		portrait.material_override = material
		portrait.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		portrait.position = Vector3(0.0, 1.51, 0.083)
		signpost.add_child(portrait)

	var title := Label3D.new()
	title.text = tr("START / FINISH")
	title.font_size = 58
	title.pixel_size = 0.0027
	title.outline_size = 0
	title.modulate = frame.albedo_color if artwork == null else Color("#f8e9ba")
	title.position = Vector3(0.0, 1.51 if artwork == null else 2.58, 0.081)
	signpost.add_child(title)


func _box(parent: Node3D, at: Vector3, dimensions: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	parent.add_child(instance)
