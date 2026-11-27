extends SceneTree

const Course := preload("res://game/race/race-course.gd")
const Pace := preload("res://game/race/race-pace.gd")
const Profile := preload("res://game/race/race-profile.gd")

var failed := false


func _initialize() -> void:
	var build := Profile.new("special-week-trial.glb", "Special Week")
	_check(build.speed == 102 and build.styles == "GAAC", "Special Week trial model lost her card")
	var gold := Profile.new("gold-ship.glb", "Gold Ship")
	var suzuka := Profile.new("silence-suzuka.glb", "Silence Suzuka")
	_check(gold.preferred_style([0, 0, 0, 0]) == Pace.Strategy.END, "Gold Ship should close")
	_check(suzuka.preferred_style([0, 0, 0, 0]) == Pace.Strategy.FRONT, "Suzuka should lead")
	var boundaries := [0.0, Course.DISTANCE / 6.0, Course.DISTANCE * 2.0 / 3.0, Course.DISTANCE * 5.0 / 6.0]
	for stage in boundaries.size():
		var distance: float = boundaries[stage]
		_check(Pace.stage_at(distance) == stage and Pace.stage_at(distance - 0.001) == maxi(0, stage - 1),
			"Incorrect phase boundary %d" % stage)
		var front := Pace.new(build, Pace.Strategy.FRONT, false)
		var end := Pace.new(build, Pace.Strategy.END, false)
		front.update_limits(distance, 2.0, 4.9)
		end.update_limits(distance, 2.0, 4.9)
		if stage == Pace.Stage.OPENING:
			_check(front.speed_cap > end.speed_cap, "Front should get the quicker opening")
		if stage >= Pace.Stage.FINAL:
			_check(end.speed_cap > front.speed_cap, "End should get the quicker finish")
		for style in Pace.NAMES.size():
			var strategy := style as Pace.Strategy
			var grass := Pace.new(build, strategy, false)
			var mud := Pace.new(build, strategy, true)
			var other := Pace.new(suzuka, strategy, false)
			for pace: Pace in [grass, mud, other]:
				pace.update_limits(distance, 2.0, 4.9)
			_check(grass.speed_cap > mud.speed_cap and grass.acceleration > mud.acceleration, "Surface lost its effect")
			_check(not is_equal_approx(grass.speed_cap, other.speed_cap)
				and not is_equal_approx(grass.acceleration, other.acceleration), "Character lost her phase limits")
	var race := Pace.new(build, Pace.Strategy.LATE, false)
	race.update_limits(boundaries[2], 5.0, 4.9)
	var fresh := race.speed_cap
	var fresh_acceleration := race.acceleration
	var cruise_cost := Pace.new(build, Pace.Strategy.LATE, false)
	cruise_cost.spend(5.0, 10.0)
	race.pushing = true
	race.spend(5.0, 10.0)
	_check(race.energy < cruise_cost.energy, "Pushing should cost energy even at the same achieved pace")
	race.energy = race.capacity * 0.10
	race.update_limits(boundaries[2], 5.0, 4.9)
	_check(race.freshness < 1.0 and race.speed_cap <= fresh - 0.5
		and race.acceleration < fresh_acceleration * 0.85, "Low energy should materially weaken the final leg")
	race.spend(6.0, 1000.0)
	race.update_limits(boundaries[2], 5.0, 4.9)
	_check(race.energy == 0.0 and race.speed_cap < fresh and race.speed_cap > 0.0, "Exhaustion must allow a slower finish")
	print("Race pace checks %s." % ("failed" if failed else "passed"))
	quit(int(failed))


func _check(ok: bool, message: String) -> void:
	if not ok:
		printerr(message)
		failed = true
