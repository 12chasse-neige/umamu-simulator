extends RefCounted

const Course := preload("res://game/race/race-course.gd")
const Pace := preload("res://game/race/race-pace.gd")
const MAX_PROJECTED_PACE := Pace.MAX_SPEED * Course.RADIUS / Course.INNER_RADIUS

var distance: float
var previous: float
var finish_time := -1.0


func _init(start: float) -> void:
	distance = start
	previous = fposmod(start, Course.LAP)


func advance(projected: float, time: float, delta: float) -> bool:
	if finish_time >= 0.0:
		return true
	var step := wrapf(projected - previous, -Course.LAP * 0.5, Course.LAP * 0.5)
	# Shorter bends cover more center-line arc per metre of physical travel.
	if absf(step) > MAX_PROJECTED_PACE * delta + 0.08:
		return false
	previous = projected
	var before := distance
	distance += step
	if distance >= Course.DISTANCE:
		var crossing := (Course.DISTANCE - before) / step
		finish_time = time - delta * (1.0 - crossing)
	return true


func completed_laps() -> int:
	return clampi(floori(distance / Course.LAP), 0, Course.LAPS)
