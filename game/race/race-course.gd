extends RefCounted

# The primary oval and its existing start stripe in the Academy scene.
const LEFT := -42.0
const RIGHT := 52.0
const CENTER_Z := -166.0
const START_X := 40.0
const RADIUS := 30.0
const HALF_WIDTH := 4.0
# The nested dirt oval has the same bend centres as the primary circuit.
const INNER_RADIUS := 13.5
const INNER_EDGE := INNER_RADIUS - RADIUS
const STRAIGHT := RIGHT - LEFT
const TURN := PI * RADIUS
const LAP := 2.0 * (STRAIGHT + TURN)
const LAPS := 2
const DISTANCE := LAPS * LAP
const MUD_PACE := 0.86
const START_DISTANCE := START_X - LEFT


static func contains_offset(offset: float) -> bool:
	return offset >= INNER_EDGE and offset <= HALF_WIDTH


static func lateral_offset(x: float, z: float) -> float:
	return Vector2(x - clampf(x, LEFT, RIGHT), z - CENTER_Z).length() - RADIUS


static func point_at(distance: float, offset := 0.0) -> Vector3:
	var s := fposmod(distance + START_DISTANCE, LAP)
	var radius := RADIUS + offset
	if s < STRAIGHT:
		return Vector3(LEFT + s, 0.0, CENTER_Z + radius)
	s -= STRAIGHT
	if s < TURN:
		var angle := PI * 0.5 - s / RADIUS
		return Vector3(RIGHT + cos(angle) * radius, 0.0, CENTER_Z + sin(angle) * radius)
	s -= TURN
	if s < STRAIGHT:
		return Vector3(RIGHT - s, 0.0, CENTER_Z - radius)
	var angle := -PI * 0.5 - (s - STRAIGHT) / RADIUS
	return Vector3(LEFT + cos(angle) * radius, 0.0, CENTER_Z + sin(angle) * radius)


static func forward_at(distance: float) -> Vector3:
	return (point_at(distance + 0.1) - point_at(distance - 0.1)).normalized()


# The closest center-line distance and signed lateral offset of a world point.
static func project(point: Vector3) -> Vector2:
	var axis := Vector2(clampf(point.x, LEFT, RIGHT), CENTER_Z)
	var radial := Vector2(point.x, point.z) - axis
	var s: float
	if point.x > RIGHT:
		s = STRAIGHT + (PI * 0.5 - radial.angle()) * RADIUS
	elif point.x < LEFT:
		s = STRAIGHT * 2.0 + TURN + (PI * 1.5 - fposmod(radial.angle(), TAU)) * RADIUS
	elif point.z >= CENTER_Z:
		s = point.x - LEFT
	else:
		s = STRAIGHT + TURN + RIGHT - point.x
	return Vector2(fposmod(s - START_DISTANCE, LAP), radial.length() - RADIUS)
