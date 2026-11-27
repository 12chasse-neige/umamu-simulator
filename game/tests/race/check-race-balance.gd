extends SceneTree

const Race := preload("res://game/race/running-race.gd")
const Runner := preload("res://game/runner/runner.gd")
const Course := preload("res://game/race/race-course.gd")
const Pace := preload("res://game/race/race-pace.gd")
const Lineup := preload("res://game/race/race-lineup.gd")
const Session := preload("res://game/app/game-session.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	Session.character_selected = true
	Session.character_path = ""
	change_scene_to_file("res://game/campus/campus-walk.tscn")
	await scene_changed
	var race: Race = current_scene.get_node("RunningRace")
	var rivals: Array[Lineup.Rival] = []
	for index in Lineup.RIVALS:
		rivals.append(Lineup.Rival.new("", "Academy runner %d" % (index + 1)))

	var full_effort_wins := await _run_heats(race, rivals, false)
	var paced_wins := await _run_heats(race, rivals, true)
	print("Full effort won %d of 8 meets. Saving energy won %d of 8." % [full_effort_wins, paced_wins])
	quit(int(full_effort_wins < 0 or full_effort_wins >= 5 or paced_wins <= full_effort_wins))


func _run_heats(race: Race, rivals: Array[Lineup.Rival], save_energy: bool) -> int:
	var wins := 0
	for mudland: bool in [false, true]:
		for style in Pace.NAMES.size():
			race._start_at_gate(mudland, rivals, style as Pace.Strategy, 8)
			Input.action_press(&"move_forward")
			for tick in 14000:
				# The two drivers use the same line and vary only their effort.
				var fraction := race._player.progress.distance / Course.DISTANCE
				if not save_energy or fraction < 0.19 or fraction > 0.59:
					Input.action_press(&"accelerate_run")
				else:
					Input.action_release(&"accelerate_run")
				var point := race._player.course_position
				var target := Course.point_at(point.x + 3.6, Course.INNER_EDGE + 0.65)
				var direction := target - race.player.position
				var yaw := atan2(-direction.x, -direction.z)
				var turn := angle_difference(race.player.camera_arm.rotation.y, yaw)
				race.player.mouse_motion.x = -turn / Runner.LOOK_SENSITIVITY
				await physics_frame
				if race.phase == Race.Phase.FINISHED:
					break
			if race.phase != Race.Phase.FINISHED:
				printerr("Field failed to finish: ", mudland, " ", Pace.NAMES[style])
				return -1
			print("%s, %s, %s: place %d of 9, %.2f s" % [
				"Saving energy" if save_energy else "Full effort",
				"Mudland" if mudland else "Grassland", Pace.NAMES[style], race._rank(), race._player.progress.finish_time])
			wins += int(race._rank() == 1)
			race._leave()
			await physics_frame
	for action in [&"move_forward", &"accelerate_run"]:
		Input.action_release(action)
	return wins
