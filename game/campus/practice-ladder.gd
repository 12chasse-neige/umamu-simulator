extends StaticBody3D

const RUNG_GAP := 0.235
const DECK_LEVEL := 8
const DECK_HEIGHT := RUNG_GAP * DECK_LEVEL
const APPROACH := 0.43
const EXIT_DEPTH := -0.50
const EXIT_LIFT := 0.045

@onready var rail_material: Material = $Rails.material_override


func _ready() -> void:
	add_to_group(&"practice_ladders")
	var rung := CylinderMesh.new()
	rung.top_radius = 0.018
	rung.bottom_radius = 0.018
	rung.height = 0.52
	rung.radial_segments = 12
	rung.material = rail_material
	for level in range(1, DECK_LEVEL + 1):
		var bar := MeshInstance3D.new()
		bar.mesh = rung
		bar.position.y = level * RUNG_GAP
		bar.rotation.z = PI * 0.5
		add_child(bar)


func entry_level(point: Vector3) -> int:
	var local := to_local(point)
	if absf(local.x) > 0.56:
		return -1
	if absf(local.y) < 0.27 and local.z >= 0.27 and local.z <= 0.94:
		return 0
	if absf(local.y - DECK_HEIGHT) < 0.24 and local.z >= -0.92 and local.z <= -0.22:
		return DECK_LEVEL
	return -1


func track_point(height: float) -> Vector3:
	return to_global(Vector3(0.0, height, APPROACH))


func exit_point() -> Vector3:
	return to_global(Vector3(0.0, DECK_HEIGHT + EXIT_LIFT, EXIT_DEPTH))


func holds(height: float, hands: bool) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for side in 2:
		var sign_value := -1.0 if side == 0 else 1.0
		var order := 1 - side if hands else side
		var position_in_rungs := height / RUNG_GAP
		var cycle := (position_in_rungs + order) * 0.5
		var phase := fposmod(cycle, 1.0)
		var swing := smoothstep(0.62, 1.0, phase)
		var first := (6 - order) if hands else (1 - order)
		var low := floorf(cycle) * 2.0 + first
		var level := lerpf(low, low + 2.0, swing)
		var arc := sin(PI * swing)
		var x := (0.205 if hands else 0.108) * sign_value
		var depth := 0.066 if hands else 0.128
		if hands:
			# The rungs end at the platform. The rails continue as handholds.
			x = lerpf(x, 0.255 * sign_value, smoothstep(7.8, 8.4, level))
			level = minf(float(DECK_LEVEL) + 3.75, level)
		else:
			depth = lerpf(0.34, depth, smoothstep(0.0, 1.0, level))
			level = minf(float(DECK_LEVEL), level)
		result.append(to_global(Vector3(x, level * RUNG_GAP + arc * 0.026, depth + arc * 0.125)))
	return result
