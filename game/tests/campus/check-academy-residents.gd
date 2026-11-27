extends SceneTree

const Preferences := preload("res://game/app/game-preferences.gd")
const Campus := preload("res://game/campus/campus-walk.tscn")
const Population := preload("res://game/campus/academy-residents.gd")
const Clock := preload("res://game/campus/campus-time.gd")
const Roster := preload("res://game/ui/character-roster.gd")

var failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(1701)
	Preferences.show_npc_names = false
	var campus := Campus.instantiate()
	var population: Population = campus.get_node("Residents")
	population._random.seed = 1701
	root.add_child(campus)
	var player := population.player
	var clock: Clock = campus.get_node("CampusTime")
	clock.hour = 23.5
	clock._process(60.0)
	_check(is_equal_approx(clock.hour, 0.5), "One real minute should advance one game hour across midnight")
	clock.advance_phase()
	clock._process(Clock.FAST_FORWARD_SECONDS)
	_check(is_equal_approx(clock.hour, Clock.TIME_STOPS[0]), "Time skip did not reach dawn")

	await _ticks(2)
	var identities := {}
	for resident in population.residents:
		_check(not resident.path.is_empty(), "A test runner was registered as a resident")
		_check(not identities.has(resident.identity), "Alternate outfit duplicated a resident")
		identities[resident.identity] = true
	for path in Roster.paths():
		_check(identities.has(population._identity(path)), "Missing campus character " + path)
	if identities.is_empty():
		_check(population.get_child_count() == 0, "Campus spawned a placeholder without an installed roster")
		_finish(0)
		return

	var seen := {}
	for target in population.residents:
		var location := target.location if target.actor == null else target.actor.position
		player._recover_at(location + Vector3.UP * 0.05 + Vector3.BACK * 0.8)
		await _ticks(12)
		for resident in population.residents:
			if resident.actor == null:
				continue
			_check(resident.identity.is_empty() or resident.identity != population._identity(player.active_character_path),
				"Player also appeared as a resident")
			_check(resident.actor.active_character_path == resident.path and not resident.actor.model_proxy.visible,
				"Campus showed a placeholder for " + resident.title)
			seen[resident.title] = true
			_check(not resident.actor.has_node("CameraArm/Camera3D"), "Resident installed a player camera")
			var tags := resident.actor.find_children("*", "Label3D", false, false)
			_check(tags.size() == 1 and not tags[0].visible, "Campus NPC name was visible by default")
	for resident in population.residents:
		if resident.identity.is_empty() or resident.identity != population._identity(player.active_character_path):
			_check(seen.has(resident.title), "Could not encounter " + resident.title)

	var walker: Population.Resident
	for resident in population.residents:
		if resident.actor != null:
			walker = resident
			break
	if walker == null:
		_check(false, "No active NPC at the last location")
	else:
		await _check_player_contact(population, walker)
		await _check_passage(population, walker, Vector3(0.0, 0.008, -51.62), true)
		await _check_passage(population, walker, Vector3(-7.6, 4.877, -79.46), false)
		_check_wandering_choices(population, walker)
		player.competition = true
		await _ticks(2)
		_check(population.get_child_count() == 0, "Resident actors remained in the meet")
		Preferences.show_npc_names = true
		player.competition = false
		await _ticks(population.residents.size() + 2)
		_check(walker.actor != null, "Resident did not return after the meet")
		if walker.actor != null:
			var tags := walker.actor.find_children("*", "Label3D", false, false)
			_check(tags.size() == 1 and tags[0].visible, "NPC name stayed hidden after enabling it")
		_check(player.change_character(walker.path), "Character switch failed")
		await _ticks(2)
		_check(walker.actor == null, "Switching characters left a duplicate in the Academy")
	_finish(seen.size())


func _check_player_contact(population: Population, walker: Population.Resident) -> void:
	var player := population.player
	var feet := Vector3(0.0, 0.08, -10.0)
	walker.actor._recover_at(feet)
	walker.idle_left = 8.0
	player._recover_at(feet + Vector3.BACK * 2.0)
	player.camera_arm.rotation.y = 0.0
	await _ticks(8)
	var touched := false
	Input.action_press(&"move_forward")
	for step in 100:
		await physics_frame
		for collision in player.get_slide_collision_count():
			if player.get_slide_collision(collision).get_collider() == walker.actor:
				touched = true
	Input.action_release(&"move_forward")
	_check(touched and player.position.z > walker.actor.position.z + 0.52,
		"Player passed through an Academy resident")


func _check_passage(population: Population, walker: Population.Resident, start: Vector3, through_door: bool) -> void:
	var graph := population.walkways
	for edge in graph.passages.size():
		var passage := graph.passages[edge]
		if passage.points[0].distance_to(start) > 0.05 or (through_door and passage.door == null):
			continue
		if not through_door and absf(passage.points[-1].y - start.y) < 2.0:
			continue
		var feet := start + Vector3.UP * 0.06
		population.player._recover_at(feet + Vector3.BACK * 1.4)
		walker.actor._recover_at(feet)
		walker.place = passage.ends.x
		walker.idle_left = 0.0
		population._take_exit(walker, edge)
		for tick in 2400:
			await physics_frame
			if walker.place == passage.ends.y:
				break
		_check(walker.place == passage.ends.y, "NPC did not finish the passage from %s" % start)
		if through_door:
			_check(passage.door.opening > 0.99, "NPC did not open the entrance")
		return
	_check(false, "Missing passage at %s" % start)


func _check_wandering_choices(population: Population, walker: Population.Resident) -> void:
	for index in population.walkways.places.size():
		if population.walkways.places[index].exits.size() < 3:
			continue
		var choices := {}
		var previous := walker.place
		walker.place = index
		for step in 32:
			population._choose_exit(walker)
			choices[walker.current_exit] = true
		walker.place = previous
		walker.current_exit = -1
		_check(choices.size() > 1, "NPC repeatedly chose the same route at a junction")
		return
	_check(false, "Wandering network has no junctions")


func _finish(seen: int) -> void:
	print("Encountered %d Academy residents. Clock and population checks %s." % [
		seen, "failed" if failed else "passed"])
	quit(int(failed))


func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame


func _check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		printerr(message)
