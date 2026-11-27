extends SceneTree

const Course := preload("res://game/race/race-course.gd")
const Pace := preload("res://game/race/race-pace.gd")
const Progress := preload("res://game/race/race-progress.gd")
const Race := preload("res://game/race/running-race.gd")
const Lineup := preload("res://game/race/race-lineup.gd")
const Runner := preload("res://game/runner/runner.gd")
const Menu := preload("res://game/ui/meet-menu.gd")
const Roster := preload("res://game/ui/character-roster.gd")
const MENU_SCENE := "res://game/ui/meet-menu.tscn"

var failed := false
var race: Race


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_lap_rules()
	change_scene_to_file(MENU_SCENE)
	await scene_changed
	var menu := current_scene as Menu
	var paths := Roster.paths()
	var character := paths[1] if paths.size() > 1 else ""
	menu._set_character(character)
	menu._enter()
	await scene_changed
	var academy := current_scene
	race = academy.get_node("RunningRace")
	var player := race.player
	var original_mask := player.collision_mask
	_check(player.active_character_path == character, "Campus ignored character selection")
	var tread := race._field.get_node("RaceTread/Mesh") as MeshInstance3D
	var material := tread.get_active_material(0) as ShaderMaterial
	_check(material == race._field._race_surface, "The race should use one continuous tread")
	var signpost: Node3D = race._field.get_node("AmazonStartSign")
	_check(Course.project(signpost.global_position).y < Course.INNER_EDGE, "Sign must be inside the inner rail")
	var across := Course.forward_at(0.0).cross(Vector3.UP)
	_check(signpost.global_basis.z.dot(across) > 0.9999, "The sign should face across the track")
	await _ticks(2)
	_check_track_geometry()
	_check_start_grid()
	await _press_race()
	_check(not paused and race.phase == Race.Phase.IDLE, "Race entry should require the start stripe")

	player._recover_at(Vector3(Course.START_X, 0.08, -130.0))
	player.camera_arm.rotation.y = 0.0
	await _ticks(10)
	Input.action_press(&"move_forward")
	for step in 260:
		await physics_frame
		if player.race.at_start(player.global_position):
			break
	Input.action_release(&"move_forward")
	await _ticks(10)
	await _press_race()
	_check(paused and race._menu.visible, "Walking to the stripe did not unlock G")
	race._menu.close()
	_check(not paused and race.phase == Race.Phase.IDLE, "Cancel should return to exploration")
	await _press_race()
	_seed_for_gate(8)
	var first_picks := _choose_rivals(false)
	_check(race._player.gate == 8, "Race entry did not use the drawn gate")
	_check(race._selected_rivals == first_picks, "The selected rivals did not reach the start grid")
	_check(current_scene == academy and race._player.runner == player, "Race replaced the campus or player")
	await _check_collision()
	await _check_mouse_steering()
	await _check_style_locked()
	await _check_collision_recovery()
	_seed_for_gate(9)
	race._retry()
	_check(race._player.gate == 9, "Retry did not draw a new gate")
	_check(player.race_pace.strategy == race._opening_strategy and player.race_pace.energy == player.race_pace.capacity,
		"Retry must restore the opening style and full energy")
	var grass_time := await _finish_race(paths.size())
	race._leave()
	_check(current_scene == academy and not player.competition and player.race_pace == null, "Leaving a race should resume the same campus")
	_check(race.get_child_count() < 5 and player.collision_mask == original_mask, "Rivals or racing collision mask leaked into exploration")
	_check(tread.get_active_material(0) == material, "Leaving the race replaced the course surface")
	await _ticks(2)
	# The race finished at the stripe, so the same G entry can start Mudland.
	await _press_race()
	_check(paused and race._menu.visible, "Race entry did not reopen after finishing")
	_seed_for_gate(8)
	var mud_picks := _choose_rivals(true)
	_check(race._selected_rivals == mud_picks, "Mudland did not retain the chosen lineup")
	_check(tread.get_active_material(0) == material and material.get_shader_parameter("mudland"), "Mudland should recolor the same tread")
	var mud_time := await _finish_race(paths.size())
	_check(mud_time > grass_time * 1.10, "Mudland should slow the race")
	race._hud._finish._retry.pressed.emit()
	_check(race.phase == Race.Phase.COUNTDOWN and race._mudland and race._selected_rivals == mud_picks,
		"Retry did not keep the surface and all eight rivals")
	race._leave()
	_check(tread.get_active_material(0) == material and material.get_shader_parameter("mudland"),
		"Leaving Mudland changed the selected track material")
	print("Academy running race checks %s." % ("failed" if failed else "passed"))
	quit(int(failed))


