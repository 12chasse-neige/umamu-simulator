extends "res://game/runner/traversal/wall-ledge.gd"

const SPEED := 0.78
const SIDE_SPEED := 0.62
const CYCLE_TRAVEL := 0.49
const TRIM_DEPTH := 0.24
const BLOCKED_RELEASE_TIME := 0.45

class Hold:
	var anchor := Vector3.INF
	var goal := Vector3.INF
	var swinging := false
	var position := Vector3.ZERO

var tree := false
var direction_name := &"wall-up"
var clip_rate := 0.0
var _origin: Vector3
var _surface_rid: RID
var _blocked_for := 0.0
var _motion := Vector2.ZERO
var _cycle := 0.0
var _last_input := Vector2.ZERO
var _hands: Array[Hold] = [Hold.new(), Hold.new()]
var _feet: Array[Hold] = [Hold.new(), Hold.new()]


static func find_face(body: CharacterBody3D, direction: Vector3, tree_only := false) -> RefCounted:
	var forward := Vector3(direction.x, 0.0, direction.z).normalized()
	var chest := body.global_position + Vector3.UP * 0.90
	var hit := _ray(body, chest, chest + forward * 0.76)
	if hit.is_empty() or not hit.collider is StaticBody3D:
		return null
	var is_tree: bool = hit.collider.is_in_group(&"climbable_trunks")
	if tree_only and not is_tree:
		return null
	if absf(hit.normal.y) > (0.54 if is_tree else 0.13):
		return null
	var wall := new()
	wall.tree = is_tree
	wall._surface_rid = hit.rid
	wall.normal = Vector3(hit.normal.x, 0.0, hit.normal.z).normalized()
	if -wall.normal.dot(forward) < (0.43 if is_tree else 0.78):
		return null
	wall._origin = hit.position
	wall._origin.y = body.global_position.y
	if not wall._has_support(body, body.global_position):
		return null
	return wall


# Measure relief against the original face. A separate piece of trim must
# have that same supporting wall behind it.
func _surface(body: CharacterBody3D, point: Vector3) -> Dictionary:
	var depth := (point - _origin).dot(normal)
	var plane := point - normal * depth
	var start := plane + normal * (STANDOFF + TRIM_DEPTH + 0.08)
	var end := plane - normal * (0.55 if tree else 0.13)
	var hit := _ray(body, start, end)
	if hit.is_empty() or hit.normal.dot(normal) < (0.44 if tree else 0.82):
		return {}
	if (hit.position - _origin).dot(normal) > TRIM_DEPTH or not hit.collider is StaticBody3D:
		return {}
	if hit.rid != _surface_rid:
		var query := PhysicsRayQueryParameters3D.create(start, end, body.collision_mask,
			[body.get_rid(), hit.rid])
		var back := body.get_world_3d().direct_space_state.intersect_ray(query)
		if back.is_empty() or back.rid != _surface_rid:
			return {}
	return hit


func _has_support(body: CharacterBody3D, point: Vector3) -> bool:
	var across := Vector3.UP.cross(normal)
	var offsets := [Vector2(0, 1.20), Vector2(0, 0.40)] if tree else [
		Vector2(-0.19, 1.13), Vector2(0.19, 1.13), Vector2(0.0, 0.25)]
	for offset: Vector2 in offsets:
		if _surface(body, point + across * offset.x + Vector3.UP * offset.y).is_empty():
			return false
	return true


