extends RefCounted

const Course := preload("res://game/race/race-course.gd")
const Profile := preload("res://game/race/race-profile.gd")
enum Strategy { FRONT, PACE, LATE, END }
enum Stage { OPENING, MIDDLE, FINAL, SPURT }

const NAMES := ["Front Runner", "Pace Chaser", "Late Surger", "End Closer"]
const STAGES := ["Opening leg", "Middle leg", "Final leg", "Last sixth"]
const PLAN := ["Take the lead early", "Track the leaders", "Advance from midpack", "Save for a late charge"]
# Wiki strategy coefficients. The final leg and last sixth share the late column.
const VELOCITY := [
	[1.0, 0.980, 0.962], [0.978, 0.991, 0.975],
	[0.930, 0.998, 0.994], [0.931, 1.000, 1.020],
]
const ACCEL := [
	[1.000, 1.0, 0.996], [0.985, 1.0, 0.996],
	[0.975, 1.0, 1.000], [0.945, 1.0, 0.967],
]
const HP_FACTOR := [0.950, 0.890, 1.000, 0.995]
const POSITION_GAP := [0.0, 3.5, 8.0, 12.0]
const CAMPUS_SCALE := 0.232
const BASE := (20.0 - (Course.DISTANCE - 2000.0) / 1000.0) * CAMPUS_SCALE
const CRUISE := 0.94
const MAX_SPEED := 6.25
const FATIGUE_RESERVE := 0.18
const PUSH_COST := 1.40
const COLLISION_RECOVERY_TIME := 0.65

var profile: Profile
var strategy: Strategy
var stage := Stage.OPENING
var capacity: float
var energy: float
var speed_cap: float
var acceleration: float
var pushing := false
var freshness := 1.0
var spurt := 0.0
var _dash := true
var surface_scale: float
var _ground_fit: float
var _distance_fit: float
var _pace_before_collision := 0.0


func _init(build: Profile, opening_style: Strategy, mudland: bool) -> void:
	profile = build
	strategy = opening_style
	surface_scale = Course.MUD_PACE if mudland else 1.0
	# Compress the aptitude penalties to keep all selectable Academy runners playable.
	_ground_fit = 1.0 - 0.058 * "ABCDEFG".find(profile.surfaces[int(mudland)])
	_distance_fit = 1.0 - 0.065 * "ABCDEFG".find(profile.sprint)
	capacity = Course.DISTANCE * 0.58 + 2.1 * profile.stamina * HP_FACTOR[strategy]
	energy = capacity
	update_limits(0.0, 0.0, 0.0)


func speed_after_acceleration(current_speed: float, target_speed: float, delta: float) -> float:
	var recovery_target := minf(target_speed, _pace_before_collision)
	var next_speed := current_speed + acceleration * delta
	if current_speed >= recovery_target:
		clear_collision_recovery()
	else:
		var recovery_speed := current_speed + _pace_before_collision * delta / COLLISION_RECOVERY_TIME
		next_speed = maxf(next_speed, minf(recovery_target, recovery_speed))
	return minf(target_speed, next_speed)


func note_collision(approach_speed: float, remaining_speed: float) -> void:
	# Small bumps still use ordinary acceleration.
	var speed_loss := approach_speed - remaining_speed
	if speed_loss >= maxf(0.9, approach_speed * 0.30):
		_pace_before_collision = maxf(_pace_before_collision, approach_speed)


func clear_collision_recovery() -> void:
	_pace_before_collision = 0.0


static func stage_at(distance: float) -> Stage:
	var fraction := distance / Course.DISTANCE
	if fraction < 1.0 / 6.0:
		return Stage.OPENING
	if fraction < 2.0 / 3.0:
		return Stage.MIDDLE
	if fraction < 5.0 / 6.0:
		return Stage.FINAL
	return Stage.SPURT


# Charge the distance actually travelled at the previous tick's effort.
func spend(actual_speed: float, delta: float) -> void:
	var relative_speed := actual_speed / (BASE * surface_scale)
	var cost := 0.88 * relative_speed * relative_speed
	if pushing:
		cost *= PUSH_COST
	if stage >= Stage.FINAL:
		cost *= 1.0 + 12.0 / profile.guts
	energy = maxf(0.0, energy - actual_speed * cost * delta)


func update_limits(distance: float, gap: float, actual_speed: float) -> void:
	stage = stage_at(distance)
	var column := mini(stage, Stage.FINAL)
	var aptitude := 1.0 - 0.065 * "ABCDEFG".find(profile.styles[strategy])
	var tactical_wit := profile.wit * aptitude
	var precision := 0.965 + 0.035 * tactical_wit / 110.0
	speed_cap = BASE * VELOCITY[strategy][column] * precision
	# During position keep, runners ahead of their desired pack position settle,
	# while runners too far back close some of the gap.
	if distance < Course.DISTANCE * 10.0 / 24.0:
		speed_cap += clampf((gap - POSITION_GAP[strategy]) * 0.021, -0.19, 0.17) * precision

	acceleration = 0.00115 * sqrt(500.0 * profile.power * 5.0) * ACCEL[strategy][column] * _ground_fit * precision
	if actual_speed >= 0.85 * BASE * surface_scale or stage != Stage.OPENING:
		_dash = false
	if stage <= Stage.MIDDLE:
		# Ease back into formation or accelerate harder when out of position.
		acceleration *= 1.0 + clampf((gap - POSITION_GAP[strategy]) * 0.008, -0.08, 0.08)
	if _dash:
		acceleration += 2.8 * ACCEL[strategy][0] * _ground_fit

	if stage >= Stage.FINAL:
		var speed_term := 0.002 * sqrt(500.0 * profile.speed * 5.0) * CAMPUS_SCALE * _distance_fit
		# Forecast the remaining work on an inside racing line. A marginal
		# reserve allows a partial spurt, or a later one as the finish approaches.
		var remaining := maxf(Course.DISTANCE - distance, 1.0)
		var reserve := energy / remaining
		spurt = smoothstep(0.75, 1.55, reserve)
		speed_cap += speed_term + spurt * (speed_term + 0.45 * sqrt(profile.guts / 110.0))
		acceleration *= 1.0 + spurt * (0.38 if stage == Stage.SPURT else 0.24)
	else:
		spurt = 0.0
	freshness = smoothstep(0.0, FATIGUE_RESERVE * capacity, energy)
	if freshness < 1.0:
		speed_cap = lerpf(BASE * (0.78 + 0.025 * profile.guts / 110.0) * precision * VELOCITY[strategy][column], speed_cap, freshness)
		acceleration *= lerpf(0.53, 1.0, freshness)
	speed_cap = minf(speed_cap, MAX_SPEED) * surface_scale
	acceleration *= surface_scale


func rival_should_push(distance: float, gap: float) -> bool:
	if freshness < 0.5:
		return false
	var reserve := energy / maxf(1.0, Course.DISTANCE - distance)
	if stage >= Stage.FINAL:
		return reserve > 1.1 or stage == Stage.SPURT
	# Early leaders spend to establish position. A rival already on pace can
	# protect her finish, or press when she has energy to spare.
	return (stage == Stage.OPENING and strategy == Strategy.FRONT) or reserve > 1.14 \
		or (reserve > 0.91 and gap > POSITION_GAP[strategy] + 2.0)
