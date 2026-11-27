extends RefCounted

const Course := preload("res://game/race/race-course.gd")
const START := Vector2(Course.START_X, Course.CENTER_Z + Course.RADIUS)
const CENTER_Z := Course.CENTER_Z
const LEFT := Course.LEFT
const RIGHT := Course.RIGHT
const RADIUS := Course.RADIUS
const LAP := Course.LAP

enum State { IDLE, COUNTDOWN, RUNNING, FINISHED }
var state := State.IDLE
var time := 0.0
var _progress := 0.0
var _last := 0.0


func update(point: Vector3, pressed: bool, delta: float) -> void:
	if pressed and active():
		reset()
		return
	if not active():
		if pressed and at_start(point):
			_progress = 0.0
			time = 3.0
			state = State.COUNTDOWN
		return
	var course_position := Course.project(point)
	if absf(point.y) > 1.0 or not Course.contains_offset(course_position.y):
		reset()
		return
	if state == State.COUNTDOWN:
		time = maxf(0.0, time - delta)
		if time == 0.0:
			state = State.RUNNING
			_last = course_position.x
		return
	_progress += wrapf(course_position.x - _last, -LAP * 0.5, LAP * 0.5)
	_last = course_position.x
	time += delta
	if _progress >= LAP - 0.35:
		state = State.FINISHED


func active() -> bool:
	return state == State.COUNTDOWN or state == State.RUNNING


func at_start(point: Vector3) -> bool:
	return absf(point.y) < 1.0 and absf(point.x - Course.START_X) < 3.0 \
		and point.z >= Course.CENTER_Z + Course.INNER_RADIUS \
		and point.z <= Course.CENTER_Z + Course.RADIUS + Course.HALF_WIDTH


func reset() -> void:
	state = State.IDLE
	time = 0.0
	_progress = 0.0
