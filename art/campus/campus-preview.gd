@tool
extends Node3D

const WINDOW_SHADER := preload("res://art/campus/clear-window.gdshader")
const WINDOW_MATERIALS := [&"Glass", &"Glass · graduated glazing"]
const PREVIEW_LAMP_SCALE := 1.0 / 4500.0
const PHYSICAL_LIGHTS := "rendering/lights_and_shadows/use_physical_light_units"

func _ready() -> void:
	var glazing := ShaderMaterial.new()
	glazing.shader = WINDOW_SHADER

	for child in $Campus.find_children("*", "MeshInstance3D", true, false):
		var pane := child as MeshInstance3D
		if pane.mesh == null:
			continue
		for surface in pane.mesh.get_surface_count():
			var original := pane.mesh.surface_get_material(surface)
			if original != null and original.resource_name in WINDOW_MATERIALS:
				pane.set_surface_override_material(surface, glazing)

	var physical_lights: bool = ProjectSettings.get_setting_with_override(PHYSICAL_LIGHTS)
	for child in $Campus.find_children("Fixture · *", "SpotLight3D", true, false):
		var lamp := child as SpotLight3D
		var task := str(lamp.name).begins_with("Fixture · task")
		var high_bay := str(lamp.name).begins_with("Fixture · high bay")
		if not physical_lights:
			lamp.light_energy *= PREVIEW_LAMP_SCALE
		lamp.spot_range = 2.1 if task else 9.8 if high_bay else 4.6
		lamp.spot_attenuation = 1.42
		lamp.shadow_enabled = not task
		lamp.distance_fade_enabled = true
		lamp.distance_fade_begin = 28.0
		lamp.distance_fade_shadow = 14.0
		lamp.distance_fade_length = 12.0

	if not Engine.is_editor_hint():
		var motion := $Campus.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if motion != null and motion.has_animation(&"FountainFlow"):
			motion.get_animation(&"FountainFlow").loop_mode = Animation.LOOP_LINEAR
			motion.play(&"FountainFlow")
