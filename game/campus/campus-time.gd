extends Node3D

const SKY_SHADER := preload("res://game/campus/campus-sky.gdshader")
const PANORAMA := preload("res://art/campus/courtyard-sky.hdr")
const TIME_STOPS := [6.1, 10.2, 17.85, 22.0]
const FAST_FORWARD_SECONDS := 2.4

@export_range(60.0, 3600.0, 1.0) var cycle_seconds := 1440.0
@export var hour := 10.2
@export var campus: Node3D
@export var world: WorldEnvironment
@export var clock_label: Label

var environment: Environment
var sky_material: ShaderMaterial
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var pendant_energy: Dictionary[SpotLight3D, float] = {}
var lantern_energy: Dictionary[SpotLight3D, float] = {}
var fountain_lights: Array[SpotLight3D] = []
var lantern_glass: StandardMaterial3D
var lamp_shade: StandardMaterial3D
var water: Dictionary[ShaderMaterial, ShaderMaterial] = {}
var light_level := -1.0
var shown_minute := -1
var skip_from := 0.0
var skip_hours := 0.0
var skip_elapsed := 0.0


func _ready() -> void:
	environment = world.environment.duplicate() as Environment
	world.environment = environment
	sky_material = ShaderMaterial.new()
	sky_material.shader = SKY_SHADER
	sky_material.set_shader_parameter(&"day_panorama", PANORAMA)
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	environment.sky = sky
	environment.glow_enabled = true
	environment.glow_intensity = 0.30
	environment.glow_hdr_threshold = 1.28
	environment.glow_bloom = 0.0
	environment.fog_enabled = true
	environment.fog_density = 0.00135
	environment.fog_sky_affect = 0.0
	environment.fog_sun_scatter = 0.21

	sun = campus.get_node("Late morning sun")
	sun.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	moon = DirectionalLight3D.new()
	moon.name = "Moonlight"
	moon.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	moon.light_color = Color("#a0bcff")
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 115.0
	add_child(moon)
	_register_fixtures()
	_apply_time()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"advance_time"):
		advance_phase()


func _process(delta: float) -> void:
	if skip_hours > 0.0:
		skip_elapsed = minf(skip_elapsed + delta, FAST_FORWARD_SECONDS)
		hour = fposmod(skip_from + skip_hours * smoothstep(0.0, FAST_FORWARD_SECONDS, skip_elapsed), 24.0)
		if skip_elapsed >= FAST_FORWARD_SECONDS:
			skip_hours = 0.0
	else:
		hour = fposmod(hour + 24.0 * delta / cycle_seconds, 24.0)
	_apply_time()


func advance_phase() -> void:
	skip_from = hour
	skip_hours = 24.0
	skip_elapsed = 0.0
	for stop in TIME_STOPS:
		var distance := fposmod(float(stop) - hour, 24.0)
		if distance > 0.18:
			skip_hours = minf(skip_hours, distance)


func _apply_time() -> void:
	var phase := (hour - 6.0) * TAU / 24.0
	var sun_direction := Vector3(-cos(phase), 0.86 * sin(phase), 0.51 * sin(phase)).normalized()
	var altitude := sun_direction.y
	var day := smoothstep(-0.17, 0.29, altitude)
	var dusk := smoothstep(-0.24, 0.03, altitude) * (1.0 - smoothstep(0.03, 0.38, altitude))
	var fixtures := 1.0 - smoothstep(-0.20, 0.16, altitude)

	sun.look_at(sun.global_position - sun_direction, Vector3.UP)
	sun.light_energy = 0.94 * smoothstep(-0.055, 0.26, altitude)
	sun.light_color = Color("#fff6e8").lerp(Color("#ff9961"), dusk * 0.93)
	sun.visible = sun.light_energy > 0.002
	moon.look_at(moon.global_position + sun_direction, Vector3.UP)
	moon.light_energy = 0.19 * smoothstep(0.02, 0.37, -altitude)
	moon.visible = moon.light_energy > 0.002
	sky_material.set_shader_parameter(&"sun_direction", sun_direction)
	sky_material.set_shader_parameter(&"daylight", day)
	sky_material.set_shader_parameter(&"twilight", dusk)

	environment.ambient_light_color = Color("#7794dc").lerp(Color("#e7f0ff"), day).lerp(Color("#e9b4a1"), dusk * 0.58)
	environment.ambient_light_energy = lerpf(0.21, 0.53, day) + 0.07 * dusk
	environment.fog_light_color = Color("#263c68").lerp(Color("#bac8da"), day).lerp(Color("#c08273"), dusk * 0.3)
	if absf(light_level - fixtures) >= 0.005 or (fixtures == 0.0 or fixtures == 1.0) and fixtures != light_level:
		_update_fixtures(fixtures)
		light_level = fixtures

	for material in water.values():
		material.set_shader_parameter(&"daylight_fraction", day)

	var minute := floori(hour * 60.0)
	if minute != shown_minute:
		clock_label.text = "%02d:%02d" % [floori(hour), minute % 60]
		shown_minute = minute


