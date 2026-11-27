extends RefCounted

# Input selects an intent. The pose follows achieved movement and traversal.
enum Gait { WALK, JOG, RUN }
enum Flight { GROUNDED, LOAD, JUMP, DOUBLE_JUMP, FALL }
const GAITS: Array[StringName] = [&"walk", &"jog", &"run"]
const SPEEDS: Array[float] = [0.86, 2.45, 3.65]
const MAX_RUN_SPEED := 5.1
const RUN_ACCELERATION_TIME := 2.0
const RUN_DECELERATION_TIME := 0.75
const TAKEOFF := 4.9
const SECOND_TAKEOFF := 3.35
const LOAD_TIME := 0.085
const COYOTE_TIME := 0.075
const BUFFER_TIME := 0.13

var visual_gait := Gait.WALK
var run_boost := 0.0
var flight := Flight.GROUNDED
var flight_age := 0.0
var load_left := 0.0
var _second_available := false
var _floor_grace := 0.0
var _jump_buffer := 0.0


func requested_gait(walk: bool, fast: bool) -> Gait:
	if walk:
		return Gait.WALK
	if fast:
		return Gait.RUN
	return Gait.JOG


func update_run_boost(accelerating: bool, delta: float) -> void:
	var target := 1.0 if accelerating else 0.0
	var duration := RUN_ACCELERATION_TIME if accelerating else RUN_DECELERATION_TIME
	run_boost = move_toward(run_boost, target, delta / duration)


func stride_for_speed(speed: float, limits: Array[float]) -> Gait:
	# A small hysteresis band keeps the other gaits stable while changing pace.
	while visual_gait < Gait.RUN:
		var threshold := (limits[visual_gait] + limits[visual_gait + 1]) * 0.5
		if speed < threshold + 0.13:
			break
		visual_gait = (visual_gait + 1) as Gait
	while visual_gait > Gait.WALK:
		var threshold := (limits[visual_gait] + limits[visual_gait - 1]) * 0.5
		if speed > threshold - 0.13:
			break
		visual_gait = (visual_gait - 1) as Gait
	return visual_gait


func horizontal(current: Vector3, desired: Vector3, supported: bool, delta: float) -> Vector3:
	if not supported:
		# Give the player steering in flight while carrying take-off momentum.
		return current.move_toward(desired, (3.8 if desired.length_squared() > 0.01 else 1.4) * delta)
	var target := desired
	var pace := current.length()
	if pace > 0.35 and not desired.is_zero_approx():
		var dot := current.normalized().dot(desired.normalized())
		# Brake into sharp changes, then rotate under the body's available traction.
		target *= lerpf(0.30, 1.0, smoothstep(-0.5, 0.96, dot))
		if dot < -0.55 and pace > 1.0:
			target = Vector3.ZERO
	var rate := 16.0 if target.length_squared() < current.length_squared() else 10.5
	return current.move_toward(target, rate * delta)


func vertical(speed: float, gravity: float, supported: bool, ready: bool, pressed: bool, delta: float, room_for_second: bool) -> float:
	flight_age += delta
	_floor_grace = COYOTE_TIME if supported else maxf(0.0, _floor_grace - delta)
	_jump_buffer = BUFFER_TIME if pressed else maxf(0.0, _jump_buffer - delta)
	if not ready:
		if flight == Flight.LOAD:
			flight = Flight.GROUNDED if supported else Flight.FALL
		load_left = 0.0
		_second_available = false
		_jump_buffer = 0.0
	if supported and flight != Flight.LOAD:
		flight = Flight.GROUNDED
		_second_available = false
	if _jump_buffer > 0.0 and _floor_grace > 0.0 and flight != Flight.LOAD:
		_jump_buffer = 0.0
		flight = Flight.LOAD
		load_left = LOAD_TIME if supported else delta
	if flight == Flight.LOAD and ready:
		load_left = maxf(0.0, load_left - delta)
		if load_left == 0.0:
			flight = Flight.JUMP
			flight_age = 0.0
			_second_available = true
			_floor_grace = 0.0
			return TAKEOFF
	elif pressed and not supported and _second_available and flight_age > 0.11 and room_for_second:
		flight = Flight.DOUBLE_JUMP
		flight_age = 0.0
		_second_available = false
		_jump_buffer = 0.0
		return SECOND_TAKEOFF
	elif not supported and (flight == Flight.GROUNDED or flight == Flight.LOAD):
		flight = Flight.FALL
		flight_age = 0.0
	return 0.0 if supported else speed + gravity * delta


func reset() -> void:
	visual_gait = Gait.WALK
	run_boost = 0.0
	flight = Flight.GROUNDED
	load_left = 0.0
	flight_age = 0.0
	_second_available = false
	_floor_grace = 0.0
	_jump_buffer = 0.0