func _choose_rivals(mudland: bool) -> Array[Lineup.Rival]:
	var entry := race._menu
	entry._clear()
	_check(entry._start_button.disabled, "Race can start with an incomplete field")
	for index in range(entry._candidates.size() - 8, entry._candidates.size()):
		entry._grid.select(index, false)
		entry._grid.multi_selected.emit(index, true)
	var picks: Array[Lineup.Rival] = entry.selected_rivals()
	_check(picks.size() == Lineup.RIVALS and not entry._start_button.disabled, "Eight chosen rivals did not unlock Start")
	var opening := entry._strategy
	for button in entry._strategy_buttons:
		button.pressed.emit()
		_check(button.button_pressed, "Race entry did not select the style")
	entry._strategy_buttons[opening].pressed.emit()
	entry._set_surface(mudland)
	entry._start_button.pressed.emit()
	_check(race.player.race_pace.strategy == opening, "Race ignored the entry style")
	for entrant in race._entrants.slice(1):
		var pace: Pace = entrant.runner.race_pace
		_check(pace.profile.styles[pace.strategy] == "A", "Rival chose a weaker style")
	return picks


func _seed_for_gate(gate: int) -> void:
	for draw_seed in 1000:
		seed(draw_seed)
		if randi_range(1, Race.GRID.size()) == gate:
			seed(draw_seed)
			return
	_check(false, "Could not seed gate %d" % gate)


func _check_start_grid() -> void:
	var rivals: Array[Lineup.Rival] = []
	for index in Lineup.RIVALS:
		rivals.append(Lineup.Rival.new("", "Academy runner %d" % (index + 1)))
	for gate in range(1, Race.GRID.size() + 1):
		_seed_for_gate(gate)
		race._start(false, rivals)
		_check(race._player.gate == gate and race._hud._summary.text == tr("Starting gate %d / %d") % [gate, 9],
			"Player and HUD disagree with gate %d" % gate)
		var offsets: Array[float] = []
		for entrant in race._entrants:
			offsets.append(Course.project(entrant.runner.position).y)
		offsets.sort()
		for index in offsets.size():
			_check(is_equal_approx(offsets[index], Race.GRID[index]) and Course.contains_offset(offsets[index]),
				"Missing or overlapping gate %d" % (index + 1))
		race._leave()


func _check_track_geometry() -> void:
	var space := race.player.get_world_3d().direct_space_state
	for offset: float in [Course.INNER_EDGE + 0.5, -12.0, -8.0, -4.0, 0.0, Course.HALF_WIDTH - 0.5]:
		var point := Course.point_at(-20.0, offset)
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP, point - Vector3.UP, 1)
		var hit := space.intersect_ray(query)
		_check(not hit.is_empty() and hit.collider.name == &"RaceTread", "Ground hit the old patchwork at offset %.1f" % offset)
	for offset: float in [Course.INNER_EDGE - 1.0, Course.HALF_WIDTH + 1.0]:
		var start := Course.point_at(-20.0) + Vector3.UP * 0.72
		var end := Course.point_at(-20.0, offset) + Vector3.UP * 0.72
		var query := PhysicsRayQueryParameters3D.create(start, end, 1)
		var hit := space.intersect_ray(query)
		var expected := &"InnerGuardRail" if offset < 0.0 else &"OuterGuardRail"
		_check(not hit.is_empty() and hit.collider.name == expected, "Missing guard rail on the %.1f m side" % offset)
	var stripe := Course.point_at(0.0) + Vector3.UP * 0.72
	var exit := Course.point_at(0.0, Course.HALF_WIDTH + 1.0) + Vector3.UP * 0.72
	var gap := PhysicsRayQueryParameters3D.create(stripe, exit, 1)
	_check(space.intersect_ray(gap).is_empty(), "The outer rail closed the Academy entrance")


func _press_race() -> void:
	Input.action_press(&"race")
	await _ticks(2)
	Input.action_release(&"race")
	await _ticks(2)


