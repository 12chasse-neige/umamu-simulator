extends RefCounted

# A grip belongs to one measured wall face and its walkable landing.
const REACH := 1.59
const STANDOFF := 0.36
const TOP_CLEARANCE := 0.045

var lip: Vector3
var normal: Vector3
var _hang: Vector3
var _rim: Vector3
var _deck: Vector3
var _path := 0.0
var _rate := 0.0
var _aligning := true
var _from_top := false
var _supported_at_base := false


static func _ray(body: CharacterBody3D, start: Vector3, end: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(start, end, body.collision_mask, [body.get_rid()])
	return body.get_world_3d().direct_space_state.intersect_ray(query)


static func find_grip(body: CharacterBody3D, facing: Vector3) -> RefCounted:
	var foot_position := body.global_position
	var direction := Vector3(facing.x, 0.0, facing.z).normalized()
	var start := foot_position + Vector3.UP * 0.38
	var face := _ray(body, start, start + direction * 0.73)
	var from_top := face.is_empty()
	if from_top:
		if not body.is_on_floor():
			return null
		start = foot_position + direction * 0.80 - Vector3.UP * 0.37
		face = _ray(body, start, start - direction * 0.86)
	if face.is_empty() or absf(face.normal.y) > 0.13 or not face.collider is StaticBody3D:
		return null
	var outward := Vector3(face.normal.x, 0.0, face.normal.z).normalized()
	if outward.dot(direction) * (1.0 if from_top else -1.0) < 0.78:
		return null

	var side := Vector3.UP.cross(outward)
	var deck_height := foot_position.y
	for offset: Vector2 in [Vector2(0.07, -0.18), Vector2(0.07, 0.18), Vector2(0.40, 0.0)]:
		var probe: Vector3 = face.position - outward * offset.x + side * offset.y
		probe.y = foot_position.y + (0.19 if from_top else REACH)
		var top := _ray(body, probe, Vector3(probe.x, foot_position.y - 0.14, probe.z))
		if top.is_empty() or top.normal.y < 0.86 or top.collider != face.collider:
			return null
		if offset.y < 0.0:
			deck_height = top.position.y
		elif absf(top.position.y - deck_height) > 0.075:
			return null
	if from_top and absf(deck_height - foot_position.y) > 0.15:
		return null
	if not from_top and deck_height - foot_position.y < 0.46:
		return null

	var grip := new()
	grip.normal = outward
	grip.lip = Vector3(face.position.x, deck_height, face.position.z)
	grip._rim = grip.lip + outward * STANDOFF + Vector3.UP * TOP_CLEARANCE
	grip._deck = grip.lip - outward * 0.40 + Vector3.UP * TOP_CLEARANCE
	grip._hang = grip._rim - Vector3.UP * 1.29
	var floor_hit := _ray(body, grip._rim, grip._hang - Vector3.UP * TOP_CLEARANCE)
	if not floor_hit.is_empty():
		grip._hang.y = floor_hit.position.y + TOP_CLEARANCE
		grip._supported_at_base = true
	for point: Vector3 in [grip._rim, grip._deck]:
		var standing := body.global_transform
		standing.origin = point
		if body.test_move(standing, Vector3.UP * 0.015, null, body.safe_margin, true):
			return null
	if grip._rim.y - grip._hang.y < 0.44:
		return null
	grip._from_top = from_top
	grip._path = grip._length() if from_top else 0.0
	return grip


func _length() -> float:
	return _rim.y - _hang.y + _rim.distance_to(_deck)


func advance(body: CharacterBody3D, direction: Vector2, delta: float) -> bool:
	var input := direction.y
	if _aligning:
		var entry_point := _deck if _from_top else _hang
		var offset := entry_point - body.global_position
		if offset.length() > 0.012:
			return body.move_and_collide(offset.limit_length(delta * 1.7)) == null
		_aligning = false
	_rate = move_toward(_rate, input * 1.30, 5.5 * delta)
	_path = clampf(_path + _rate * delta, 0.0, _length())
	var rise := _rim.y - _hang.y
	var target := _hang + Vector3.UP * minf(_path, rise) - normal * maxf(0.0, _path - rise)
	# Roll the body over the lip through a short, tangent-continuous arc.
	const CORNER := 0.13
	if absf(_path - rise) < CORNER:
		var t := (_path - rise + CORNER) / (2.0 * CORNER)
		target = _rim - Vector3.UP * (CORNER * (1.0 - t) * (1.0 - t)) - normal * (CORNER * t * t)
	if body.move_and_collide(target - body.global_position) != null:
		return false
	return not ((_path >= _length() and input > 0.0) or (_path <= 0.0 and input < 0.0))


func clip_phase() -> float:
	return clampf(_path / _length(), 0.0, 1.0)


func top_blend(body: CharacterBody3D) -> float:
	return smoothstep(0.0, 0.66, (_rim - body.global_position).dot(normal))


func hands(body: CharacterBody3D) -> Array[Vector3]:
	var across := normal.cross(Vector3.UP)
	var targets: Array[Vector3] = []
	for sign_value: float in [1.0, -1.0]:
		var grip := lip + across * (0.19 * sign_value)
		var released := body.global_position + across * (0.19 * sign_value) + Vector3.UP * 0.88
		# Once the leading shoe bears weight, the hands can release for balance.
		var release := smoothstep(lip.y - 0.54, lip.y - 0.03, body.global_position.y)
		targets.append(grip.lerp(released - normal * 0.15 * (1.0 - top_blend(body)), release))
	return targets


func feet(body: CharacterBody3D) -> Array[Vector3]:
	var across := normal.cross(Vector3.UP)
	var targets: Array[Vector3] = []
	var height := body.global_position.y
	for sign_value: float in [1.0, -1.0]:
		var base := _hang + across * (0.11 * sign_value)
		if _supported_at_base:
			base.y -= TOP_CLEARANCE
		else:
			base += Vector3.UP * 0.19 - normal * 0.20
		var leading := sign_value > 0.0
		var planted := lip + across * (0.11 * sign_value) - normal * (0.10 if leading else 0.29)
		var swing := smoothstep(_hang.y, lip.y - 0.32, height) if leading else smoothstep(lip.y - 0.30, lip.y + TOP_CLEARANCE, height)
		var foot := base.lerp(planted, swing)
		# Clear the vertical face before bringing the toe over the lip.
		foot.y += sin(PI * swing) * (0.22 if leading else 0.16)
		foot += normal * sin(PI * swing) * 0.15
		var neutral := body.global_position + across * (0.11 * sign_value) - Vector3.UP * TOP_CLEARANCE
		targets.append(foot.lerp(neutral, smoothstep(0.42, 1.0, top_blend(body))))
	return targets
