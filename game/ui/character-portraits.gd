extends Node

const Runner := preload("res://game/runner/runner.gd")
const RunnerScene := preload("res://game/runner/runner.tscn")
const CACHE := "user://portraits-v4"
const SIZE := Vector2i(224, 248)

static var _fallback: ImageTexture

var _portraits: Dictionary[String, ImageTexture] = {}
var _queued: Array[String] = []
var _building := false
var _placeholder: Image
var _studio: SubViewport
var _camera: Camera3D
var _model: Runner


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


static func for_node(owner: Node, path: String) -> Texture2D:
	var studio := owner.get_tree().root.get_node_or_null("CharacterPortraits")
	if studio != null:
		return studio.texture_for(path)
	if _fallback == null:
		_fallback = ImageTexture.create_from_image(_silhouette())
	return _fallback


func texture_for(path: String) -> Texture2D:
	if _portraits.has(path):
		return _portraits[path]
	if _placeholder == null:
		_placeholder = _silhouette()
	var texture := ImageTexture.create_from_image(_placeholder)
	_portraits[path] = texture
	if not path.is_empty() and DisplayServer.get_name() != "headless":
		_queued.append(path)
		if not _building:
			_building = true
			_build_queue.call_deferred()
	return texture


func _build_queue() -> void:
	var folder := ProjectSettings.globalize_path(CACHE)
	DirAccess.make_dir_recursive_absolute(folder)
	while not _queued.is_empty():
		var path: String = _queued.pop_front()
		var skin := _skin_path(path)
		var version := "%s:%d" % [skin, FileAccess.get_modified_time(skin)]
		var file := CACHE.path_join(version.sha256_text().left(20) + ".png")
		var portrait := Image.load_from_file(file) if FileAccess.file_exists(file) else null
		if portrait == null or portrait.is_empty():
			portrait = await _render(path, skin)
			if portrait != null and not portrait.is_empty():
				portrait.save_png(file)
		if portrait != null and not portrait.is_empty():
			_portraits[path].set_image(portrait)
	_building = false


func _render(path: String, skin: String) -> Image:
	if not ResourceLoader.exists(skin, "PackedScene"):
		return null
	var status := ResourceLoader.load_threaded_request(skin, "PackedScene")
	while status == OK and ResourceLoader.load_threaded_get_status(skin) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
	var scene := ResourceLoader.load_threaded_get(skin) as PackedScene if status == OK else load(skin) as PackedScene
	if scene == null:
		return null
	if _studio == null:
		_build_studio()
	if not _model.change_character(path):
		return null
	_model.motion.portrait()
	var rig := _model.motion.rig
	rig.force_update_all_bone_transforms()
	var head_point := rig.global_transform * rig.get_bone_global_pose(rig.find_bone("Head")).origin
	var ankle_point := rig.global_transform * rig.get_bone_global_pose(rig.find_bone("Ankle_L")).origin
	var body_span := maxf(0.01, head_point.y - ankle_point.y)
	var aim := head_point + Vector3.UP * body_span * 0.16
	_camera.size = body_span * 0.44
	_camera.near = body_span * 0.018
	_camera.far = body_span * 6.0
	_camera.position = aim + Vector3(0.15, 0.055, 2.1) * body_span
	_camera.look_at(aim)
	_studio.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var draft := _studio.get_texture().get_image()
	var crop := draft.get_used_rect()
	# Hair, ears and hats vary by rig. Align their rendered top edge for the gallery.
	_camera.position.y += (SIZE.y * 0.095 - crop.position.y) / SIZE.y * _camera.size
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var result := _studio.get_texture().get_image()
	_studio.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_model.change_character("")
	return result if result.get_used_rect().size.y > 40 else null


func _build_studio() -> void:
	_studio = SubViewport.new()
	_studio.size = SIZE
	_studio.own_world_3d = true
	_studio.transparent_bg = true
	_studio.msaa_3d = Viewport.MSAA_4X
	_studio.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_studio)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-27, 22, -8)
	light.light_energy = 0.86
	_studio.add_child(light)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("#eee6ff")
	world.environment.ambient_light_energy = 0.62
	_studio.add_child(world)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_studio.add_child(_camera)
	_camera.make_current()
	_model = RunnerScene.instantiate() as Runner
	_model.character_path = ""
	_model.computer_controlled = true
	_model.competition = true
	_model.movement_locked = true
	_model.get_node("CameraArm/Camera3D").free()
	_studio.add_child(_model)
	_model.facing.rotation.y = 0.0
	_model.set_physics_process(false)


static func _skin_path(path: String) -> String:
	if path == Runner.LOCAL_CHARACTER and ResourceLoader.exists(Runner.DETAIL_CHARACTER, "PackedScene"):
		return Runner.DETAIL_CHARACTER
	return path


static func _silhouette() -> Image:
	var portrait := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	var violet := Color("#a58fbe")
	for y in SIZE.y:
		for x in SIZE.x:
			var p := Vector2(float(x) / SIZE.x, float(y) / SIZE.y)
			var head := ((p - Vector2(0.5, 0.425)) / Vector2(0.148, 0.160)).length()
			var chest := ((p - Vector2(0.5, 0.84)) / Vector2(0.29, 0.24)).length()
			var color := violet
			color.a = 1.0 - smoothstep(0.97, 1.01, minf(head, chest))
			portrait.set_pixel(x, y, color)
	return portrait