func _check_collision() -> void:
	while race.phase == Race.Phase.COUNTDOWN:
		await physics_frame
	var player := race.player
	var rival := race._entrants[-1].runner
	rival.movement_locked = true
	var start: float = Course.project(player.position).y
	var contacted := false
	Input.action_press(&"move_right")
	for step in 100:
		await physics_frame
		for collision_index in player.get_slide_collision_count():
			if player.get_slide_collision(collision_index).get_collider() == rival:
				contacted = true
	Input.action_release(&"move_right")
	_check(Course.project(player.position).y > start + 0.70, "The player was held in a starting lane")
	_check(contacted, "Player did not collide with the rival capsule")
	_check(player.position.distance_to(rival.position) >= 0.52, "Runner capsules passed through each other")


func _check_collision_recovery() -> void:
	_seed_for_gate(8)
	race._retry()
	while race.phase == Race.Phase.COUNTDOWN:
		await physics_frame
	var player := race.player
	for entrant in race._entrants.slice(1):
		entrant.runner.movement_locked = true
	var blocker := race._entrants[-1]
	var contact_distance := Race.START_OFFSET + 10.0
	var lane: float = Race.GRID[race._player.gate - 1]
	blocker.progress = Progress.new(contact_distance)
	blocker.runner._recover_at(Course.point_at(contact_distance, lane) + Vector3.UP * 0.06)
	var approached_at := 0.0
	var contacted := false
	Input.action_press(&"move_forward")
	for tick in 360:
		await physics_frame
		for index in player.get_slide_collision_count():
			if player.get_slide_collision(index).get_collider() == blocker.runner:
				contacted = true
				break
		if contacted:
			break
		approached_at = maxf(approached_at, player.get_real_velocity().slide(Vector3.UP).length())
	_check(contacted and approached_at > 3.5, "Recovery check did not hit a rival at running speed")
	# Hold the block briefly to check that recovery cannot punch through a rival.
	await _ticks(25)
	_check(player.position.distance_to(blocker.runner.position) >= 0.52, "Recovery crossed a blocked lane")
	blocker.runner._recover_at(Course.point_at(contact_distance, lane + 1.8) + Vector3.UP * 0.06)
	var recovery_ticks := 0
	while recovery_ticks < 450:
		await physics_frame
		recovery_ticks += 1
		if player.get_real_velocity().slide(Vector3.UP).length() >= approached_at * 0.90:
			break
	Input.action_release(&"move_forward")
	var recovery_seconds := float(recovery_ticks) / Engine.physics_ticks_per_second
	_check(recovery_seconds < 0.9, "Collision recovery took %.2f s after the lane cleared" % recovery_seconds)
	print("Collision recovery: %.2f s to regain 90%% of %.2f m/s" % [recovery_seconds, approached_at])


func _check_mouse_steering() -> void:
	var player := race.player
	var start := player.position
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(-PI * 0.5 / Runner.LOOK_SENSITIVITY, 0.0)
	mouse.screen_relative = mouse.relative
	if DisplayServer.get_name() == "headless":
		# The headless display never enters captured mouse mode.
		player.mouse_motion = mouse.screen_relative
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		Input.parse_input_event(mouse)
		Input.flush_buffered_events()
	Input.action_press(&"move_forward")
	await _ticks(70)
	Input.action_release(&"move_forward")
	_check(absf(player.camera_arm.rotation.y) < 0.03, "Mouse yaw was overridden in the race")
	_check(player.position.z < start.z - 0.75, "W did not follow the mouse toward the inside")
	_check(player.facing.global_basis.z.dot(Vector3.FORWARD) > 0.88, "Runner did not turn with mouse-directed movement")


