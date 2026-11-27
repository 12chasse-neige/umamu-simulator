extends RefCounted

const MIN_HEIGHT := 0.28
const MAX_HEIGHT := 0.83
const MAX_DEPTH := 0.82

var forward: Vector3
var handhold: Vector3
var _start: Vector3
var _destination: Vector3
var _rise: float
var _duration: float
var phase := 0.0


static func find(body: CharacterBody3D, heading: Vector3, speed: float) -> RefCounted:
	var start := body.global_position
	var direction := heading.normalized()
	var baseline := start + Vector3.UP * (MIN_HEIGHT - 0.035)
	var wall := _ray(body, baseline, baseline + direction * 0.50)
	if wall.is_empty() or absf(wall.normal.y) > 0.24 or wall.normal.dot(direction) > -0.76:
		return null
	if not wall.collider is StaticBody3D or wall.collider.is_in_group(&"climbable_trunks"):
		return null
	var edge: Vector3 = wall.position
	var top := _ray(body, edge + direction * 0.07 + Vector3.UP * 0.72, edge + direction * 0.07)
	if top.is_empty() or top.normal.y < 0.80 or top.rid != wall.rid:
		return null
	var height: float = top.position.y - start.y
	if height < MIN_HEIGHT or height > MAX_HEIGHT:
		return null
	# A long ledge or a succession of stairs is not a narrow vaultable obstacle.
	var probe := edge + direction * (MAX_DEPTH + 0.26)
	probe.y = start.y + MAX_HEIGHT + 0.14
	var landing_hit := _ray(body, probe, probe - Vector3.UP * (MAX_HEIGHT + 0.45))
	if landing_hit.is_empty() or landing_hit.normal.y < 0.79 or absf(landing_hit.position.y - start.y) > 0.22:
		return null
	var destination: Vector3 = landing_hit.position + Vector3.UP * 0.02
	var lift := Vector3.UP * (height + 0.075)
	var across := destination - start
	across.y = 0.0
	var raised := body.global_transform.translated(lift)
	if body.test_move(body.global_transform, lift) or body.test_move(raised, across):
		return null
	var landing := body.global_transform
	landing.origin = destination
	if body.test_move(landing, Vector3.UP * 0.025, null, body.safe_margin, true):
		return null

	var vault := new()
	vault.forward = direction
	vault.handhold = top.position
	vault._start = start
	vault._destination = destination
	vault._rise = lift.y
	vault._duration = clampf(across.length() / speed + 0.26, 0.57, 0.83)
	return vault


func advance(body: CharacterBody3D, delta: float) -> bool:
	phase = minf(1.0, phase + delta / _duration)
	var across := smoothstep(0.16, 0.86, phase)
	var lift := smoothstep(0.0, 0.29, phase) * (1.0 - smoothstep(0.70, 1.0, phase))
	var target := _start.lerp(_destination, across) + Vector3.UP * _rise * lift
	return body.move_and_collide(target - body.global_position) == null and phase < 1.0


static func _ray(body: CharacterBody3D, start: Vector3, end: Vector3) -> Dictionary:
	return body.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(start, end, body.collision_mask, [body.get_rid()]))