func _register_fixtures() -> void:
	for fixture in campus.find_children("Fixture · *", "SpotLight3D", true, false):
		var lamp := fixture as SpotLight3D
		pendant_energy[lamp] = lamp.light_energy

	for child in campus.find_children("*", "MeshInstance3D", true, false):
		var model := child as MeshInstance3D
		var material := model.material_override as ShaderMaterial
		if material != null and material.shader.resource_path.ends_with("fountain-water.gdshader"):
			if not water.has(material):
				water[material] = material.duplicate() as ShaderMaterial
			model.material_override = water[material]
			if model.name == &"Water surface":
				_add_fountain_lights(model.to_global(model.get_aabb().get_center()))

		if str(model.name).begins_with("Cast cap, frame and warm panes"):
			for surface in model.mesh.get_surface_count():
				var glass := model.mesh.surface_get_material(surface) as StandardMaterial3D
				if glass != null and glass.resource_name == &"Honey glass":
					if lantern_glass == null:
						lantern_glass = _emissive_copy(glass)
					model.set_surface_override_material(surface, lantern_glass)
					_add_path_light(model)
		elif str(model.name).begins_with("Opal table lamp"):
			for surface in model.mesh.get_surface_count():
				var shade := model.mesh.surface_get_material(surface) as StandardMaterial3D
				if shade != null and shade.resource_name == &"Classroom · opal enamel":
					if lamp_shade == null:
						lamp_shade = _emissive_copy(shade)
					model.set_surface_override_material(surface, lamp_shade)


func _emissive_copy(original: StandardMaterial3D) -> StandardMaterial3D:
	var material := original.duplicate() as StandardMaterial3D
	material.emission_enabled = true
	material.emission = Color("#ffc578")
	return material


func _add_path_light(model: MeshInstance3D) -> void:
	var is_gate_lantern := str(model.get_parent().name).begins_with("Pier lantern")
	var lamp := SpotLight3D.new()
	lamp.name = "Gate lantern pool" if is_gate_lantern else "Lantern pool"
	lamp.light_color = Color("#ffd095")
	lamp.spot_range = 10.0
	lamp.spot_attenuation = 1.38
	lamp.spot_angle = 68.0
	lamp.spot_angle_attenuation = 0.62
	lamp.distance_fade_enabled = true
	lamp.distance_fade_begin = 47.0
	lamp.distance_fade_length = 25.0
	add_child(lamp, true)
	var bounds := model.get_aabb()
	var anchor := bounds.get_center()
	var peak_energy := 4.1
	if is_gate_lantern:
		# Put the beam just outside the pane facing the entrance so the cap can shade the pier.
		var inward := Vector3(-signf(model.global_position.x), 0.0, 0.0)
		lamp.global_position = model.to_global(anchor) + inward * 0.32
		lamp.look_at(lamp.global_position + inward * 0.50 + Vector3.DOWN)
		lamp.spot_angle = 70.0
		lamp.spot_attenuation = 0.75
		lamp.light_size = 0.45
		lamp.light_specular = 0.20
		lamp.shadow_enabled = true
		lamp.shadow_bias = 0.012
		lamp.shadow_normal_bias = 0.25
		lamp.distance_fade_shadow = lamp.distance_fade_begin + lamp.distance_fade_length
		peak_energy = 2.3
	else:
		# Start directly below the lantern casing so the solid cap stays above the beam.
		anchor.y = bounds.position.y - 0.05
		lamp.global_position = model.to_global(anchor)
		lamp.rotation.x = -PI * 0.5
	lantern_energy[lamp] = peak_energy


func _add_fountain_lights(center: Vector3) -> void:
	for side in [-1.0, 1.0]:
		var lamp := SpotLight3D.new()
		lamp.name = "Basin uplight"
		lamp.light_color = Color("#ffd7a4")
		lamp.spot_range = 7.0
		lamp.spot_angle = 29.0
		lamp.spot_angle_attenuation = 0.85
		add_child(lamp, true)
		lamp.global_position = center + Vector3(float(side) * 2.15, 0.11, 1.56)
		lamp.look_at(center + Vector3.UP * 2.05, Vector3.UP)
		fountain_lights.append(lamp)


func _update_fixtures(level: float) -> void:
	for lamp in pendant_energy:
		lamp.light_energy = pendant_energy[lamp] * lerpf(0.85, 1.4, level)
	for lamp in lantern_energy:
		lamp.light_energy = lantern_energy[lamp] * level
		lamp.visible = level > 0.005
	for lamp in fountain_lights:
		lamp.light_energy = 2.1 * level
		lamp.visible = level > 0.005
	if lantern_glass != null:
		lantern_glass.emission_energy_multiplier = 2.35 * level
	if lamp_shade != null:
		lamp_shade.emission_energy_multiplier = lerpf(0.05, 0.9, level)