func advance(body: CharacterBody3D, direction: Vector2, delta: float) -> bool:
	clip_rate = 0.0
	var position := body.global_position
	var across := Vector3.UP.cross(normal)
	if tree:
		direction.x = 0.0
	# Anticipate the approaching capsule edge. Move out over a sill before
	# the vertical sweep meets its underside and ease in after clearing it.
	var height: float = body.get_node("Capsule").shape.height
	var leading := across * direction.x * 0.19 + Vector3.UP * direction.y * 0.18
	var surface_depth := -INF
	for level: float in [0.08, 0.40, 0.80, height - 0.32, height - 0.05]:
		for ahead: Vector3 in [Vector3.ZERO, leading]:
			var hit := _surface(body, position + Vector3.UP * level + ahead)
			if not hit.is_empty():
				surface_depth = maxf(surface_depth, (hit.position - _origin).dot(normal))
	var wall_depth := (position - _origin).dot(normal)
	if is_finite(surface_depth):
		var error := STANDOFF + surface_depth - wall_depth
		body.move_and_collide(normal * clampf(error, -1.0 * delta, 1.7 * delta))

	if direction.is_zero_approx():
		_blocked_for = 0.0
		_motion = Vector2.ZERO
		_update_contacts(body)
		return _has_support(body, body.global_position)
	if direction.dot(_last_input) < 0.25:
		_blocked_for = 0.0
	_last_input = direction
	_motion = _motion.move_toward(direction * Vector2(SIDE_SPEED, SPEED), 4.8 * delta)
	if absf(direction.x) > absf(direction.y):
		direction_name = &"wall-left" if direction.x < 0.0 else &"wall-right"
	else:
		direction_name = &"wall-down" if direction.y < 0.0 else &"wall-up"

	if _motion.y < 0.0:
		var ground := _ray(body, position + Vector3.UP * 0.06, position + Vector3.DOWN * 0.058)
		if not ground.is_empty() and ground.normal.y > 0.70:
			return false
	var start := body.global_position
	var traverse := (across * _motion.x + Vector3.UP * _motion.y) * delta
	if _has_support(body, start + traverse):
		body.move_and_collide(traverse)
	var achieved := body.global_position - start
	var progress := Vector2(achieved.dot(across), achieved.y).length()
	_cycle += progress / CYCLE_TRAVEL
	var full_speed := (direction.normalized() * Vector2(SIDE_SPEED, SPEED)).length()
	clip_rate = clampf(progress / (full_speed * delta), 0.0, 1.0)
	if tree and _motion.y < 0.0:
		clip_rate *= -1.0
	_update_contacts(body)
	_blocked_for = 0.0 if progress > 0.001 else _blocked_for + delta
	return _blocked_for < BLOCKED_RELEASE_TIME


func _update_contacts(body: CharacterBody3D) -> void:
	for side in 2:
		_update_hold(body, _hands[side], side, true)
		_update_hold(body, _feet[side], side, false)


func _update_hold(body: CharacterBody3D, hold: Hold, side: int, hand: bool) -> void:
	var opposite := 1 - side if hand else side
	var phase := fposmod(_cycle + opposite * 0.5, 1.0)
	var swinging := phase > 0.58
	if not hold.anchor.is_finite():
		hold.anchor = _contact(body, side, hand, Vector2.ZERO)
		hold.goal = hold.anchor
	if swinging and not hold.swinging:
		hold.goal = _contact(body, side, hand, _last_input * 0.17)
	elif not swinging and hold.swinging:
		hold.anchor = hold.goal
	hold.swinging = swinging
	var motion := smoothstep(0.58, 1.0, phase)
	hold.position = hold.anchor.lerp(hold.goal, motion) + normal * sin(PI * motion) * 0.10


func _contact(body: CharacterBody3D, side: int, hand: bool, reach: Vector2) -> Vector3:
	var across := normal.cross(Vector3.UP)
	var width := (0.15 if tree else 0.18) if hand else 0.11
	var x := width * (1.0 if side == 0 else -1.0) - reach.x
	var height := (1.35 if hand else 0.23) + reach.y
	var center := body.global_position + across * x + Vector3.UP * height
	var hit := _surface(body, center)
	if hit.is_empty():
		return center - normal * (0.30 if hand else 0.18)
	return hit.position + normal * (0.024 if hand else 0.12)


func clip_phase() -> float:
	return fposmod(_cycle, 1.0)


func top_blend(_body: CharacterBody3D) -> float:
	return 0.0


func hands(_body: CharacterBody3D) -> Array[Vector3]:
	return [_hands[0].position, _hands[1].position]


func feet(_body: CharacterBody3D) -> Array[Vector3]:
	return [_feet[0].position, _feet[1].position]