func _check_style_locked() -> void:
	var pace := race.player.race_pace
	for index in Pace.NAMES.size():
		var event := InputEventKey.new()
		event.pressed = true
		event.keycode = (KEY_1 + index) as Key
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await _ticks(2)
		_check(pace.strategy == race._opening_strategy and race._hud._pace.text.contains(tr(Pace.NAMES[race._opening_strategy])),
			"Key %d changed the style chosen at entry" % (index + 1))
		event.pressed = false
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _finish_race(model_count: int) -> float:
	_check(race._entrants.size() == 9, "Expected the player and eight rivals")
	var used := {}
	for entrant in race._entrants:
		var path := entrant.runner.active_character_path
		if not path.is_empty():
			_check(not used.has(path), "A rival reused another entrant's model")
			used[path] = true
	if model_count >= 9:
		_check(used.size() == 9, "The installed roster should supply nine distinct models")
	var start := race.player.position
	Input.action_press(&"move_forward")
	Input.action_press(&"accelerate_run")
	await _ticks(60)
	_check(race.phase == Race.Phase.COUNTDOWN, "Countdown ended early")
	_check(race.player.position.distance_to(start) < 0.08, "Player moved before the start")
	while race.phase == Race.Phase.COUNTDOWN:
		await physics_frame
	await _ticks(110)
	Input.action_press(&"move_left")
	for tick in 720:
		_aim_player(Course.forward_at(race._player.course_position.x))
		await physics_frame
		if race._player.course_position.y < Course.INNER_EDGE + 1.55:
			break
	Input.action_release(&"move_left")
	_check(race._player.course_position.y < Course.INNER_EDGE + 2.2, "Gate %d could only reach track offset %.2f m" % [race._player.gate, race._player.course_position.y])
	for entrant in race._entrants.slice(1):
		_check(entrant.course_position.y < -5.5, "A rival failed to move inside on the opening straight or bend")
	var saw_wait := false
	var inner_progress := 0.0
	var previous := race._player.progress.distance
	for tick in 12800:
		var point := race._player.course_position
		var target := Course.point_at(point.x + 2.6, -15.0)
		if race._player.progress.finish_time < 0.0:
			_aim_player(target - race.player.position)
		await physics_frame
		if race._player.progress.finish_time >= 0.0 and race.phase != Race.Phase.FINISHED:
			saw_wait = true
			_check(not race._hud._finish.visible, "The results opened before the field finished")
		var progress: float = race._player.progress.distance
		if race._player.course_position.y < -10.0:
			inner_progress += progress - previous
		previous = progress
		if race.phase == Race.Phase.FINISHED:
			break
	Input.action_release(&"move_forward")
	Input.action_release(&"accelerate_run")
	var finish: float = race._player.progress.finish_time
	_check(saw_wait or race._rank() == race._entrants.size(), "An early finisher skipped waiting for the field")
	_check(finish > 105.0, "Race should require two full Academy laps")
	_check(race.phase == Race.Phase.FINISHED and race._hud._finish.visible, "Race never showed results")
	_check(race._player.progress.completed_laps() == 2, "Player finished before completing two laps")
	_check(inner_progress > Course.LAP, "Player could not keep racing on the inner circuits for a full lap")
	for entrant in race._entrants:
		_check(entrant.progress.finish_time > 0.0 and entrant.progress.completed_laps() == 2, "A runner did not finish both laps")
	var scores := race._hud._finish._finish_order
	_check(scores.size() == 9, "The results must show all nine runners")
	for index in range(1, scores.size()):
		_check(scores[index].seconds >= scores[index - 1].seconds, "The results were not in finish order")
	print("%s: %.2f s, rank %d, %d character models" % [
		"Mudland" if race._mudland else "Grassland", finish, race._rank(), used.size()])
	return finish


func _aim_player(direction: Vector3) -> void:
	var yaw := atan2(-direction.x, -direction.z)
	var turn := angle_difference(race.player.camera_arm.rotation.y, yaw)
	race.player.mouse_motion.x = -turn / Runner.LOOK_SENSITIVITY


func _check_lap_rules() -> void:
	for offset: float in [-2.1, Course.INNER_EDGE + 0.7]:
		for step in range(-10, ceili(Course.LAP * 2.0) + 10):
			var distance := step * 0.5
			var sample := Course.project(Course.point_at(distance, offset))
			var error := wrapf(sample.x - distance, -Course.LAP * 0.5, Course.LAP * 0.5)
			_check(absf(error) < 0.002 and absf(sample.y - offset) < 0.002, "Oval projection drifted")
	var progress := Progress.new(-1.0)
	_check(not progress.advance(Course.LAP * 0.5, 0.05, 0.05), "Accepted a shortcut across the oval")
	_check(progress.advance(Course.LAP - 1.3, 0.05, 0.05) and progress.distance < -1.0, "Reverse travel gained progress")
	for index in range(-5, ceili(Course.DISTANCE * 4.0) + 2):
		var distance := index * 0.25
		_check(progress.advance(fposmod(distance, Course.LAP), index * 0.05, 0.05), "Rejected valid course progress")
		if distance < Course.DISTANCE - 0.01:
			_check(progress.finish_time < 0.0, "Accepted an early finish")
	_check(progress.completed_laps() == 2 and progress.finish_time > 0.0, "Two valid laps did not finish")


func _ticks(ticks: int) -> void:
	for tick in ticks:
		await physics_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		printerr(message)
